import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';

/// 本地课表快照：编解码 + 存取。
///
/// 课表接口（`xskb/xskb_list.do`）是按周次返回的，这里把**整学期每周**拿到的
/// 排课合并成一份 JSON 快照落盘；冷启动先读它把每周数据水合进内存，
/// 界面切周全部走本地，联网只发生在「补拉缺失的周 / 手动刷新」时。
///
/// JSON 结构（v1）：
/// ```json
/// {
///   "version": 1,
///   "savedAt": "2026-09-21T21:00:00.000",
///   "weeks": {
///     "4": [
///       {"n": "高等数学", "l": "J3-311", "t": "王可芸", "w": 1,
///        "sp": 1, "ep": 2, "sw": 4, "ew": 18, "c": "3", "k": "必修"}
///     ]
///   }
/// }
/// ```
///
/// `weeks` 的键是本地周次；某周没课就存空数组 —— 空周也要记下来，
/// 不然每次切到它都会再联网一次。存取全部**不抛异常**：快照坏了就当没存过，
/// 重新联网拉一遍就是了，不该让课表页打不开。
abstract final class TimetableCacheCodec {
  /// 快照结构版本；结构变更时递增，旧版本读出来按空处理。
  static const int version = 1;

  /// 把每周排课编码成快照 JSON。[savedAt] 落个时间戳方便排查「数据多旧」。
  static Map<String, Object?> encode(
    Map<int, List<CourseSession>> weeks, {
    DateTime? savedAt,
  }) => <String, Object?>{
    'version': version,
    'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
    'weeks': <String, Object?>{
      for (final MapEntry<int, List<CourseSession>> entry in weeks.entries)
        '${entry.key}': <Object?>[
          for (final CourseSession session in entry.value) _encodeSession(session),
        ],
    },
  };

  /// 从快照 JSON 还原每周排课。
  ///
  /// 宽容解析：版本不认、结构不对、单条字段缺到没法用的都**整条丢掉**，
  /// 其余照常还原 —— 快照是自己写的，宁可少几条也不要整份作废。
  static Map<int, List<CourseSession>> decode(Object? data) {
    if (data is! Map) {
      return const <int, List<CourseSession>>{};
    }
    if (data['version'] != version) {
      return const <int, List<CourseSession>>{};
    }
    final Object? weeks = data['weeks'];
    if (weeks is! Map) {
      return const <int, List<CourseSession>>{};
    }
    final Map<int, List<CourseSession>> result = <int, List<CourseSession>>{};
    for (final MapEntry<Object?, Object?> entry in weeks.entries) {
      final int? week = int.tryParse('${entry.key}');
      if (week == null || week < 1 || entry.value is! List) {
        continue;
      }
      result[week] = <CourseSession>[
        for (final Object? item in entry.value! as List<Object?>)
          if (_decodeSession(item) case final CourseSession session) session,
      ];
    }
    return result;
  }

  static Map<String, Object?> _encodeSession(CourseSession session) {
    final Map<String, Object?> json = <String, Object?>{
      'n': session.course.name,
      'l': session.course.location,
      't': session.course.teacher,
      'w': session.weekday,
      'sp': session.startPeriod,
      'ep': session.endPeriod,
      'sw': session.startWeek,
      'ew': session.endWeek,
    };
    // 可空字段缺省就不写，省一点体积。
    if (session.course.credits != null) {
      json['c'] = session.course.credits;
    }
    if (session.course.category != null) {
      json['k'] = session.course.category;
    }
    return json;
  }

  static CourseSession? _decodeSession(Object? data) {
    if (data is! Map) {
      return null;
    }
    final Object? name = data['n'];
    if (name is! String || name.trim().isEmpty) {
      return null; // 连课名都没有的条目没法用
    }
    final int? weekday = _intOf(data['w']);
    final int? startPeriod = _intOf(data['sp']);
    final int? endPeriod = _intOf(data['ep']);
    final int? startWeek = _intOf(data['sw']);
    final int? endWeek = _intOf(data['ew']);
    if (weekday == null ||
        startPeriod == null ||
        endPeriod == null ||
        startWeek == null ||
        endWeek == null) {
      return null;
    }
    return CourseSession(
      course: Course(
        name: name,
        location: data['l'] is String ? data['l'] as String : '',
        teacher: data['t'] is String ? data['t'] as String : '',
        credits: data['c'] is String ? data['c'] as String : null,
        category: data['k'] is String ? data['k'] as String : null,
      ),
      // 越界/起止颠倒的按自建课表同款规则就地摆正。
      weekday: weekday.clamp(1, 7),
      startPeriod: startPeriod.clamp(1, endPeriod),
      endPeriod: endPeriod.clamp(startPeriod, 30),
      startWeek: startWeek.clamp(1, endWeek),
      endWeek: endWeek.clamp(startWeek, 60),
    );
  }

  static int? _intOf(Object? value) =>
      value is int ? value : (value is String ? int.tryParse(value) : null);
}

/// 课表快照的存取口子（抽象出来方便测试用内存假实现替换）。
abstract class TimetableCacheStore {
  const TimetableCacheStore();

  /// 读快照；没存过 / 内容坏了都返回空表。
  Future<Map<int, List<CourseSession>>> read();

  /// 整份覆盖写入。
  Future<void> write(Map<int, List<CourseSession>> weeks);

  /// 清掉快照（换账号 / 退出登录时用）。
  Future<void> clear();
}

/// 落在 `shared_preferences` 里的实现（key [storageKey]）。
class PrefsTimetableCacheStore extends TimetableCacheStore {
  const PrefsTimetableCacheStore();

  /// 存储键；改结构时换新 key，旧数据自然作废。
  static const String storageKey = 'timetable_cache_v1';

  @override
  Future<Map<int, List<CourseSession>>> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return const <int, List<CourseSession>>{};
      }
      return TimetableCacheCodec.decode(jsonDecode(raw));
    } catch (error) {
      debugPrint('读取课表快照失败：$error');
      return const <int, List<CourseSession>>{};
    }
  }

  @override
  Future<void> write(Map<int, List<CourseSession>> weeks) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(TimetableCacheCodec.encode(weeks)),
      );
    } catch (error) {
      debugPrint('保存课表快照失败：$error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (error) {
      debugPrint('清除课表快照失败：$error');
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_course.dart';

/// 自建课程的本地存储。
///
/// 契约和 [JwAccountStore]、[ReminderStore] 一样：**任何方法都不抛异常**。
/// 读失败返回空列表、写失败静默 —— 存不上只是「下次打开少了几门自己加的课」，
/// 不该把 App 顶掉（写盘通常是用户刚点完「保存」时发生的）。
abstract interface class CustomCourseStore {
  /// 读本机保存的自建课程；没存过或读不出来时返回空列表。
  Future<List<CustomCourse>> read();

  /// 覆盖保存（整份列表，不是增量）。
  Future<void> write(List<CustomCourse> courses);
}

/// 默认实现：各平台的 `SharedPreferences`。
class PrefsCustomCourseStore implements CustomCourseStore {
  const PrefsCustomCourseStore();

  /// 存储键。带版本后缀：将来字段结构变了可以直接换键，不会读到旧结构。
  static const String storageKey = 'custom_courses_v1';

  @override
  Future<List<CustomCourse>> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return const <CustomCourse>[];
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <CustomCourse>[];
      }
      final List<CustomCourse> result = <CustomCourse>[];
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) {
          continue; // 单条结构不对就丢这一条，剩下的照读
        }
        final CustomCourse? course = CustomCourse.fromJson(item);
        if (course != null) {
          result.add(course);
        }
      }
      return result;
    } catch (error) {
      debugPrint('读取自建课程失败：$error');
      return const <CustomCourse>[];
    }
  }

  @override
  Future<void> write(List<CustomCourse> courses) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(<Map<String, dynamic>>[
          for (final CustomCourse course in courses) course.toJson(),
        ]),
      );
    } catch (error) {
      debugPrint('保存自建课程失败：$error');
    }
  }
}

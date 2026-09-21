import 'package:flutter/foundation.dart';

import 'course.dart';
import 'period.dart';

/// 用户自己添加的课程。
///
/// 为什么不直接塞 [CourseSession]：自建课程是**用户数据**，要一直留在本机
/// （见 `CustomCourseStore`）—— 刷新课表、换账号都不该把它冲掉；而教务系统抓回来的
/// 排课只是本次会话里的临时数据。显示时再 [toSession] 合并进网格，两边用同一套渲染。
@immutable
class CustomCourse {
  const CustomCourse({
    required this.id,
    required this.name,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.location = '',
    this.teacher = '',
    this.startWeek = minWeek,
    this.endWeek = defaultWeeks,
  });

  /// 新建课程默认占用的周次上限。
  ///
  /// 取 20 是因为它对应学期兜底值（`defaultTerm`）的总周数；用户改成别的范围随时可调。
  static const int defaultWeeks = 20;

  /// 节次下限。
  static const int minPeriod = 1;

  /// 节次上限：跟着节次表的长度走，别让自建课程落到时间轴下面去。
  static int get maxPeriod => Period.defaults.length;

  /// 周次下限。
  static const int minWeek = 1;

  /// 周次上限，和设置页里「总周数」可调的上限一致。
  static const int maxWeek = 30;

  /// 稳定标识，用来编辑 / 删除；创建后不再变。
  final String id;

  /// 课程名称。
  final String name;

  /// 星期几，取值 [DateTime.monday] ~ [DateTime.sunday]。
  final int weekday;

  /// 起始节次（含）。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 上课地点。可以为空。
  final String location;

  /// 任课教师。可以为空。
  final String teacher;

  /// 生效的起始周（含）。
  final int startWeek;

  /// 生效的结束周（含）。
  final int endWeek;

  /// 连续占用的节数。
  int get periodCount => endPeriod - startPeriod + 1;

  /// 节次描述，例如「第 3-4 节」。
  String get periodsLabel =>
      startPeriod == endPeriod ? '第 $startPeriod 节' : '第 $startPeriod-$endPeriod 节';

  /// 周次描述，例如「第 1-16 周」。
  String get weeksLabel =>
      startWeek == endWeek ? '第 $startWeek 周' : '第 $startWeek-$endWeek 周';

  /// 在第 [week] 周是否上课。
  bool isActiveInWeek(int week) => week >= startWeek && week <= endWeek;

  /// 转成网格能画的排课。
  ///
  /// 带上 [CourseSession.customId]，界面据此认出「这条是自己加的」，
  /// 从而在详情里给出编辑 / 删除入口。
  CourseSession toSession() => CourseSession(
    course: Course(name: name, location: location, teacher: teacher),
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    startWeek: startWeek,
    endWeek: endWeek,
    customId: id,
  );

  /// 复制并替换部分字段。
  CustomCourse copyWith({
    String? id,
    String? name,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    String? location,
    String? teacher,
    int? startWeek,
    int? endWeek,
  }) => CustomCourse(
    id: id ?? this.id,
    name: name ?? this.name,
    weekday: weekday ?? this.weekday,
    startPeriod: startPeriod ?? this.startPeriod,
    endPeriod: endPeriod ?? this.endPeriod,
    location: location ?? this.location,
    teacher: teacher ?? this.teacher,
    startWeek: startWeek ?? this.startWeek,
    endWeek: endWeek ?? this.endWeek,
  );

  /// 存档用的字段表。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'weekday': weekday,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'location': location,
    'teacher': teacher,
    'startWeek': startWeek,
    'endWeek': endWeek,
  };

  /// 从存档还原一条课程。
  ///
  /// 字段缺失或越界时**就地钳制**，只有「连名字都没有」才返回 null ——
  /// 存档是用户手打出来的东西，宁可把一条坏数据修好，也不要整个丢掉。
  static CustomCourse? fromJson(Map<String, dynamic> json) {
    final String id = _string(json['id']);
    final String name = _string(json['name']).trim();
    if (id.isEmpty || name.isEmpty) {
      return null;
    }
    final int startPeriod = _clampInt(json['startPeriod'], minPeriod, maxPeriod);
    final int startWeek = _clampInt(json['startWeek'], minWeek, maxWeek);
    return CustomCourse(
      id: id,
      name: name,
      weekday: _clampInt(json['weekday'], DateTime.monday, DateTime.sunday),
      startPeriod: startPeriod,
      // 结束节次不能小于起始节次，否则卡片会算出负高度。
      endPeriod: _clampInt(json['endPeriod'], startPeriod, maxPeriod),
      location: _string(json['location']),
      teacher: _string(json['teacher']),
      startWeek: startWeek,
      endWeek: _clampInt(json['endWeek'], startWeek, maxWeek),
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  /// 读一个整数并钳制到 `[min, max]`；读不出来时取 `min`。
  static int _clampInt(Object? value, int min, int max) {
    final int raw = switch (value) {
      final num number => number.round(),
      final String text => int.tryParse(text.trim()) ?? min,
      _ => min,
    };
    if (raw < min) {
      return min;
    }
    return raw > max ? max : raw;
  }

  @override
  bool operator ==(Object other) =>
      other is CustomCourse &&
      other.id == id &&
      other.name == name &&
      other.weekday == weekday &&
      other.startPeriod == startPeriod &&
      other.endPeriod == endPeriod &&
      other.location == location &&
      other.teacher == teacher &&
      other.startWeek == startWeek &&
      other.endWeek == endWeek;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    weekday,
    startPeriod,
    endPeriod,
    location,
    teacher,
    startWeek,
    endWeek,
  );

  @override
  String toString() => 'CustomCourse($id, $name, 周$weekday $periodsLabel $weeksLabel)';
}

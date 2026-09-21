import 'package:flutter/foundation.dart';

/// 一门课程的基础信息。
@immutable
class Course {
  const Course({
    required this.name,
    required this.location,
    this.teacher = '',
    this.credits,
    this.category,
  });

  /// 课程名称。
  final String name;

  /// 上课地点。
  final String location;

  /// 任课教师。
  ///
  /// 来自课表接口格子里的「老师」字段；多位老师时是逗号分隔的一串。
  final String teacher;

  /// 学分，例如「3」。
  final String? credits;

  /// 课程属性，例如「必修」「选修」。
  final String? category;

  /// 是否有教师信息可显示。
  bool get hasTeacher => teacher.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is Course &&
      other.name == name &&
      other.teacher == teacher &&
      other.location == location;

  @override
  int get hashCode => Object.hash(name, teacher, location);
}

/// 一次具体的排课：某门课在星期几的第几节到第几节，以及在哪些周次生效。
@immutable
class CourseSession {
  const CourseSession({
    required this.course,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.startWeek = 1,
    this.endWeek = 20,
    this.customId,
  });

  /// 课程信息。
  final Course course;

  /// 星期几，取值 [DateTime.monday] ~ [DateTime.sunday]。
  final int weekday;

  /// 起始节次（含）。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 生效的起始周（含）。
  final int startWeek;

  /// 生效的结束周（含）。
  final int endWeek;

  /// 这条排课是不是用户自己添加的（对应 `CustomCourse.id`）；null 表示来自教务系统。
  ///
  /// 网格里的课来自两处：教务系统抓回来的，以及用户自己敲进去的。两者长得一样，
  /// 但**只有后者能改能删**，所以把来源直接标在数据上，界面不必去猜。
  final String? customId;

  /// 连续占用的节数。
  int get periodCount => endPeriod - startPeriod + 1;

  /// 是否是自己添加的课程。
  bool get isCustom => customId != null;

  /// 该排课在第 [week] 周是否上课。
  bool isActiveInWeek(int week) => week >= startWeek && week <= endWeek;

  /// 周次描述，例如「第 1-8 周」。
  String get weeksLabel =>
      startWeek == endWeek ? '第 $startWeek 周' : '第 $startWeek-$endWeek 周';

  /// 节次描述，例如「第三-四节」。
  String get periodsLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod-$endPeriod 节';

  /// 复制并替换部分字段。
  CourseSession copyWith({
    Course? course,
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    int? startWeek,
    int? endWeek,
    String? customId,
  }) => CourseSession(
    course: course ?? this.course,
    weekday: weekday ?? this.weekday,
    startPeriod: startPeriod ?? this.startPeriod,
    endPeriod: endPeriod ?? this.endPeriod,
    startWeek: startWeek ?? this.startWeek,
    endWeek: endWeek ?? this.endWeek,
    customId: customId ?? this.customId,
  );
}

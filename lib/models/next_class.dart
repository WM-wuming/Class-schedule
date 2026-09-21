import 'package:flutter/foundation.dart';

import 'course.dart';
import 'period.dart';
import 'week.dart';

/// 桌面小组件要显示的一条「接下来要上的课」。
///
/// 小组件是原生的 `AppWidgetProvider`（RemoteViews），它不会算周次、也不会认得
/// 教务数据 —— Flutter 侧把「接下来几天要上的课」换算成带真实时间戳的条目推过去，
/// 原生只负责按当前时间挑一条显示。见 `android/.../NextClassWidgetProvider.kt`。
@immutable
class NextClassEntry {
  const NextClassEntry({
    required this.start,
    required this.end,
    required this.name,
    required this.location,
    required this.teacher,
    required this.periodLabel,
    required this.timeLabel,
    required this.dayLabel,
  });

  final DateTime start;
  final DateTime end;
  final String name;
  final String location;
  final String teacher;

  /// 节次描述，例如「第 3-4 节」。
  final String periodLabel;

  /// 时刻描述，例如「10:15-11:50」。
  final String timeLabel;

  /// 相对今天的天数描述：「今天」「明天」「后天」。
  final String dayLabel;

  Map<String, Object> toJson() => <String, Object>{
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'name': name,
    'location': location,
    'teacher': teacher,
    'period': periodLabel,
    'time': timeLabel,
    'day': dayLabel,
  };

  @override
  bool operator ==(Object other) =>
      other is NextClassEntry &&
      other.start == start &&
      other.end == end &&
      other.name == name &&
      other.location == location &&
      other.teacher == teacher &&
      other.periodLabel == periodLabel &&
      other.timeLabel == timeLabel &&
      other.dayLabel == dayLabel;

  @override
  int get hashCode => Object.hash(
    start, end, name, location, teacher, periodLabel, timeLabel, dayLabel);
}

/// 往后数几天内找「接下来要上的课」。
///
/// - 只保留「还没下课」的节次（正在上的课也在内，原生会把它显示成「正在上课」）；
/// - 按开始时间升序，第一条就是小组件要突出显示的那条；
/// - 学期外（假期）或三天内都没课 → 空列表，原生据此显示「没有课了可以放心玩了！」。
List<NextClassEntry> buildNextClassEntries({
  required Term term,
  required List<CourseSession> Function(int week) sessionsOf,
  required DateTime now,
  int horizonDays = 3,
}) {
  final List<NextClassEntry> entries = <NextClassEntry>[];
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<String> dayLabels = <String>['今天', '明天', '后天'];

  for (int offset = 0; offset < horizonDays; offset++) {
    final DateTime day = today.add(Duration(days: offset));
    final int week = term.weekOf(day);
    if (week < 1 || week > term.totalWeeks) {
      continue; // 假期
    }
    final List<CourseSession> sessions =
        sessionsOf(week).where((CourseSession s) => s.weekday == day.weekday).toList()
          ..sort((CourseSession a, CourseSession b) {
            final int byStart = a.startPeriod.compareTo(b.startPeriod);
            return byStart != 0 ? byStart : a.endPeriod.compareTo(b.endPeriod);
          });
    for (final CourseSession session in sessions) {
      final Period startPeriod = _periodAt(session.startPeriod);
      final Period endPeriod = _periodAt(session.endPeriod);
      final DateTime start = _at(day, startPeriod.start);
      final DateTime end = _at(day, endPeriod.end);
      if (!end.isAfter(now)) {
        continue; // 已下课的不再出现
      }
      entries.add(
        NextClassEntry(
          start: start,
          end: end,
          name: session.course.name,
          location: session.course.location,
          teacher: session.course.teacher,
          periodLabel: session.periodsLabel,
          timeLabel: '${startPeriod.start}-${endPeriod.end}',
          dayLabel: dayLabels[offset],
        ),
      );
    }
  }
  return entries;
}

/// 学期从周日开始排（见 [Term.startOfWeek]），星期几换算成相对周日的偏移。
Period _periodAt(int index) =>
    Period.defaults[(index - 1).clamp(0, Period.defaults.length - 1)];

DateTime _at(DateTime day, String hhmm) {
  final List<String> parts = hhmm.split(':');
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}

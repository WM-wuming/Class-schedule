import 'package:flutter/foundation.dart';

/// 课表里的一列，也就是一周中的某一天。
@immutable
class ScheduleDay {
  const ScheduleDay({required this.weekday, required this.date});

  /// 星期几，取值 [DateTime.monday] ~ [DateTime.sunday]。
  final int weekday;

  /// 这一天对应的日期。
  final DateTime date;

  /// 表头第一行：一、二、三……
  String get label => const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  /// 表头第二行：9/20。
  String get dateLabel => '${date.month}/${date.day}';

  /// 是否为周末。
  bool get isWeekend =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;

  @override
  bool operator ==(Object other) =>
      other is ScheduleDay && other.weekday == weekday && other.date == date;

  @override
  int get hashCode => Object.hash(weekday, date);
}

/// 学期的时间设置，负责周次与日期的换算。
@immutable
class Term {
  const Term({required this.startDate, this.totalWeeks = 20});

  /// 第 1 周周日的日期（本课表以周日为一周的第一天）。
  final DateTime startDate;

  /// 学期总周数。
  final int totalWeeks;

  /// 第 [week] 周的第一天（周日）零点。
  DateTime startOfWeek(int week) => _dateOnly(
    startDate,
  ).add(Duration(days: (week - 1) * 7));

  /// 第 [week] 周的最后一天（周六）零点。
  DateTime endOfWeek(int week) => startOfWeek(week).add(const Duration(days: 6));

  /// [date] 落在第几周。早于开学日期时返回小于 1 的值。
  int weekOf(DateTime date) {
    final difference = _dateOnly(date).difference(_dateOnly(startDate)).inDays;
    return (difference / 7).floor() + 1;
  }

  /// 学期内有效的周次，从 1 到 [totalWeeks]。
  List<int> get weeks =>
      List<int>.generate(totalWeeks, (int index) => index + 1);

  /// 第 [week] 周的日期范围描述，例如「9/20 - 9/26」。
  String rangeLabelOf(int week) {
    final start = startOfWeek(week);
    final end = endOfWeek(week);
    return '${start.month}/${start.day} - ${end.month}/${end.day}';
  }

  /// 第 [week] 周要显示的列，按周日到周六排列。
  List<ScheduleDay> daysOf(int week, {bool includeWeekend = true}) {
    final start = startOfWeek(week);
    return List<ScheduleDay>.generate(7, (int index) {
      final date = start.add(Duration(days: index));
      return ScheduleDay(weekday: date.weekday, date: date);
    }).where((ScheduleDay day) => includeWeekend || !day.isWeekend).toList();
  }

  /// 根据新的开学日期 / 总周数生成一份新设置。
  Term copyWith({DateTime? startDate, int? totalWeeks}) => Term(
    startDate: startDate ?? this.startDate,
    totalWeeks: totalWeeks ?? this.totalWeeks,
  );

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  bool operator ==(Object other) =>
      other is Term &&
      other.startDate == startDate &&
      other.totalWeeks == totalWeeks;

  @override
  int get hashCode => Object.hash(startDate, totalWeeks);
}

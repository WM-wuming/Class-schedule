import 'package:flutter/widgets.dart';

import '../models/week.dart';
import '../theme/course_palette.dart';
import 'timetable_grid.dart';

/// 课表顶部的日期条：左侧留白对齐网格的节次列 + 每天的表头，今天会高亮。
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
    this.todayWeekday,
    this.onDayTap,
  });

  /// 要显示的日期列。
  final List<ScheduleDay> days;

  /// 今天对应的星期几。
  final int? todayWeekday;

  /// 点击某一天。
  final ValueChanged<ScheduleDay>? onDayTap;

  /// 日期条高度（设计稿尺寸，会随字号缩放）。
  static const double height = 50;

  @override
  Widget build(BuildContext context) {
    final TimetableScale scale = TimetableScale.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: GridColors.surface,
        border: Border(bottom: BorderSide(color: GridColors.divider)),
      ),
      child: SizedBox(
        height: scale.px(height),
        child: Row(
          children: <Widget>[
            // 与网格左侧的节次列等宽，让日期列和下面的格子严格对齐。
            SizedBox(width: scale.px(TimetableGrid.gutterWidth)),
            for (final ScheduleDay day in days)
              Expanded(
                child: _DayHeader(
                  day: day,
                  isToday: todayWeekday == day.weekday,
                  onTap: onDayTap == null ? null : () => onDayTap!(day),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday, this.onTap});

  final ScheduleDay day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TimetableScale scale = TimetableScale.of(context);
    final Color foreground = isToday
        ? const Color(0xFFFFFFFF)
        : GridColors.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          // 横向留白不跟字号缩放：列宽是天平分的，跟着放大就把日期挤掉了。
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: scale.px(4)),
          decoration: BoxDecoration(
            color: isToday ? GridColors.today : null,
            borderRadius: BorderRadius.circular(scale.px(10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                day.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              SizedBox(height: scale.px(2)),
              Text(
                day.dateLabel,
                style: TextStyle(color: foreground, fontSize: 11, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

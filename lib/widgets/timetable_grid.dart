import 'package:flutter/widgets.dart';

import '../models/course.dart';
import '../models/period.dart';
import '../models/week.dart';
import '../theme/course_palette.dart';

/// 课表的排版尺度。
///
/// 课表里的**字**是 Flutter 按系统的字号设置（[MediaQuery.textScaler]）自动放大缩小的，
/// 但网格一直按固定像素画（每节 [TimetableGrid.periodHeight] 高、时间轴
/// [TimetableGrid.gutterWidth] 宽）：字号一调大，字就会被固定尺寸的格子裁掉，
/// 看起来像「字变大了界面没变」。
///
/// 所以这里取出同一个缩放系数，也用到格子的尺寸上 —— **格子、间距和字一起等比例
/// 放大缩小**：界面字号调大，课表跟着变大；调小，课表跟着收紧。
///
/// 只缩放「竖向 + 时间轴宽度」：列宽是由屏幕宽度天平分的，横向再撑就把课程名
/// 挤没了，所以列与列之间的分隔 [TimetableGrid.columnInset] 保持固定。
@immutable
class TimetableScale {
  const TimetableScale(this.factor);

  /// 按当前上下文的系统字号设置推导。
  factory TimetableScale.of(BuildContext context) =>
      TimetableScale.fromScaler(MediaQuery.textScalerOf(context));

  /// 从一个字号缩放器推导，效果同 [TimetableScale.of]，只是不依赖上下文。
  factory TimetableScale.fromScaler(TextScaler scaler) {
    final double factor = scaler.scale(referenceFontSize) / referenceFontSize;
    return TimetableScale(factor.clamp(minFactor, maxFactor));
  }

  /// 参照字号：课程名的字号。网格尺寸按它的缩放比例等比换算。
  static const double referenceFontSize = 13;

  /// 缩放系数下限：贴着系统「最小字号」。
  static const double minFactor = 0.85;

  /// 缩放系数上限：再放大列宽就只剩两三个字了，
  /// 宁可让卡片里的内容用省略号收尾，也要保住一屏能放下 7 天。
  static const double maxFactor = 1.6;

  /// 缩放系数，`1.0` 就是设计稿尺寸。
  final double factor;

  /// 把设计稿上的像素换算成当前尺度下的实际像素。
  double px(double design) => design * factor;

  @override
  bool operator ==(Object other) =>
      other is TimetableScale && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;

  @override
  String toString() => 'TimetableScale(${factor.toStringAsFixed(2)}x)';
}

/// 把节次和休息行换算成像素位置，保证左侧时间轴和课程块严格对齐。
///
/// 这里的尺寸都是**当前尺度下的实际像素**；设计稿尺寸 → 实际尺寸的换算在
/// [GridMetrics.scaled] 里统一做。课程卡片内部的留白与间距不在这里，
/// 那是 [CourseBlock] 自己的事。
@immutable
class GridMetrics {
  const GridMetrics({
    required this.periods,
    this.periodHeight = TimetableGrid.periodHeight,
    this.breakHeight = TimetableGrid.breakHeight,
  });

  /// 按当前界面的字号尺度，把设计稿尺寸换算成实际尺寸。
  factory GridMetrics.scaled({
    required List<Period> periods,
    required TimetableScale scale,
  }) => GridMetrics(
    periods: periods,
    periodHeight: scale.px(TimetableGrid.periodHeight),
    breakHeight: scale.px(TimetableGrid.breakHeight),
  );

  /// 节次表。
  final List<Period> periods;

  /// 每一节的高度。
  final double periodHeight;

  /// 午休分隔行的高度。
  final double breakHeight;

  /// 整个网格的高度。
  double get totalHeight {
    var height = 0.0;
    for (final Period period in periods) {
      height += periodHeight;
      if (period.breakAfter != null) {
        height += breakHeight;
      }
    }
    return height;
  }

  /// 第 [periodIndex] 节顶部相对网格顶部的位置。
  double topOf(int periodIndex) {
    var top = 0.0;
    for (final Period period in periods) {
      if (period.index >= periodIndex) {
        break;
      }
      top += periodHeight;
      if (period.breakAfter != null) {
        top += breakHeight;
      }
    }
    return top;
  }

  /// 从 [startPeriod] 到 [endPeriod]（含）的课程块高度，中间的休息行计入其中。
  double heightOf(int startPeriod, int endPeriod) {
    var height = 0.0;
    for (final Period period in periods) {
      if (period.index < startPeriod || period.index > endPeriod) {
        continue;
      }
      height += periodHeight;
      if (period.breakAfter != null && period.index < endPeriod) {
        height += breakHeight;
      }
    }
    return height;
  }
}

/// 课表网格：左侧节次时间轴 + 每天一列，课程块按节次跨行显示。
class TimetableGrid extends StatefulWidget {
  const TimetableGrid({
    super.key,
    required this.days,
    required this.periods,
    required this.sessions,
    required this.currentWeek,
    this.todayWeekday,
    this.dimInactiveCourses = true,
    this.showTeacher = true,
    this.showPeriodTime = true,
    this.onSessionTap,
  });

  /// 要显示的日期列。
  final List<ScheduleDay> days;

  /// 节次表。
  final List<Period> periods;

  /// 全部排课。
  final List<CourseSession> sessions;

  /// 正在查看的周次，用于判断排课是否在本周生效。
  final int currentWeek;

  /// 今天对应的星期几，用于高亮；为 null 时不高亮。
  final int? todayWeekday;

  /// 是否淡化本周不上课的课程。
  final bool dimInactiveCourses;

  /// 是否在课程卡片上显示教师。
  final bool showTeacher;

  /// 是否在时间轴上显示起止时间。
  final bool showPeriodTime;

  /// 点击课程卡片的回调。
  final ValueChanged<CourseSession>? onSessionTap;

  /// 左侧时间轴的宽度（设计稿尺寸，会随字号缩放）。
  static const double gutterWidth = 40;

  /// 每一节的高度（设计稿尺寸，会随字号缩放）。
  static const double periodHeight = 62;

  /// 休息行的高度（设计稿尺寸，会随字号缩放）。
  static const double breakHeight = 26;

  /// 相邻两节课之间空出的距离（设计稿尺寸，会随字号缩放）。
  static const double blockGap = 4;

  /// 课程块离本列左右边缘的距离。
  ///
  /// 横向**不**跟字号缩放：列宽是屏幕宽度天平分出来的，这 3px 是分隔线，
  /// 不是放字的地方，跟着放大只会挤掉课程名。
  static const double columnInset = 3;

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TimetableScale scale = TimetableScale.of(context);
    final GridMetrics metrics = GridMetrics.scaled(
      periods: widget.periods,
      scale: scale,
    );

    return RawScrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          height: metrics.totalHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: scale.px(TimetableGrid.gutterWidth),
                child: _Gutter(
                  metrics: metrics,
                  showPeriodTime: widget.showPeriodTime,
                ),
              ),
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (final ScheduleDay day in widget.days)
                      Expanded(
                        child: _DayColumn(
                          day: day,
                          metrics: metrics,
                          sessions: widget.sessions
                              .where(
                                (CourseSession session) =>
                                    session.weekday == day.weekday,
                              )
                              .toList()
                            ..sort(
                              (CourseSession a, CourseSession b) =>
                                  a.startPeriod.compareTo(b.startPeriod),
                            ),
                          currentWeek: widget.currentWeek,
                          isToday: widget.todayWeekday == day.weekday,
                          dimInactiveCourses: widget.dimInactiveCourses,
                          showTeacher: widget.showTeacher,
                          onSessionTap: widget.onSessionTap,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左侧节次时间轴。
class _Gutter extends StatelessWidget {
  const _Gutter({required this.metrics, required this.showPeriodTime});

  final GridMetrics metrics;
  final bool showPeriodTime;

  @override
  Widget build(BuildContext context) {
    final TimetableScale scale = TimetableScale.of(context);

    return ColoredBox(
      color: GridColors.gutter,
      // 文字在时间轴里水平居中，与右边课程列的内容拉开视觉距离。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (final Period period in metrics.periods) ...<Widget>[
            SizedBox(
              height: metrics.periodHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GridColors.textPrimary,
                      fontSize: 11,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (showPeriodTime) ...<Widget>[
                    SizedBox(height: scale.px(3)),
                    Text(
                      period.start,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: GridColors.textSecondary,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      period.end,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: GridColors.textSecondary,
                        fontSize: 10,
                        height: 1.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (period.breakAfter != null)
              SizedBox(
                height: metrics.breakHeight,
                child: DecoratedBox(
                  // 休息行也要压一条下边线：否则它看起来是「贴着下面一节」的，
                  // 与它自己顶部那条线不对称。
                  decoration: const BoxDecoration(
                    color: GridColors.breakBand,
                    border: Border(
                      bottom: BorderSide(color: GridColors.divider),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      period.breakAfter!,
                      style: const TextStyle(
                        color: GridColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 一天的课程列。
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.metrics,
    required this.sessions,
    required this.currentWeek,
    required this.isToday,
    required this.dimInactiveCourses,
    required this.showTeacher,
    required this.onSessionTap,
  });

  final ScheduleDay day;
  final GridMetrics metrics;
  final List<CourseSession> sessions;
  final int currentWeek;
  final bool isToday;
  final bool dimInactiveCourses;
  final bool showTeacher;
  final ValueChanged<CourseSession>? onSessionTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? GridColors.todayColumn : GridColors.surface,
        border: const Border(
          right: BorderSide(color: GridColors.divider),
        ),
      ),
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              for (final Period period in metrics.periods) ...<Widget>[
                SizedBox(
                  height: metrics.periodHeight,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: GridColors.divider),
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
                if (period.breakAfter != null)
                  SizedBox(
                    height: metrics.breakHeight,
                    child: const DecoratedBox(
                      // 与上一节底部的线配成一对，把休息行夹成一条完整的分隔带。
                      decoration: BoxDecoration(
                        color: GridColors.breakBand,
                        border: Border(
                          bottom: BorderSide(color: GridColors.divider),
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  ),
              ],
            ],
          ),
          for (final CourseSession session in sessions)
            Positioned(
              top: metrics.topOf(session.startPeriod),
              height: metrics.heightOf(session.startPeriod, session.endPeriod),
              left: TimetableGrid.columnInset,
              right: TimetableGrid.columnInset,
              child: CourseBlock(
                session: session,
                dimmed: dimInactiveCourses && !session.isActiveInWeek(currentWeek),
                showTeacher: showTeacher,
                onTap: onSessionTap == null
                    ? null
                    : () => onSessionTap!(session),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一个课程卡片。
///
/// 卡片本身占满它所在的节次格子，但上下各让出半个 [gap]（透明的），
/// 于是相邻两节课之间就空出一整段 —— 看起来是分开的，不会粘成一片。
class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.session,
    this.gap = TimetableGrid.blockGap,
    this.dimmed = false,
    this.showTeacher = true,
    this.onTap,
  });

  /// 这条排课。
  final CourseSession session;

  /// 与上下相邻课程之间留出的空隙（设计稿像素，会随字号缩放）。
  final double gap;

  /// 是否淡化显示（本周不上课）。
  final bool dimmed;

  /// 是否显示教师。
  final bool showTeacher;

  /// 点击回调。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CourseColor color = CoursePalette.of(session.course.name);
    final bool compact = session.periodCount < 2;
    final TimetableScale scale = TimetableScale.of(context);
    final double radius = scale.px(8);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: scale.px(gap) / 2),
      child: Opacity(
        opacity: dimmed ? 0.32 : 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.fill,
              borderRadius: BorderRadius.circular(radius),
              border: Border(
                left: BorderSide(color: color.accent, width: scale.px(3)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  scale.px(6),
                  scale.px(5),
                  4,
                  scale.px(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      // 不限行数：课程名完整显示，超出格高的部分由外层
                      // ClipRRect 静默裁掉（不出现「...」）。
                      session.course.name,
                      style: TextStyle(
                        color: color.accent,
                        fontSize: 13,
                        height: 1.18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: scale.px(3)),
                    Text(
                      '@${session.course.location}',
                      style: const TextStyle(
                        color: GridColors.textSecondary,
                        fontSize: 10.5,
                        height: 1.2,
                      ),
                    ),
                    if (!compact && showTeacher)
                      Text(
                        session.course.teacher,
                        style: const TextStyle(
                          color: GridColors.textSecondary,
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

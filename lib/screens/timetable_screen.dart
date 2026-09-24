import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/course.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/course_form.dart';
import '../widgets/home_nav.dart';
import '../widgets/sheets.dart';
import '../widgets/timetable_grid.dart';
import '../widgets/week_picker.dart';
import '../widgets/week_strip.dart';
import 'login_screen.dart';

/// 课表首页。
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// 当前 Tab（底部导航高亮用）。
  final HomeTab currentTab;

  /// 切换 Tab。
  final ValueChanged<HomeTab> onSelectTab;

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  /// 是否正显示「放假啦」彩蛋页 —— 逻辑上它是「第 totalWeeks+1 周」的虚拟页，
  /// 只有当前周停在最后一周时才成立；用户从周次选择器跳走就自动消失。
  bool _showHoliday = false;

  void _handleSwipe(ScheduleController controller, double velocity) {
    final bool holidayVisible =
        _showHoliday && controller.currentWeek == controller.term.totalWeeks;
    if (velocity > 220) {
      // 右滑 = 往回翻：放假页退回最后一周，其余照常上一周。
      if (holidayVisible) {
        setState(() {
          _showHoliday = false;
        });
      } else {
        controller.previousWeek();
      }
    } else if (velocity < -220) {
      // 左滑 = 往后翻：最后一周之后是「放假啦」，放假页再往后翻回第 1 周。
      if (holidayVisible) {
        setState(() {
          _showHoliday = false;
        });
        controller.goToWeek(1);
      } else if (controller.currentWeek >= controller.term.totalWeeks) {
        setState(() {
          _showHoliday = true;
        });
      } else {
        controller.nextWeek();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final AppSettings settings = controller.settings;
    final int lastWeek = controller.term.totalWeeks;
    final bool holidayVisible =
        _showHoliday && controller.currentWeek == lastWeek;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        // 标题与周次胶囊并排一行（标题在左），头部从两行缩成一行，课表整体上移。
        titleAlignment: Alignment.centerLeft,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '广应科课表',
              style: TextStyle(
                color: GridColors.textPrimary,
                fontSize: 19,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            WeekPickerPill(controller: controller),
          ],
        ),
        suffixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.refreshCw, size: 20),
            onPress: controller.refresh,
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.clock, size: 20),
            onPress: () => showTodaySchedule(context, controller: controller),
          ),
        ],
      ),
      footer: homeNavBar(
        context: context,
        current: widget.currentTab,
        onSelect: widget.onSelectTab,
      ),
      child: holidayVisible
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (DragEndDetails details) =>
                  _handleSwipe(controller, details.primaryVelocity ?? 0),
              child: _HolidayView(lastWeek: lastWeek),
            )
          : Column(
              children: <Widget>[
                WeekStrip(
                  days: controller.days,
                  todayWeekday: controller.todayWeekday,
                ),
                _StatusBanner(controller: controller),
                Expanded(
                  child: ColoredBox(
                    color: GridColors.page,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (DragEndDetails details) =>
                          _handleSwipe(
                            controller,
                            details.primaryVelocity ?? 0,
                          ),
                      child: Stack(
                        children: <Widget>[
                          if (controller.isReady || controller.isLoading)
                            TimetableGrid(
                              days: controller.days,
                              periods: settings.periods,
                              sessions: controller.sessions,
                              currentWeek: controller.currentWeek,
                              todayWeekday: controller.todayWeekday,
                              dimInactiveCourses: settings.dimInactiveCourses,
                              showTeacher: settings.showTeacher,
                              showPeriodTime: settings.showPeriodTime,
                              onSessionTap: (CourseSession session) =>
                                  showCourseDetail(
                                    context,
                                    session: session,
                                    week: controller.currentWeek,
                                    controller: controller,
                                  ),
                            ),
                          if (controller.isReady &&
                              !controller.isLoading &&
                              controller.sessions.isEmpty)
                            const Positioned.fill(child: _EmptyHint()),
                          // 右下角加号。放在这一层（而不是 FScaffold 的 footer 之上）是因为
                          // 这个 Stack 已经排除了底部导航，按钮自然就贴着课表区域的右下角。
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _AddCourseButton(
                              onPress: () => showCustomCourseForm(
                                context,
                                controller: controller,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 「放假啦」彩蛋页：学期最后一周再往后翻时出现，再翻一次回到第 1 周。
class _HolidayView extends StatelessWidget {
  const _HolidayView({required this.lastWeek});

  /// 学期总周数（提示文案里告诉用户往回翻是第几周）。
  final int lastWeek;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GridColors.page,
    child: SizedBox.expand(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFFFF3E0), GridColors.page],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // 一圈庆祝的小圆点，便宜但够热闹。
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                children: <Widget>[
                  const Align(
                    alignment: Alignment.center,
                    child: Text('🎉', style: TextStyle(fontSize: 72)),
                  ),
                  Align(
                    alignment: const Alignment(-0.95, -0.85),
                    child: _dot(12, const Color(0xFFF6C445)),
                  ),
                  Align(
                    alignment: const Alignment(0.9, -0.7),
                    child: _dot(8, const Color(0xFF7FB069)),
                  ),
                  Align(
                    alignment: const Alignment(-0.8, 0.85),
                    child: _dot(9, const Color(0xFF6FA8DC)),
                  ),
                  Align(
                    alignment: const Alignment(0.85, 0.8),
                    child: _dot(11, const Color(0xFFE98980)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '放假啦！',
              style: TextStyle(
                color: GridColors.textPrimary,
                fontSize: 34,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '这学期的课上完啦，好好休息～',
              style: TextStyle(color: GridColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 26),
            Text(
              '再往后翻回到第 1 周 · 往回翻回到第 $lastWeek 周',
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static Widget _dot(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 拉取状态 / 报错提示条。
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const _Banner(
        background: Color(0xFFF3F7FE),
        border: Color(0xFFD6E4FA),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('正在从教务系统获取课表…')),
          ],
        ),
      );
    }

    final String? error = controller.error;
    if (error != null) {
      return _Banner(
        background: const Color(0xFFFFF6E5),
        border: const Color(0xFFF0D9A8),
        child: Row(
          children: <Widget>[
            const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: const TextStyle(
                  color: Color(0xFF8A6116),
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: .outline,
              onPress: controller.refresh,
              child: const Text('重试'),
            ),
            const SizedBox(width: 6),
            FButton(
              variant: .outline,
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LoginScreen(
                    initialAccount: controller.savedAccount,
                    initialPassword: controller.savedPassword,
                  ),
                ),
              ),
              child: const Text('去登录'),
            ),
          ],
        ),
      );
    }

    // 非致命提示：例如刷新失败时继续显示上一次拿到的课表。
    final String? notice = controller.notice;
    if (notice != null) {
      return _Banner(
        background: const Color(0xFFF2F4F8),
        border: const Color(0xFFDDE1EA),
        child: Row(
          children: <Widget>[
            const Icon(
              FLucideIcons.info,
              size: 16,
              color: GridColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice,
                style: const TextStyle(
                  color: GridColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              variant: .outline,
              onPress: controller.refresh,
              child: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.child,
    required this.background,
    required this.border,
  });

  final Widget child;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
    decoration: BoxDecoration(
      color: background,
      border: Border(bottom: BorderSide(color: border)),
    ),
    child: DefaultTextStyle(
      style: const TextStyle(color: GridColors.textPrimary, fontSize: 12.5),
      child: IconTheme(
        data: const IconThemeData(size: 16, color: GridColors.textSecondary),
        child: child,
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          FLucideIcons.sparkles,
          size: 28,
          color: GridColors.textSecondary,
        ),
        const SizedBox(height: 8),
        Text(
          '这一周没有课',
          style: const TextStyle(color: GridColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '左右滑动换周 · 右下角 + 可以自己加课',
          style: TextStyle(
            color: GridColors.textSecondary.withValues(alpha: 0.8),
            fontSize: 11.5,
          ),
        ),
      ],
    ),
  );
}

/// 课表右下角的圆形加号：打开「添加课程」表单。
class _AddCourseButton extends StatelessWidget {
  const _AddCourseButton({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '添加课程',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPress,
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: GridColors.today,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x332C63D4),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          FLucideIcons.plus,
          size: 24,
          color: Color(0xFFFFFFFF),
        ),
      ),
    ),
  );
}

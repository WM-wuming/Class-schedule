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
import 'settings_screen.dart';

/// 课表首页。
class TimetableScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final AppSettings settings = controller.settings;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        titleAlignment: Alignment.center,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '广应课课表',
              style: TextStyle(
                color: GridColors.textPrimary,
                fontSize: 20,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            WeekPickerPill(controller: controller),
          ],
        ),
        suffixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.ellipsis, size: 20),
            onPress: () => _openMenu(context, controller),
          ),
          FHeaderAction(
            icon: const Icon(FLucideIcons.clock, size: 20),
            onPress: () => showTodaySchedule(context, controller: controller),
          ),
        ],
      ),
      footer: homeNavBar(current: currentTab, onSelect: onSelectTab),
      child: Column(
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
                onHorizontalDragEnd: (DragEndDetails details) {
                  final double velocity = details.primaryVelocity ?? 0;
                  if (velocity > 220) {
                    controller.previousWeek();
                  } else if (velocity < -220) {
                    controller.nextWeek();
                  }
                },
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
                        onPress: () =>
                            showCustomCourseForm(context, controller: controller),
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

  void _openMenu(BuildContext context, ScheduleController controller) {
    showAppMenu(
      context,
      onSettings: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      onBackToCurrentWeek: controller.backToCurrentWeek,
      onRefresh: controller.refresh,
    );
  }
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
                  builder: (_) =>
                      LoginScreen(
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

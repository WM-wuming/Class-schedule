import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../models/course.dart';
import '../models/custom_course.dart';
import '../models/period.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import 'course_form.dart';

/// 弹出底部菜单。
Future<void> showAppMenu(
  BuildContext context, {
  required VoidCallback onSettings,
  required VoidCallback onBackToCurrentWeek,
  required VoidCallback onRefresh,
}) async {
  await showFSheet<void>(
    context: context,
    side: FLayout.btt,
    builder: (BuildContext sheetContext) => _SheetBody(
      title: '广应课课表',
      child: FTileGroup(
        physics: const NeverScrollableScrollPhysics(),
        children: <FTileMixin>[
          FTile(
            title: const Text('刷新课表'),
            prefix: const Icon(FLucideIcons.refreshCw, size: 18),
            onPress: () {
              Navigator.maybePop(sheetContext);
              onRefresh();
            },
          ),
          FTile(
            title: const Text('设置'),
            prefix: const Icon(FLucideIcons.settings, size: 18),
            onPress: () {
              Navigator.maybePop(sheetContext);
              onSettings();
            },
          ),
          FTile(
            title: const Text('回到本周'),
            prefix: const Icon(FLucideIcons.calendarDays, size: 18),
            onPress: () {
              Navigator.maybePop(sheetContext);
              onBackToCurrentWeek();
            },
          ),
        ],
      ),
    ),
  );
}

/// 弹出课程详情。
///
/// 传了 [controller] 时，**自己添加的课程**会多一个「编辑」入口 —— 那条排课存在本机，
/// 改得动。教务系统拉回来的课不给这个按钮：它下次刷新就被覆盖了，让用户去改只会骗人。
Future<void> showCourseDetail(
  BuildContext context, {
  required CourseSession session,
  required int week,
  ScheduleController? controller,
}) async {
  final CourseColor color = CoursePalette.of(session.course.name);
  final CustomCourse? custom = controller?.customCourseById(session.customId);
  var wantEdit = false;

  await showFSheet<void>(
    context: context,
    side: FLayout.btt,
    builder: (BuildContext sheetContext) => _SheetBody(
      title: '课程详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 4,
                        height: 20,
                        margin: const EdgeInsets.only(top: 2, right: 8),
                        decoration: BoxDecoration(
                          color: color.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          session.course.name,
                          style: TextStyle(
                            color: color.accent,
                            fontSize: 17,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (session.course.hasTeacher)
                    _DetailRow(
                      icon: FLucideIcons.user,
                      label: '教师',
                      value: session.course.teacher,
                    ),
                  if (session.course.location.isNotEmpty)
                    _DetailRow(
                      icon: FLucideIcons.mapPin,
                      label: '地点',
                      value: session.course.location,
                    ),
                  if (session.course.category != null)
                    _DetailRow(
                      icon: FLucideIcons.bookOpen,
                      label: '属性',
                      value: session.course.category!,
                    ),
                  if (session.course.credits != null)
                    _DetailRow(
                      icon: FLucideIcons.graduationCap,
                      label: '学分',
                      value: '${session.course.credits} 学分',
                    ),
                  _DetailRow(
                    icon: FLucideIcons.calendarDays,
                    label: '周次',
                    value: session.weeksLabel,
                  ),
                  _DetailRow(
                    icon: FLucideIcons.clock,
                    label: '节次',
                    value:
                        '周${_weekdayLabel(session.weekday)} ${session.periodsLabel}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.isActiveInWeek(week)
                        ? '第 $week 周正常上课'
                        : '第 $week 周不上课',
                    style: const TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (custom != null) ...<Widget>[
            const SizedBox(height: 12),
            FButton(
              onPress: () {
                wantEdit = true;
                Navigator.maybePop(sheetContext);
              },
              child: const Text('编辑这门课'),
            ),
          ],
        ],
      ),
    ),
  );

  // 等详情弹层收完了再弹编辑表单，否则两个 sheet 会叠在一起。
  if (wantEdit && custom != null && controller != null && context.mounted) {
    await showCustomCourseForm(context, controller: controller, editing: custom);
  }
}

/// 弹出今天的课程。
Future<void> showTodaySchedule(
  BuildContext context, {
  required ScheduleController controller,
}) async {
  final DateTime now = DateTime.now();
  final int week = controller.todayWeek;
  final List<CourseSession> today = controller
      .sessionsOf(now.weekday)
      .where((CourseSession session) => session.isActiveInWeek(week))
      .toList();

  await showFSheet<void>(
    context: context,
    side: FLayout.btt,
    builder: (BuildContext sheetContext) => _SheetBody(
      title: '今天 · 周${_weekdayLabel(now.weekday)} · 第 $week 周',
      child: FCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: today.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    '今天没有课，休息一下 🎉',
                    style: TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final CourseSession session in today)
                      _TodayRow(
                        session: session,
                        periods: controller.settings.periods,
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.session, required this.periods});

  final CourseSession session;
  final List<Period> periods;

  @override
  Widget build(BuildContext context) {
    final CourseColor color = CoursePalette.of(session.course.name);
    final String start = periods[session.startPeriod - 1].start;
    final String end = periods[session.endPeriod - 1].end;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 78,
            child: Text(
              '$start\n$end',
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              color: color.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.course.name,
                  style: TextStyle(
                    color: color.accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    if (session.course.location.isNotEmpty)
                      '@${session.course.location}',
                    if (session.course.hasTeacher) session.course.teacher,
                  ].join(' · '),
                  style: const TextStyle(
                    color: GridColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 15, color: GridColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: GridColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹层的统一外壳。
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: GridColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

String _weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

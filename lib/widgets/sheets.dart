import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/course.dart';
import '../models/custom_course.dart';
import '../models/period.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import 'sheet_surface.dart';
import 'course_form.dart';

/// 弹出课程详情：居中的液态玻璃卡。
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
  final List<Period> periods = controller?.settings.periods ?? Period.defaults;
  final String? timeRange = _periodTimeRange(periods, session);
  var wantEdit = false;

  await showAppDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => GlassDialogSurface(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '课程详情',
                    style: TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(FLucideIcons.x, size: 20),
                    color: GridColors.textPrimary,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  session.course.name,
                  style: const TextStyle(
                    color: GridColors.textPrimary,
                    fontSize: 24,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _HighlightCard(
                children: <Widget>[
                  const _CardLabel('上课时间'),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      timeRange ?? session.periodsLabel,
                      style: const TextStyle(
                        color: GridColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '周${_weekdayLabel(session.weekday)} · ${session.periodsLabel}',
                    style: const TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  if (session.course.location.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(height: 1, color: const Color(0x14000000)),
                    const SizedBox(height: 12),
                    const _CardLabel('上课地点'),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        session.course.location,
                        style: const TextStyle(
                          color: GridColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (session.course.hasTeacher)
                _DialogInfoRow(label: '授课教师', value: session.course.teacher),
              _DialogInfoRow(label: '上课周次', value: session.weeksLabel),
              if (session.course.category != null)
                _DialogInfoRow(label: '课程属性', value: session.course.category!),
              if (session.course.credits != null)
                _DialogInfoRow(label: '学分', value: '${session.course.credits}'),
              if (!session.isCustom)
                _EnrichedInfoRows(
                  session: session,
                  week: week,
                  controller: controller,
                ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  session.isActiveInWeek(week)
                      ? '第 $week 周正常上课'
                      : '第 $week 周不上这节课',
                  style: const TextStyle(
                    color: GridColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (custom != null) ...<Widget>[
                const SizedBox(height: 12),
                FButton(
                  onPress: () {
                    wantEdit = true;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('编辑这门课'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  // 等详情弹窗收完了再弹编辑表单，否则两个弹层会叠在一起。
  if (wantEdit && custom != null && controller != null && context.mounted) {
    await showCustomCourseForm(
      context,
      controller: controller,
      editing: custom,
    );
  }
}

/// 节次换算成钟点时间，例如「14:30 – 16:05」。节次表里找不到对应节时返回 null。
String? _periodTimeRange(List<Period> periods, CourseSession session) {
  Period? first;
  Period? last;
  for (final Period period in periods) {
    if (period.index == session.startPeriod) {
      first = period;
    }
    if (period.index == session.endPeriod) {
      last = period;
    }
  }
  if (first == null || last == null) {
    return null;
  }
  return '${first.start} – ${last.end}';
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

  await showAppSheet<void>(
    context: context,
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

/// 详情弹窗里的浅灰信息卡（上课时间 / 上课地点）。
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: GridColors.page,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

/// 信息卡里的小标签（「上课时间」「上课地点」）。
class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: GridColors.textSecondary, fontSize: 12),
  );
}

/// 详情弹窗里「标签 + 值」的一行（授课教师 / 上课周次等）。
class _DialogInfoRow extends StatelessWidget {
  const _DialogInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              value,
              style: const TextStyle(
                color: GridColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 详情弹窗里的「副数据源」信息行：课时详情弹窗打开后，用旧课表接口
/// （`main_index_loadkb.jsp`，比新课表接口多学分与课程属性）异步补齐缺失的字段。
///
/// 加载中先显示一行淡淡的提示；补不到（未登录 / 接口失败 / 匹配不上）就安静地
/// 什么都不加 —— 副数据源的失败不该在详情弹窗里制造噪音。
class _EnrichedInfoRows extends StatefulWidget {
  const _EnrichedInfoRows({
    required this.session,
    required this.week,
    required this.controller,
  });

  final CourseSession session;
  final int week;
  final ScheduleController? controller;

  @override
  State<_EnrichedInfoRows> createState() => _EnrichedInfoRowsState();
}

class _EnrichedInfoRowsState extends State<_EnrichedInfoRows> {
  Future<CourseSession?>? _future;

  @override
  void initState() {
    super.initState();
    final ScheduleController? controller = widget.controller;
    if (controller != null) {
      _future = controller.loadEnrichedSession(widget.session, widget.week);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CourseSession?>(
    future: _future,
    builder: (BuildContext context, AsyncSnapshot<CourseSession?> snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 5),
          child: Text(
            '正在补充学分等信息…',
            style: TextStyle(color: GridColors.textSecondary, fontSize: 11.5),
          ),
        );
      }
      final CourseSession? enriched = snapshot.data;
      if (enriched == null) {
        return const SizedBox.shrink();
      }
      final Course original = widget.session.course;
      final List<Widget> rows = <Widget>[
        // 老师虽然新课表接口有，但个别格子可能漏 —— 旧接口补得上也一并显示。
        if (!original.hasTeacher && enriched.course.hasTeacher)
          _DialogInfoRow(label: '授课教师', value: enriched.course.teacher),
        if (original.category == null && enriched.course.category != null)
          _DialogInfoRow(
            label: '课程属性',
            value: enriched.course.category!,
          ),
        if (original.credits == null && enriched.course.credits != null)
          _DialogInfoRow(label: '学分', value: '${enriched.course.credits}'),
      ];
      if (rows.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    },
  );
}

/// 弹层的统一外壳。
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SheetSurface(
      child: SafeArea(
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
      ),
    );
  }
}

String _weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../models/classroom.dart';
import '../models/period.dart';
import '../models/week.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/home_nav.dart';
import 'login_screen.dart';

/// 「空教室」页：按**日期**查教室占用表，点进一间教室能看它这一天每节课在上什么课。
///
/// 数据来自教务系统的教室空余查询（`kbcx/kbxx_classroom_ifr`），**只读** ——
/// 本页不会预约、借用任何教室。
///
/// 交互（对齐 2026-09 的改版）：
/// - 头部是一块蓝色区：校区 / 教学楼 chips + 日期条（今天起往后两周）。
///   点日期 = 换「周次 + 星期」，是唯一会重新联网的入口之一；
/// - 教室列表是「占用一览」：每间教室一行，右侧把每个节次的占用画成红绿小条
///   （绿 = 空闲、红 = 占用，按上午 / 下午 / 晚上 分组），不再按节次先过滤；
/// - 点任意一间教室 → 底部弹层，按节次列出上课班级（课程 / 教师）与空闲时段。
abstract final class _RoomColors {
  /// 头部蓝底。
  static const Color header = Color(0xFF3A5AA6);

  /// 头部选中的 chip（更深的蓝）。
  static const Color headerChipActive = Color(0xFF27407B);

  /// 头部未选中的 chip（半透明白）。
  static const Color headerChip = Color(0x2EFFFFFF);

  /// 教室卡片的底色。
  static const Color card = Color(0xFFE9EDF6);

  /// 空闲的小条。
  static const Color free = Color(0xFF7CC47F);

  /// 占用的小条。
  static const Color busy = Color(0xFFE2636B);

  /// 详情里「空闲」文字用的绿（比小条的绿深，浅底上可读）。
  static const Color freeDeep = Color(0xFF2E7D46);
}

class ClassroomScreen extends StatefulWidget {
  const ClassroomScreen({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// 当前 Tab（底部导航高亮用）。
  final HomeTab currentTab;

  /// 切换 Tab。
  final ValueChanged<HomeTab> onSelectTab;

  @override
  State<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends State<ClassroomScreen> {
  bool _requested = false;

  /// 只看全天空闲的教室（默认关 —— 列表本身就是占用一览，想筛再筛）。
  bool _freeOnly = false;

  /// 上一次表格里的节次列。
  ///
  /// 换条件重新查询的那一瞬间 [ScheduleController.classroomBoard] 是 null，
  /// 用它兜着，详情弹层与占用条不会闪一下消失。
  List<JwPeriodRange> _columns = const <JwPeriodRange>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) {
      return;
    }
    _requested = true;
    final ScheduleController controller = ScheduleScope.of(context);
    // 放到帧后执行：`ensureClassroomBoard` 会立刻 notifyListeners()，
    // 在 build/didChangeDependencies 期间通知会触发断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(controller.ensureClassroomBoard());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final JwClassroomBoard? board = controller.classroomBoard;

    if (board != null && board.periodColumns.isNotEmpty) {
      // 只是缓存上一份表格的列，用来渲染占用条；真正的状态在 controller 里。
      _columns = board.periodColumns;
    }
    final List<JwPeriodRange> columns = _columns;

    return FScaffold(
      childPad: false,
      // 头部是深蓝底，状态栏图标用浅色才看得见。
      scaffoldStyle: FScaffoldStyleDelta.delta(
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      footer: homeNavBar(current: widget.currentTab, onSelect: widget.onSelectTab),
      child: Column(
        children: <Widget>[
          _Header(
            controller: controller,
            query: controller.classroomQuery,
            board: board,
            onRefresh: () => controller.loadClassroomBoard(force: true),
          ),
          Expanded(
            child: ColoredBox(
              color: GridColors.page,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: <Widget>[
                  const _LegendBar(),
                  const SizedBox(height: 10),
                  if (board != null && !board.isEmpty) ...<Widget>[
                    _SummaryRow(
                      board: board,
                      freeOnly: _freeOnly,
                      onToggle: () => setState(() => _freeOnly = !_freeOnly),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (controller.classroomLoading && board == null)
                    const _LoadingCard()
                  else if (controller.classroomError != null)
                    _ErrorCard(
                      message: controller.classroomError!,
                      onRetry: () => controller.loadClassroomBoard(force: true),
                      onLogin: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LoginScreen(
                            initialAccount: controller.savedAccount,
                            initialPassword: controller.savedPassword,
                          ),
                        ),
                      ),
                    )
                  else if (board == null)
                    const SizedBox.shrink()
                  else
                    ..._results(context, board: board, columns: columns),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _results(
    BuildContext context, {
    required JwClassroomBoard board,
    required List<JwPeriodRange> columns,
  }) {
    if (board.isEmpty) {
      return <Widget>[
        const _HintCard(
          title: '没有查询到教室',
          message:
              '这个条件下教务系统没返回任何教室。可以换一个教学楼，'
              '或者确认日期是否选对了。',
        ),
      ];
    }

    final JwPeriodRange allDay =
        board.wholeDay ??
        JwPeriodRange(start: 1, end: Period.defaults.length);
    final List<JwClassroom> shown = _freeOnly
        ? board.freeIn(allDay)
        : board.classrooms;

    return <Widget>[
      if (shown.isEmpty)
        const _HintCard(
          title: '没有全天空闲的教室',
          message:
              '这个条件下每间教室都有课。可以关掉「只看空闲」看各教室的占用时段，'
              '或者换一天、换一栋教学楼。',
        )
      else
        for (final JwClassroom room in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RoomCard(
              room: room,
              columns: columns,
              onTap: () => showClassroomDetail(
                context,
                room: room,
                board: board,
                columns: columns,
              ),
            ),
          ),
    ];
  }
}

/// 头部蓝色区：标题 + 刷新、校区 / 教学楼 chips、日期条。
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.query,
    required this.board,
    required this.onRefresh,
  });

  final ScheduleController controller;
  final JwClassroomQuery query;
  final JwClassroomBoard? board;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final Term term = controller.term;
    final List<DateTime> dates = _stripDates(term);
    final DateTime? selected = _selectedDate(term, query);
    final List<JwClassroomOption> campuses = board?.campusOptions ?? const <JwClassroomOption>[];
    final List<JwClassroomOption> buildings = board?.buildingOptions ?? const <JwClassroomOption>[];

    return ColoredBox(
      color: _RoomColors.header,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    '空教室',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _RoundAction(icon: FLucideIcons.refreshCw, onPress: onRefresh),
                ],
              ),
              if (campuses.length > 1) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final JwClassroomOption option in campuses)
                      _HeaderChip(
                        label: option.name,
                        selected: query.campusId == option.id,
                        onTap: () => controller.updateClassroomQuery(
                          query.copyWith(campusId: option.id),
                        ),
                      ),
                  ],
                ),
              ],
              if (buildings.length > 1) ...<Widget>[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final JwClassroomOption option in buildings)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _HeaderChip(
                            label: option.name,
                            selected: query.buildingId == option.id,
                            onTap: () => controller.updateClassroomQuery(
                              query.copyWith(buildingId: option.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final DateTime date in dates)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _HeaderChip(
                          label: _dateLabel(date),
                          selected: selected == date,
                          onTap: () => controller.updateClassroomQuery(
                            query.copyWith(
                              week: term.weekOf(date),
                              weekday: date.weekday,
                            ),
                          ),
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

  /// 日期条：今天起往后 18 天，落在学期外的裁掉；学期结束了就退回最后一周。
  List<DateTime> _stripDates(Term term) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<DateTime> dates = <DateTime>[
      for (var i = 0; i < 18; i++) today.add(Duration(days: i)),
    ].where((DateTime date) {
      final int week = term.weekOf(date);
      return week >= 1 && week <= term.totalWeeks;
    }).toList();
    if (dates.isNotEmpty) {
      return dates;
    }
    final DateTime last = term.startOfWeek(term.totalWeeks);
    return <DateTime>[for (var i = 0; i < 7; i++) last.add(Duration(days: i))];
  }

  /// 查询条件（周次 + 星期）反推出来的日期，用来高亮日期条。
  DateTime? _selectedDate(Term term, JwClassroomQuery query) {
    if (query.week < 1 || query.week > term.totalWeeks) {
      return null;
    }
    // 学期第 1 周从周日开始：周日偏移 0，周一偏移 1……周六偏移 6。
    return term
        .startOfWeek(query.week)
        .add(Duration(days: query.weekday % 7));
  }

  String _dateLabel(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    if (date == today) {
      return '今天';
    }
    return '${date.month}/${date.day}';
  }
}

/// 头部里的一颗圆角 chip：选中 = 深蓝，未选中 = 半透明白。
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? _RoomColors.headerChipActive
            : _RoomColors.headerChip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// 头部右上角的圆形按钮（刷新）。
class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onPress});

  final IconData icon;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPress,
    child: Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: _RoomColors.headerChip,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}

/// 图例：绿 = 空闲、红 = 占用；右侧是占用条的三个分组。
class _LegendBar extends StatelessWidget {
  const _LegendBar();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(
      color: GridColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: <Widget>[
        const _Dot(color: _RoomColors.free),
        const SizedBox(width: 6),
        const Text('空闲', style: _LegendBar._labelStyle),
        const SizedBox(width: 14),
        const _Dot(color: _RoomColors.busy),
        const SizedBox(width: 6),
        const Text('占用', style: _LegendBar._labelStyle),
        const Spacer(),
        for (var i = 0; i < _groupNames.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 10),
          Container(width: 1, height: 11, color: const Color(0xFFE3E6EF)),
          const SizedBox(width: 6),
          Text(_groupNames[i], style: _LegendBar._groupStyle),
        ],
      ],
    ),
  );

  static const List<String> _groupNames = <String>['上午', '下午', '晚上'];

  static const TextStyle _labelStyle = TextStyle(
    color: GridColors.textPrimary,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle _groupStyle = TextStyle(
    color: GridColors.textSecondary,
    fontSize: 12,
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 查询结果上方那行：有多少间、多少间全天空闲，以及「只看空闲」开关。
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.board,
    required this.freeOnly,
    required this.onToggle,
  });

  final JwClassroomBoard board;
  final bool freeOnly;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final JwPeriodRange allDay =
        board.wholeDay ??
        JwPeriodRange(start: 1, end: Period.defaults.length);
    final int free = board.freeIn(allDay).length;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '共 ${board.classrooms.length} 间教室 · 全天空闲 $free 间',
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Chip(label: '只看空闲', selected: freeOnly, onTap: onToggle),
      ],
    );
  }
}

/// 一间教室：左边名字与容量，右边把每个节次的占用画成红绿小条。
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.columns,
    required this.onTap,
  });

  final JwClassroom room;
  final List<JwPeriodRange> columns;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String seatLine = <String>[
      for (final MapEntry<String, String> entry in room.extras.entries)
        '${entry.key} ${entry.value}',
    ].join(' · ');

    return Semantics(
      button: true,
      label: '${room.name}，查看上课班级',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: _RoomColors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      room.name,
                      style: const TextStyle(
                        color: GridColors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (seatLine.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        seatLine,
                        style: const TextStyle(
                          color: GridColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (columns.isNotEmpty) _OccupancyBars(room: room, columns: columns),
            ],
          ),
        ),
      ),
    );
  }
}

/// 节次占用条：每列一根小条，绿 = 该节次没课、红 = 有课，按上午 / 下午 / 晚上 分组。
class _OccupancyBars extends StatelessWidget {
  const _OccupancyBars({required this.room, required this.columns});

  final JwClassroom room;
  final List<JwPeriodRange> columns;

  @override
  Widget build(BuildContext context) {
    final List<(String, List<JwPeriodRange>)> groups = groupPeriodColumns(
      columns,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var g = 0; g < groups.length; g++) ...<Widget>[
          if (g > 0) const SizedBox(width: 10),
          for (var i = 0; i < groups[g].$2.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == groups[g].$2.length - 1 ? 0 : 3,
              ),
              child: Container(
                width: 7,
                height: 24,
                decoration: BoxDecoration(
                  color: room.isBusyIn(groups[g].$2[i])
                      ? _RoomColors.busy
                      : _RoomColors.free,
                  borderRadius: BorderRadius.circular(3.5),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 教室详情：这一天每个节次在上什么课（上课班级查询的入口）。
Future<void> showClassroomDetail(
  BuildContext context, {
  required JwClassroom room,
  required JwClassroomBoard board,
  required List<JwPeriodRange> columns,
}) async {
  final List<(String, List<JwPeriodRange>)> groups = groupPeriodColumns(
    columns,
  );
  final String seatLine = <String>[
    for (final MapEntry<String, String> entry in room.extras.entries)
      '${entry.key} ${entry.value}',
  ].join(' · ');

  await showFSheet<void>(
    context: context,
    side: FLayout.btt,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              room.name,
              style: const TextStyle(
                color: GridColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '第 ${board.week} 周 · 星期${_weekdayLabel(board.weekday)}'
              '${seatLine.isEmpty ? '' : ' · $seatLine'}',
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '这一天没有排课信息。',
                  style: TextStyle(
                    color: GridColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              )
            else
              for (var g = 0; g < groups.length; g++) ...<Widget>[
                if (g > 0) const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    groups[g].$1,
                    style: const TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final JwPeriodRange column in groups[g].$2)
                  _DetailPeriodRow(room: room, column: column),
              ],
          ],
        ),
      ),
    ),
  );
}

/// 详情里的一行：节次（+ 起止时间）｜上课班级（课程 / 教师）或「空闲」。
class _DetailPeriodRow extends StatelessWidget {
  const _DetailPeriodRow({required this.room, required this.column});

  final JwClassroom room;
  final JwPeriodRange column;

  @override
  Widget build(BuildContext context) {
    final List<JwClassroomBusy> busy = room.busyIn(column);
    final JwClassroomBusy? lesson = busy.isEmpty ? null : busy.first;
    final String time = _timeRangeOf(column);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  column.label,
                  style: const TextStyle(
                    color: GridColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: const TextStyle(
                      color: GridColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: lesson == null
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '空闲',
                      style: TextStyle(
                        color: _RoomColors.freeDeep,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        lesson.label,
                        style: TextStyle(
                          color: CoursePalette.of(lesson.label).accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lesson.detail != null &&
                          lesson.detail!.isNotEmpty)
                        Text(
                          lesson.detail!,
                          style: const TextStyle(
                            color: GridColors.textSecondary,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 节次对应的作息时间（超出本校节次表的部分钳到最后一节）。
  static String _timeRangeOf(JwPeriodRange column) {
    final List<Period> periods = Period.defaults;
    if (column.start < 1 || column.start > periods.length) {
      return '';
    }
    final int end = column.end.clamp(1, periods.length);
    return '${periods[column.start - 1].start} - ${periods[end - 1].end}';
  }
}

/// 把节次列按 上午（1-4）/ 下午（5-8）/ 晚上（9+）分组，空组不出现。
List<(String, List<JwPeriodRange>)> groupPeriodColumns(
  List<JwPeriodRange> columns,
) {
  const List<String> names = <String>['上午', '下午', '晚上'];
  final List<List<JwPeriodRange>> groups = <List<JwPeriodRange>>[
    <JwPeriodRange>[],
    <JwPeriodRange>[],
    <JwPeriodRange>[],
  ];
  for (final JwPeriodRange column in columns) {
    final int index = column.start <= 4
        ? 0
        : (column.start <= 8 ? 1 : 2);
    groups[index].add(column);
  }
  return <(String, List<JwPeriodRange>)>[
    for (var i = 0; i < names.length; i++)
      if (groups[i].isNotEmpty) (names[i], groups[i]),
  ];
}

/// 一个小圆角标签，选中时用主色调。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? GridColors.today : GridColors.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: selected ? const Color(0xFFFFFFFF) : GridColors.textPrimary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在查询教室占用情况…',
            style: const TextStyle(color: GridColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: GridColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onLogin,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF0D9A8)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8A6116), fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FButton(variant: .outline, onPress: onRetry, child: const Text('重试')),
          const SizedBox(width: 6),
          FButton(variant: .outline, onPress: onLogin, child: const Text('去登录')),
        ],
      ),
    ),
  );
}

/// 1 → 「一」，7 → 「日」。
String _weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

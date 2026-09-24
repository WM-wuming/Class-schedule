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
import '../widgets/sheet_surface.dart';
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

  /// 教室名过滤关键字（[TextEditingController] 的实时镜像）。
  String _searchText = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 每敲一个字就重刷列表：数据全在本地（board.classrooms），过滤是纯内存操作。
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchText = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      footer: homeNavBar(
        context: context,
        current: widget.currentTab,
        onSelect: widget.onSelectTab,
      ),
      child: Column(
        // 必须 stretch：FScaffold 把 child 放进 Expanded（松宽度约束），Column
        // 宽度只取最宽子项 —— 手机上日期条 18 个 chip 超过屏宽撑满看不出，
        // 屏幕过宽（平板 / 横屏 / 折叠屏展开）时内容窄于屏宽，蓝色头部就
        // 盖不满整页。stretch 让 Column 与三个色块子项一律取满父约束宽。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            controller: controller,
            query: controller.classroomQuery,
            board: board,
          ),
          // 固定在蓝色头部下方：搜索框 + 统计行 + 空闲/占用图例。不放进 ListView，
          // 键盘弹出/列表滚动都不影响输入框的焦点与命中，图例滚动时也一直可见。
          ColoredBox(
            color: GridColors.page,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SearchField(controller: _searchController),
                  if (board != null && !board.isEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    // 统计行（共 X 间 · 全天空闲 Y 间）挪到搜索框正下方。
                    _SummaryRow(board: board),
                  ],
                  const SizedBox(height: 10),
                  // 空闲/占用 + 上午/下午/晚上图例：与搜索框一起固定在列表外，
                  // 滚动教室列表时仍然可见。水平同样走 16 外边距 ——
                  // 「标签槽右缘 = 卡片占用条右缘」的对位关系不变（见 _LegendBar 注释）。
                  _LegendBar(columns: columns),
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: GridColors.page,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                children: <Widget>[
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

    final List<JwClassroom> shown = board.classrooms;

    // 搜索框有字时按教室名本地过滤（忽略大小写），不发请求 —— 数据本来就在手上。
    final String keyword = _searchText.trim().toLowerCase();
    if (keyword.isNotEmpty) {
      final List<JwClassroom> matched = shown
          .where(
            (JwClassroom room) => room.name.toLowerCase().contains(keyword),
          )
          .toList();
      if (matched.isEmpty) {
        return <Widget>[
          _HintCard(
            title: '没有找到教室「${_searchText.trim()}」',
            message: '换个关键字试试，比如教学楼号或房间号（J1、201…）。',
          ),
        ];
      }
      return <Widget>[
        for (final JwClassroom room in matched)
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

    return <Widget>[
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

/// 头部蓝色区：标题、校区 / 教学楼 chips、日期条。
class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.query,
    required this.board,
  });

  final ScheduleController controller;
  final JwClassroomQuery query;
  final JwClassroomBoard? board;

  @override
  Widget build(BuildContext context) {
    final Term term = controller.term;
    final List<DateTime> dates = _stripDates(term);
    final DateTime? selected = _selectedDate(term, query);
    final List<JwClassroomOption> campuses =
        board?.campusOptions ?? const <JwClassroomOption>[];
    final List<JwClassroomOption> buildings =
        board?.buildingOptions ?? const <JwClassroomOption>[];

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
              const Text(
                '教室状态',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
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
    final List<DateTime> dates =
        <DateTime>[for (var i = 0; i < 18; i++) today.add(Duration(days: i))]
            .where((DateTime date) {
              final int week = term.weekOf(date);
              return week >= 1 && week <= term.totalWeeks;
            })
            .toList();
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
    return term.startOfWeek(query.week).add(Duration(days: query.weekday % 7));
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

/// 教室搜索框：按教室名过滤当前查询结果（纯本地，不发请求）。
///
/// 用 forui 的 [FTextField]（登录页同款，真机输入没问题），不再手搓
/// `TextField` + `Material(transparency)` —— 那套在真机上焦点/输入法不稳。
/// 有内容时显示内置的清除按钮。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => FTextField(
    control: FTextFieldControl.managed(controller: controller),
    hint: '搜索教室，如 J1-101',
    keyboardType: TextInputType.text,
    textInputAction: TextInputAction.search,
    clearable: (TextEditingValue value) => value.text.isNotEmpty,
    clearIconBuilder:
        (BuildContext context, FTextFieldStyle style, VoidCallback clear) =>
            FButton.icon(
              variant: .ghost,
              onPress: clear,
              child: const Icon(
                FLucideIcons.x,
                size: 15,
                color: GridColors.textSecondary,
              ),
            ),
    prefixBuilder:
        (
          BuildContext context,
          FTextFieldStyle style,
          Set<FTextFieldVariant> variants,
        ) => const Padding(
          padding: EdgeInsets.only(left: 12, right: 8),
          child: Icon(
            FLucideIcons.search,
            size: 15,
            color: GridColors.textSecondary,
          ),
        ),
  );
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
        color: selected ? _RoomColors.headerChipActive : _RoomColors.headerChip,
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

/// 图例：绿 = 空闲、红 = 占用；右侧是占用条的三个分组。
///
/// 它**固定在搜索框下方、教室列表外**（不随列表滚动），水平方向仍与
/// 教室卡片走同一套 16 外边距。
///
/// 右侧的「上午 / 下午 / 晚上」标签按下面教室卡片里**占用条的实际布局**
/// （每根 7 宽、组内间距 3、组间 10）摆位 —— 每个标签占一个组宽的槽位居中，
/// 右缘和卡片占用条的右缘（同为 14 内边距）对齐，所以标签正好落在
/// 对应那一组占用条的正上方。
class _LegendBar extends StatelessWidget {
  const _LegendBar({required this.columns});

  /// 当前表格的节次列 —— 决定右侧分组的数量与每组宽度。
  final List<JwPeriodRange> columns;

  @override
  Widget build(BuildContext context) {
    final List<(String, List<JwPeriodRange>)> groups = groupPeriodColumns(
      columns,
    );

    return Container(
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
          for (var i = 0; i < groups.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: _OccupancyBars.groupGap),
            SizedBox(
              width: _OccupancyBars.groupWidth(groups[i].$2.length),
              child: Center(
                child: Text(groups[i].$1, style: _LegendBar._groupStyle),
              ),
            ),
          ],
        ],
      ),
    );
  }

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

/// 查询结果上方那行：有多少间、多少间全天空闲。
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.board});

  final JwClassroomBoard board;

  @override
  Widget build(BuildContext context) {
    final JwPeriodRange allDay =
        board.wholeDay ?? JwPeriodRange(start: 1, end: Period.defaults.length);
    final int free = board.freeIn(allDay).length;

    return Text(
      '共 ${board.classrooms.length} 间教室 · 全天空闲 $free 间',
      style: const TextStyle(color: GridColors.textSecondary, fontSize: 12),
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
              if (columns.isNotEmpty)
                _OccupancyBars(room: room, columns: columns),
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

  /// 一根小条的宽度。
  static const double barWidth = 7;

  /// 组内相邻两根小条的间距。
  static const double barGap = 3;

  /// 两组之间的间距。
  static const double groupGap = 10;

  /// [count] 根小条组成的**一组**的总宽度（图例标签按它对位）。
  static double groupWidth(int count) =>
      count <= 0 ? 0 : count * barWidth + (count - 1) * barGap;

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
          if (g > 0) const SizedBox(width: groupGap),
          for (var i = 0; i < groups[g].$2.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == groups[g].$2.length - 1 ? 0 : barGap,
              ),
              child: Container(
                width: barWidth,
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

  await showAppSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => SheetSurface(
      child: SafeArea(
        top: false,
        // 弹层本身有限高：三组节次行（上午/下午/晚上）内容一多就会溢出被裁，
        // 所以内容放进 ConstrainedBox + SingleChildScrollView，超出就能下滑。
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: SingleChildScrollView(
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
                      if (lesson.detail != null && lesson.detail!.isNotEmpty)
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
    final int index = column.start <= 4 ? 0 : (column.start <= 8 ? 1 : 2);
    groups[index].add(column);
  }
  return <(String, List<JwPeriodRange>)>[
    for (var i = 0; i < names.length; i++)
      if (groups[i].isNotEmpty) (names[i], groups[i]),
  ];
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
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 13,
            ),
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
          FButton(
            variant: .outline,
            onPress: onLogin,
            child: const Text('去登录'),
          ),
        ],
      ),
    ),
  );
}

/// 1 → 「一」，7 → 「日」。
String _weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

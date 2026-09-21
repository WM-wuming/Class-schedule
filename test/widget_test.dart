import 'package:class_schedule/models/week.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:class_schedule/widgets/timetable_grid.dart';

import 'fakes.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  group('学期换算', () {
    final Term term = defaultTerm;

    test('第 1 周从 2026/8/30 周日开始', () {
      expect(term.startOfWeek(1), DateTime(2026, 8, 30));
      expect(term.startOfWeek(1).weekday, DateTime.sunday);
    });

    test('第 4 周覆盖 9/20 - 9/26', () {
      expect(term.weekOf(DateTime(2026, 9, 20)), 4);
      expect(term.weekOf(DateTime(2026, 9, 26)), 4);
      expect(term.weekOf(DateTime(2026, 9, 27)), 5);
      expect(term.rangeLabelOf(4), '9/20 - 9/26');
    });

    test('一周按周日到周六排列', () {
      final List<ScheduleDay> days = term.daysOf(4);
      expect(days.map((ScheduleDay day) => day.dateLabel).toList(), <String>[
        '9/20',
        '9/21',
        '9/22',
        '9/23',
        '9/24',
        '9/25',
        '9/26',
      ]);
      expect(days.first.label, '日');
      expect(days.first.weekday, DateTime.sunday);
      expect(days[1].label, '一');
      expect(days.last.label, '六');
    });

    test('不显示周末时只剩 5 天', () {
      expect(term.daysOf(4, includeWeekend: false), hasLength(5));
    });
  });

  testWidgets('课表首页能渲染出网格与课程卡片', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    expect(find.text('广应科课表'), findsOneWidget);
    // 两条「线性代数」：周一 5-6 节、周三 1-2 节
    expect(find.text('线性代数'), findsNWidgets(2));
    expect(find.text('概率论与数理统计'), findsNWidgets(2));
    expect(find.text('Python程序设计'), findsNWidgets(2));
    expect(find.text('军事理论'), findsOneWidget);
    expect(find.text('中国近现代史纲要'), findsOneWidget);
    expect(find.text('大学体育I'), findsOneWidget);
    expect(find.text('大学日语Ⅰ'), findsOneWidget);
    expect(find.text('午休'), findsOneWidget);
    expect(find.text('晚休'), findsOneWidget);
    expect(find.text('第一节'), findsOneWidget);
    expect(find.text('第十一节'), findsOneWidget);
  });

  testWidgets('点击课程卡片会弹出详情', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    // 第一条「线性代数」是周一 5-6 节，地点 J1-507
    await tester.tap(find.text('线性代数').first);
    await tester.pumpAndSettle();

    expect(find.text('课程详情'), findsOneWidget);
    expect(find.text('J1-507'), findsWidgets);
    expect(find.text('王可芸'), findsWidgets);
  });

  testWidgets('周次胶囊可以打开周次列表', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('周').first);
    await tester.pumpAndSettle();

    expect(find.text('选择周次'), findsOneWidget);
  });

  testWidgets('我的信息页可以进入设置页并让显示选项生效', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    // 右上角现在是刷新按钮（三个点菜单已移除，设置入口挪到「我的信息」页）
    expect(find.byIcon(FLucideIcons.refreshCw), findsOneWidget);

    await tester.tap(find.text('我的信息'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    // 设置页是二级页面结构：「学期 / 显示 / 周次」合并在「课表」子页里。
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();

    // 课表二级页第一组是「学期」；「数据来源」整组已经移除
    expect(find.text('学期'), findsOneWidget);
    expect(find.text('开学日期'), findsOneWidget);
    expect(find.text('数据来源'), findsNothing);
    expect(find.text('本地示例'), findsNothing);
    expect(find.text('教务系统'), findsNothing);

    // 往下滚到「显示」分组（ListView 懒加载，不滚动不会构建）
    await tester.dragUntilVisible(
      find.text('显示周末'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(find.text('显示周末'), findsOneWidget);
    expect(find.text('淡化非本周课程'), findsOneWidget);

    // 关掉「显示周末」，开关状态要跟着变
    expect(tester.widget<FSwitch>(find.byType(FSwitch).first).value, isTrue);
    await tester.tap(find.byType(FSwitch).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FSwitch>(find.byType(FSwitch).first).value, isFalse);

    // 返回到「我的信息」（课表二级页 → 设置主页 → 我的信息，共两次返回），
    // 再切回课表 Tab —— 周六那一列应该消失
    await tester.tap(find.byIcon(FLucideIcons.chevronLeft).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.chevronLeft).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(find.text('9/26'), findsNothing);
    expect(find.text('9/25'), findsOneWidget);
  });

  testWidgets('左右滑动可以翻周', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    String weekLabel() =>
        tester.widget<Text>(find.textContaining('第 ').first).data!;

    final RegExp pattern = RegExp(r'第 (\d+) 周');
    final int start = int.parse(pattern.firstMatch(weekLabel())!.group(1)!);

    await tester.fling(find.byType(TimetableGrid), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    final int previous = start > 1 ? start - 1 : 1;
    expect(weekLabel(), '第 $previous 周');

    await tester.fling(find.byType(TimetableGrid), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(weekLabel(), '第 $start 周');
  });

  testWidgets('最后一周再往后翻出现「放假啦」，再翻回第 1 周', (WidgetTester tester) async {
    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    final BuildContext gridContext = tester.element(
      find.byType(TimetableGrid).first,
    );
    final ScheduleController controller = ScheduleScope.of(gridContext);
    controller.goToWeek(controller.term.totalWeeks);
    await tester.pumpAndSettle();
    expect(find.text('放假啦！'), findsNothing);

    // 往后翻（左滑）：最后一周之后是放假页
    await tester.fling(find.byType(TimetableGrid), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('放假啦！'), findsOneWidget);

    // 放假页再往后翻：回到第 1 周
    await tester.fling(find.text('放假啦！'), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('放假啦！'), findsNothing);
    expect(controller.currentWeek, 1);

    // 再进一次放假页，往回翻（右滑）退回最后一周
    controller.goToWeek(controller.term.totalWeeks);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(TimetableGrid), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('放假啦！'), findsOneWidget);
    await tester.fling(find.text('放假啦！'), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('放假啦！'), findsNothing);
    expect(controller.currentWeek, controller.term.totalWeeks);
  });

  group('网格几何', () {
    /// 行高关系：相邻节次相差一节，跨过午休要多出一个分隔行。
    testWidgets('节次行高与午休分隔行对得上', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      double centerY(String text) => tester.getCenter(find.text(text)).dy;

      expect(
        centerY('第二节') - centerY('第一节'),
        closeTo(TimetableGrid.periodHeight, 0.6),
      );
      expect(
        centerY('第三节') - centerY('第二节'),
        closeTo(TimetableGrid.periodHeight, 0.6),
      );
      // 第四节 与 第五节 之间夹着「午休」
      expect(
        centerY('第五节') - centerY('第四节'),
        closeTo(TimetableGrid.periodHeight + TimetableGrid.breakHeight, 0.6),
      );
      // 第八节 与 第九节 之间夹着「晚休」
      expect(
        centerY('第九节') - centerY('第八节'),
        closeTo(TimetableGrid.periodHeight + TimetableGrid.breakHeight, 0.6),
      );
      expect(
        centerY('第十一节') - centerY('第十节'),
        closeTo(TimetableGrid.periodHeight, 0.6),
      );

      // 左侧时间轴是把「节次名 + 起止时间」整组居中，整组中线就是这一行的中线
      double rowCenter(String label, String end) =>
          (tester.getTopLeft(find.text(label)).dy +
              tester.getBottomLeft(find.text(end)).dy) /
          2;

      // 休息行正好落在两节之间
      expect(
        centerY('午休') - rowCenter('第四节', '11:50'),
        closeTo(
          TimetableGrid.periodHeight / 2 + TimetableGrid.breakHeight / 2,
          0.6,
        ),
      );
    });

    testWidgets('时间轴、日期列与课程块宽度一致', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      final double gridWidth = tester.getSize(find.byType(TimetableGrid)).width;
      final double columnWidth = (gridWidth - TimetableGrid.gutterWidth) / 7;

      // 时间轴占左侧固定宽度，节次名在时间轴里水平居中
      expect(
        tester.getCenter(find.text('第一节')).dx,
        closeTo(TimetableGrid.gutterWidth / 2, 0.6),
      );

      // 7 个日期列表头等宽平分剩余空间
      double headerCenter(String date) => tester.getCenter(find.text(date)).dx;
      expect(
        headerCenter('9/21') - headerCenter('9/20'),
        closeTo(columnWidth, 0.6),
      );
      expect(
        headerCenter('9/26') - headerCenter('9/20'),
        closeTo(columnWidth * 6, 0.6),
      );
    });

    testWidgets('课程块按节次落位并跨行', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      final double gridWidth = tester.getSize(find.byType(TimetableGrid)).width;
      final double columnWidth = (gridWidth - TimetableGrid.gutterWidth) / 7;

      Rect blockOf(String courseName, {int index = 0}) => tester.getRect(
        find
            .ancestor(
              of: find.text(courseName).at(index),
              matching: find.byType(CourseBlock),
            )
            .first,
      );

      final double rowTop =
          (tester.getTopLeft(find.text('第一节')).dy +
                  tester.getBottomLeft(find.text('09:05')).dy) /
              2 -
          TimetableGrid.periodHeight / 2;

      // 列顺序是 日→六，同列内按开始节次排序，所以「线性代数」的
      // index 0 是周一 5-6 节、index 1 是周三 1-2 节。

      // 周三（第 4 列）第 1-2 节：贴住第一节顶端，高度为两节
      final Rect linearWed = blockOf('线性代数', index: 1);
      expect(linearWed.top, closeTo(rowTop, 0.6));
      expect(linearWed.height, closeTo(TimetableGrid.periodHeight * 2, 0.6));
      expect(
        linearWed.left - TimetableGrid.gutterWidth,
        closeTo(columnWidth * 3 + 3, 0.6),
      );

      // 周一（第 2 列）第 3-4 节 与 周三第 7-8 节的两条「概率论与数理统计」
      final Rect probabilityMon = blockOf('概率论与数理统计');
      final Rect probabilityWed = blockOf('概率论与数理统计', index: 1);
      expect(
        probabilityMon.height,
        closeTo(TimetableGrid.periodHeight * 2, 0.6),
      );
      expect(
        probabilityMon.left - TimetableGrid.gutterWidth,
        closeTo(columnWidth + 3, 0.6),
      );
      expect(
        probabilityWed.left - probabilityMon.left,
        closeTo(columnWidth * 2, 0.6),
      );
      expect(
        probabilityWed.top - probabilityMon.top,
        closeTo(
          TimetableGrid.periodHeight * 4 + TimetableGrid.breakHeight,
          0.6,
        ),
      );

      // 课程块左右各留 3px
      final Rect linearMon = blockOf('线性代数');
      expect(linearMon.width, closeTo(columnWidth - 6, 0.6));

      // 周二第 9-11 节「军事理论」：跨三节，前面隔着午休、晚休两个分隔行
      final Rect military = blockOf('军事理论');
      expect(military.height, closeTo(TimetableGrid.periodHeight * 3, 0.6));
      expect(
        military.top - probabilityMon.top,
        closeTo(
          TimetableGrid.periodHeight * 6 + TimetableGrid.breakHeight * 2,
          0.6,
        ),
      );
    });

    testWidgets('每节课之间都空出 blockGap', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      /// 课程卡片本身（不含上下让出的透明间隙）。
      Rect cardOf(String courseName, {int index = 0}) => tester.getRect(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text(courseName).at(index),
                    matching: find.byType(CourseBlock),
                  )
                  .first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );

      /// 卡片所在的格子（含上下让出的间隙）。
      Rect slotOf(String courseName, {int index = 0}) => tester.getRect(
        find
            .ancestor(
              of: find.text(courseName).at(index),
              matching: find.byType(CourseBlock),
            )
            .first,
      );

      // 卡片比格子矮 blockGap：上下各让一半，所以它不会顶到格子的边。
      final Rect upperSlot = slotOf('Python程序设计');
      expect(
        upperSlot.height - cardOf('Python程序设计').height,
        closeTo(TimetableGrid.blockGap, 0.6),
      );

      // 周五第 5-6 节与第 7-8 节的两条「Python程序设计」在网格里紧挨着
      // （中间没有休息行），所以两张卡片之间正好空出一个 blockGap。
      final Rect upper = cardOf('Python程序设计');
      final Rect lower = cardOf('Python程序设计', index: 1);
      expect(lower.left, closeTo(upper.left, 0.6));
      expect(lower.top - upper.bottom, closeTo(TimetableGrid.blockGap, 0.6));

      // 周一的「概率论与数理统计」(3-4 节) 与「线性代数」(5-6 节) 中间隔着午休行，
      // 空隙 = 休息行高度 + blockGap。
      expect(
        cardOf('线性代数').top - cardOf('概率论与数理统计').bottom,
        closeTo(TimetableGrid.breakHeight + TimetableGrid.blockGap, 0.6),
      );
    });
  });

  group('教务系统数据源', () {
    testWidgets('教务系统返回的课表能渲染到网格', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      // 线性代数在周一 5-6 节和周三 1-2 节各有一条
      expect(find.text('线性代数'), findsNWidgets(2));
      expect(find.text('Python程序设计'), findsNWidgets(2));
      expect(find.text('军事理论'), findsOneWidget);
      expect(find.text('@J1-507'), findsOneWidget);
      // 新课表接口会返回任课教师
      expect(find.text('王可芸'), findsWidgets);
      // 顶部不再显示加载态
      expect(find.textContaining('正在从教务系统获取'), findsNothing);
    });

    testWidgets('弹层能显示教务系统的周次、老师与地点', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('线性代数').first);
      await tester.pumpAndSettle();

      expect(find.text('课程详情'), findsOneWidget);
      expect(find.text('J1-507'), findsWidgets);
      // 周一那条「线性代数」在教务系统里是 4-7 周
      expect(find.text('第 4-7 周'), findsOneWidget);
      expect(find.text('王可芸'), findsWidgets);
    });

    testWidgets('会话失效时给出可读错误和重试按钮', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp(transport: jwExpiredTransport));
      await tester.pumpAndSettle();

      expect(find.textContaining('会话已失效'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });
}

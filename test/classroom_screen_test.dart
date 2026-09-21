import 'dart:math' as math;

import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:class_schedule/widgets/sheet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'fakes.dart';

/// 打开 App 并切到「空教室」页。
///
/// 空教室页有头部（chips + 日期条）加一排教室卡片，默认 800×600 的测试画布
/// 会把结果挤到屏幕外 —— ListView 不会构建视口外的东西，断言就会「找不到」。
/// 所以这里给一块够高的画布。
Future<RecordingTransport> openClassroom(
  WidgetTester tester, [
  RecordingTransport? transport,
]) async {
  tester.view.physicalSize = const Size(1500, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final RecordingTransport fake = transport ?? RecordingTransport();
  await tester.pumpWidget(jwApp(transport: fake.call));
  await tester.pumpAndSettle();

  // 底部导航项的文案是「教室状态」，课表页上没有这四个字，
  // 所以这里点到的就是底部导航那一项。
  await tester.tap(find.text('教室状态'));
  await tester.pumpAndSettle();
  return fake;
}

/// 1 → 「一」，7 → 「日」。
String weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

void main() {
  testWidgets('默认按今天查询，列出全部教室与占用小条', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final RecordingTransport fake = await openClassroom(tester);

    expect(fake.classroomBodies, hasLength(1));
    expect(fake.classroomBodies.single, contains('skxq1=${now.weekday}'));
    expect(fake.classroomBodies.single, contains('skxq2=${now.weekday}'));
    // 新设计是「占用一览」：四间教室全部列出，不再默认只列空闲。
    for (final String name in <String>[
      'J1-101',
      'J1-102',
      'J1-103',
      'J1-201',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('容量 60'), findsWidgets);
    expect(find.text('今天'), findsOneWidget); // 日期条默认选中今天
    expect(find.text('空闲'), findsOneWidget); // 图例
    expect(find.text('占用'), findsOneWidget);
    expect(find.textContaining('全天空闲 1 间'), findsOneWidget);
  });

  testWidgets('图例的分组标签与下方教室卡片的占用条逐组对齐', (WidgetTester tester) async {
    await openClassroom(tester);

    // 夹具一天 6 个大节 → 上午/下午/晚上各 2 根条。
    expect(find.text('上午'), findsOneWidget);
    expect(find.text('下午'), findsOneWidget);
    expect(find.text('晚上'), findsOneWidget);

    // 占用小条 = 7×24 的 ConstrainedBox（Container(width:7,height:24)）。
    final List<Rect> bars = <Rect>[];
    for (final Element element in tester.elementList(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is ConstrainedBox &&
            widget.constraints ==
                const BoxConstraints.tightFor(width: 7.0, height: 24.0),
      ),
    )) {
      final RenderBox box = element.renderObject! as RenderBox;
      bars.add(box.localToGlobal(Offset.zero) & box.size);
    }
    expect(bars, isNotEmpty);

    // 同一间教室卡片里的条 top 相同；取最上面那间卡片的 6 根，按横向排序。
    final double cardTop = bars
        .map<double>((Rect bar) => bar.top)
        .reduce(math.min);
    final List<Rect> cardBars = bars
        .where((Rect bar) => bar.top == cardTop)
        .toList()
      ..sort((Rect a, Rect b) => a.left.compareTo(b.left));
    expect(cardBars, hasLength(6));

    // 图例标签的中心要正对对应那组占用条的中心。
    double groupCenter(int index) =>
        (cardBars[index * 2].left + cardBars[index * 2 + 1].right) / 2;
    final List<String> labels = <String>['上午', '下午', '晚上'];
    for (var i = 0; i < labels.length; i++) {
      final double labelCenter = tester.getRect(find.text(labels[i])).center.dx;
      expect(
        (labelCenter - groupCenter(i)).abs(),
        lessThan(0.5),
        reason: '${labels[i]} 应与第 ${i + 1} 组占用条对齐',
      );
    }
  });

  testWidgets('点教室打开详情，按节次列出上课班级', (WidgetTester tester) async {
    await openClassroom(tester);

    await tester.tap(find.text('J1-103'));
    await tester.pumpAndSettle();

    // J1-103：第1-2节、第3-4节都是线性代数（陈志强），第7-8节概率论。
    expect(find.text('线性代数'), findsNWidgets(2));
    expect(find.text('陈志强'), findsNWidgets(2));
    expect(find.text('概率论与数理统计'), findsOneWidget);
    expect(find.text('周敏'), findsOneWidget);
    expect(find.text('第 1-2 节'), findsOneWidget);
    // 空着的节次显示「空闲」（详情里 3 处 + 图例 1 处）。
    expect(find.text('空闲'), findsWidgets);
  });

  testWidgets('详情弹层有白色 Material 底（forui 弹层不自带背景）', (WidgetTester tester) async {
    await openClassroom(tester);

    await tester.tap(find.text('J1-103'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('线性代数').first,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Material && widget.color == sheetSurfaceColor,
        ),
      ),
      findsOneWidget,
      reason: '弹层内容必须包在 SheetSurface（玻璃底 + Material）里，否则透出被压暗的页面',
    );
    // 液态玻璃：弹层本体一块 BackdropFilter，背后的 barrier 一块。
    expect(find.byType(BackdropFilter), findsAtLeastNWidgets(2));
  });

  testWidgets('点日期条会重新联网并带上新的周次与星期', (WidgetTester tester) async {
    final RecordingTransport fake = await openClassroom(tester);
    final int calls = fake.classroomBodies.length;

    final DateTime now = DateTime.now();
    final DateTime tomorrow = now.add(const Duration(days: 1));

    await tester.tap(find.text('${tomorrow.month}/${tomorrow.day}'));
    await tester.pumpAndSettle();

    expect(fake.classroomBodies, hasLength(calls + 1));
    expect(fake.classroomBodies.last, contains('skxq1=${tomorrow.weekday}'));
    expect(fake.classroomBodies.last, contains('skxq2=${tomorrow.weekday}'));
    expect(
      fake.classroomBodies.last,
      contains('zc1=${defaultTerm.weekOf(tomorrow)}'),
    );
  });

  testWidgets('切校区与教学楼会重新联网', (WidgetTester tester) async {
    final RecordingTransport fake = await openClassroom(tester);
    final int calls = fake.classroomBodies.length;

    await tester.tap(find.text('肇庆校区'));
    await tester.pumpAndSettle();
    expect(fake.classroomBodies, hasLength(calls + 1));
    expect(fake.classroomBodies.last, contains('xqid=19'));

    await tester.tap(find.text('第二教学楼'));
    await tester.pumpAndSettle();
    expect(fake.classroomBodies, hasLength(calls + 2));
    expect(fake.classroomBodies.last, contains('jzwid=00002'));
  });

  testWidgets('结果行只显示统计，不再有「只看空闲」开关', (WidgetTester tester) async {
    await openClassroom(tester);

    expect(find.text('只看空闲'), findsNothing);
    expect(find.textContaining('全天空闲'), findsOneWidget);

    // 所有教室都直接列出来，不做过滤。
    expect(find.text('J1-102'), findsOneWidget);
    expect(find.text('J1-101'), findsOneWidget);
  });

  testWidgets('会话失效时给出错误与「去登录」', (WidgetTester tester) async {
    await openClassroom(
      tester,
      RecordingTransport(
        classroomError: const JwException('教务系统会话已失效或未登录，请到「我的信息」页登录'),
      ),
    );

    expect(find.textContaining('会话已失效'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('教务系统没返回教室时给出可读提示', (WidgetTester tester) async {
    await openClassroom(
      tester,
      RecordingTransport(
        classroomHtml:
            '<html><body><table>'
            '<tr><th>教室</th><th>容量</th></tr>'
            '</table></body></html>',
      ),
    );

    expect(find.textContaining('没有查询到教室'), findsOneWidget);
  });

  testWidgets('搜索框按教室名本地过滤列表，不发请求', (WidgetTester tester) async {
    final RecordingTransport fake = await openClassroom(tester);
    final int calls = fake.classroomBodies.length;

    // 小写也能匹配（忽略大小写）。FTextField 内部是 EditableText，不是 Material TextField。
    await tester.enterText(find.byType(EditableText), 'j1-1');
    await tester.pumpAndSettle();

    expect(fake.classroomBodies, hasLength(calls)); // 纯本地过滤
    expect(find.text('J1-101'), findsOneWidget);
    expect(find.text('J1-102'), findsOneWidget);
    expect(find.text('J1-103'), findsOneWidget);
    expect(find.text('J1-201'), findsNothing);

    // 点清除按钮恢复完整列表。
    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.text('J1-101'), findsOneWidget);
    expect(find.text('J1-201'), findsOneWidget);
  });

  testWidgets('搜索没有匹配的教室时给出提示', (WidgetTester tester) async {
    await openClassroom(tester);

    await tester.enterText(find.byType(EditableText), 'N9-999');
    await tester.pumpAndSettle();

    expect(find.textContaining('没有找到教室'), findsOneWidget);
    expect(find.textContaining('换个关键字'), findsOneWidget);
  });
}

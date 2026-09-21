import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

  // 课表页上没有「空教室」这三个字，所以这里点到的就是底部导航那一项。
  await tester.tap(find.text('空教室'));
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
    for (final String name in <String>['J1-101', 'J1-102', 'J1-103', 'J1-201']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.textContaining('容量 60'), findsWidgets);
    expect(find.text('今天'), findsOneWidget); // 日期条默认选中今天
    expect(find.text('空闲'), findsOneWidget); // 图例
    expect(find.text('占用'), findsOneWidget);
    expect(find.textContaining('全天空闲 1 间'), findsOneWidget);
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

  testWidgets('「只看空闲」只留全天空闲的教室', (WidgetTester tester) async {
    await openClassroom(tester);

    await tester.tap(find.text('只看空闲'));
    await tester.pumpAndSettle();

    // 只有 J1-102 一整天都没课。
    expect(find.text('J1-102'), findsOneWidget);
    expect(find.text('J1-101'), findsNothing);
    expect(find.text('J1-103'), findsNothing);
    expect(find.text('J1-201'), findsNothing);
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
}

import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/main.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('学生信息解析', () {
    test('从真实主页面读出姓名/学号/院系/专业/班级', () {
      final JwStudentInfo student = JwStudentInfoParser.parse(
        fixtureWeekInfoHtml,
      );

      expect(student.name, '张三');
      expect(student.studentId, '202600000001');
      expect(student.department, '信息学院');
      expect(student.major, '软件工程');
      expect(student.className, '26软件工程2班');
      expect(student.isEmpty, isFalse);
    });

    test('页面里没有这些字段时返回空对象，不抛异常', () {
      final JwStudentInfo student = JwStudentInfoParser.parse('<html></html>');
      expect(student.isEmpty, isTrue);
    });

    test('主页面解析同时给出周次与学生信息', () {
      final JwMainPageInfo info = JwMainPageParser.parse(fixtureWeekInfoHtml);
      expect(info.week.week, 3);
      expect(info.week.totalWeeks, 20);
      expect(info.student.name, '张三');
    });
  });

  group('选课中心解析', () {
    test('真实页面当前没有开放轮次 → 空列表', () {
      expect(JwSelectionParser.parse(fixtureSelectionEmptyHtml), isEmpty);
    });

    test('有轮次时解析出名称/学期/时间/轮次 id', () {
      final List<JwSelectionRound> rounds = JwSelectionParser.parse(
        fixtureSelectionRoundsHtml,
      );

      expect(rounds, hasLength(2));
      expect(rounds.first.term, '2026-2027-1');
      expect(rounds.first.name, contains('通识选修课'));
      expect(rounds.first.timeRange, contains('2026-09-28'));
      expect(rounds.first.roundId, '2026092801');
      expect(rounds.last.roundId, '2026092102');
    });

    test('不是选课页面时给出可读错误', () {
      expect(
        () => JwSelectionParser.parse('<html><body>404</body></html>'),
        throwsA(isA<JwException>()),
      );
    });
  });

  group('控制器里的选课读取', () {
    test('读取成功后缓存，不重复请求', () async {
      final RecordingTransport transport = RecordingTransport(
        selectionHtml: fixtureSelectionRoundsHtml,
      );
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await controller.loadSelectionRounds();
      expect(controller.selectionRounds, hasLength(2));
      expect(controller.selectionError, isNull);

      final int calls = transport.methods.length;
      await controller.loadSelectionRounds(); // 第二次复用本次会话已读到的结果
      expect(transport.methods.length, calls);

      await controller.loadSelectionRounds(force: true); // 强制刷新
      expect(transport.methods.length, calls + 1);
      controller.dispose();
    });

    test('读取失败时给出可读错误', () async {
      final RecordingTransport transport = RecordingTransport(
        selectionError: const JwException('会话已失效'),
      );
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await controller.loadSelectionRounds();
      expect(controller.selectionRounds, isNull);
      expect(controller.selectionError, contains('会话已失效'));
      controller.dispose();
    });
  });

  group('底部导航', () {
    testWidgets('可以在课表 / 我的信息 / 选课 之间切换', (WidgetTester tester) async {
      await tester.pumpWidget(
        ClassScheduleApp(
          transport: RecordingTransport().call,
          swipeDebounce: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      // 默认在课表页
      expect(find.text('广应科课表'), findsOneWidget);
      expect(find.text('课表'), findsOneWidget); // 底部导航
      expect(find.text('选课'), findsOneWidget);

      // 切到「我的信息」：真实姓名来自主页面
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('202600000001'), findsOneWidget);
      expect(find.text('信息学院'), findsOneWidget);
      expect(find.text('广应科课表'), findsNothing);

      // 切到「选课」：真实页面当前没有轮次
      await tester.tap(find.text('选课'));
      await tester.pumpAndSettle();
      expect(find.text('当前没有开放的选课轮次'), findsOneWidget);
      expect(find.text('张三'), findsNothing);

      // 切回课表
      await tester.tap(find.text('课表'));
      await tester.pumpAndSettle();
      expect(find.text('广应科课表'), findsOneWidget);
    });

    testWidgets('有轮次时选课页列出轮次', (WidgetTester tester) async {
      await tester.pumpWidget(
        ClassScheduleApp(
          transport: RecordingTransport(
            selectionHtml: fixtureSelectionRoundsHtml,
          ).call,
          swipeDebounce: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('选课'));
      await tester.pumpAndSettle();

      expect(find.textContaining('通识选修课'), findsOneWidget);
      expect(find.textContaining('体育项目选课'), findsOneWidget);
      expect(find.text('轮次 2026092801'), findsOneWidget);
    });

  });
}

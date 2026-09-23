import 'dart:io';

import 'package:class_schedule/data/custom_course_store.dart';
import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/models/course.dart';
import 'package:class_schedule/models/custom_course.dart';
import 'package:class_schedule/models/reminder.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('自建课程模型', () {
    test('存档往返不丢字段', () {
      const CustomCourse course = CustomCourse(
        id: 'c1',
        name: '高等数学',
        weekday: 3,
        startPeriod: 3,
        endPeriod: 4,
        location: 'J1-507',
        teacher: '王老师',
        startWeek: 2,
        endWeek: 16,
      );

      expect(CustomCourse.fromJson(course.toJson()), course);
    });

    test('字段越界就地钳制', () {
      final CustomCourse? course = CustomCourse.fromJson(<String, dynamic>{
        'id': 'c2',
        'name': '越界课',
        'weekday': 99,
        'startPeriod': -5,
        'endPeriod': 999,
        'startWeek': 0,
        'endWeek': 99,
      });

      expect(course, isNotNull);
      expect(course!.weekday, DateTime.sunday);
      expect(course.startPeriod, CustomCourse.minPeriod);
      expect(course.endPeriod, CustomCourse.maxPeriod);
      expect(course.startWeek, CustomCourse.minWeek);
      expect(course.endWeek, CustomCourse.maxWeek);
    });

    test('结束节次早于起始节次时抬到起始节次', () {
      final CustomCourse? course = CustomCourse.fromJson(<String, dynamic>{
        'id': 'c3',
        'name': '反着的课',
        'weekday': 1,
        'startPeriod': 6,
        'endPeriod': 2,
      });

      expect(course!.startPeriod, 6);
      expect(course.endPeriod, 6);
    });

    test('没有 id 或没有名字就整条丢掉', () {
      expect(CustomCourse.fromJson(<String, dynamic>{'name': '没 id'}), isNull);
      expect(
        CustomCourse.fromJson(<String, dynamic>{'id': 'c4', 'name': '   '}),
        isNull,
      );
    });

    test('转成排课时带着自己的 id', () {
      const CustomCourse course = CustomCourse(
        id: 'c5',
        name: '自习',
        weekday: 2,
        startPeriod: 9,
        endPeriod: 10,
      );

      final CourseSession session = course.toSession();

      expect(session.customId, 'c5');
      expect(session.isCustom, isTrue);
      expect(session.course.name, '自习');
      expect(session.weekday, 2);
      expect(session.periodsLabel, '第 9-10 节');
    });

    test('周次范围决定哪几周上课', () {
      const CustomCourse course = CustomCourse(
        id: 'c6',
        name: '前半学期',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 3,
        endWeek: 8,
      );

      expect(course.isActiveInWeek(2), isFalse);
      expect(course.isActiveInWeek(3), isTrue);
      expect(course.isActiveInWeek(8), isTrue);
      expect(course.isActiveInWeek(9), isFalse);
      expect(course.weeksLabel, '第 3-8 周');
    });
  });

  group('自建课程存储', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('没存过时读出空列表', () async {
      const CustomCourseStore store = PrefsCustomCourseStore();

      expect(await store.read(), isEmpty);
    });

    test('写进去能原样读回来', () async {
      const CustomCourseStore store = PrefsCustomCourseStore();
      const CustomCourse course = CustomCourse(
        id: 'c1',
        name: '高数',
        weekday: 4,
        startPeriod: 1,
        endPeriod: 2,
        location: 'J1-101',
        teacher: '李老师',
        startWeek: 1,
        endWeek: 12,
      );

      await store.write(<CustomCourse>[course]);

      expect(await store.read(), <CustomCourse>[course]);
    });

    test('存档坏掉时返回空列表而不是抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsCustomCourseStore.storageKey: '{不是 JSON',
      });
      const CustomCourseStore store = PrefsCustomCourseStore();

      expect(await store.read(), isEmpty);
    });

    test('单条坏掉只丢那一条', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsCustomCourseStore.storageKey:
            '[{"id":"c1","name":"好的","weekday":1,"startPeriod":1,"endPeriod":2},'
            '{"bad":true},'
            '{"id":"c2","weekday":1,"startPeriod":1,"endPeriod":2}]',
      });
      const CustomCourseStore store = PrefsCustomCourseStore();

      final List<CustomCourse> courses = await store.read();

      expect(courses, hasLength(1));
      expect(courses.single.name, '好的');
    });
  });

  group('控制器里的自建课程', () {
    ScheduleController build({
      FakeCustomCourseStore? store,
      FakeReminderNotifier? notifier,
      List<CustomCourse>? restored,
      JwTransport? transport,
    }) => ScheduleController(
      transport: transport ?? jwOkTransport,
      accountStore: FakeAccountStore(),
      reminderNotifier: notifier ?? FakeReminderNotifier(),
      reminderStore: FakeReminderStore(),
      customCourseStore: store ?? FakeCustomCourseStore(),
      restoredCustomCourses: restored,
      swipeDebounce: Duration.zero,
    );

    /// 等冷启动那几件异步事（校准周次、取课表、查通知权限）跑完。
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 120));

    test('添加后立刻出现在课表上并落库', () async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      final ScheduleController controller = build(store: store);
      await settle();

      final CustomCourse? added = await controller.addCustomCourse(
        name: '晚自习',
        weekday: DateTime.now().weekday,
        startPeriod: 9,
        endPeriod: 11,
        startWeek: controller.todayWeek,
        endWeek: controller.todayWeek,
      );

      expect(added, isNotNull);
      expect(store.writes, 1);
      expect(store.value.single.name, '晚自习');
      final Iterable<CourseSession> mine = controller
          .sessionsOfWeek(controller.todayWeek)
          .where((CourseSession s) => s.course.name == '晚自习');
      expect(mine, hasLength(1));
      expect(mine.single.isCustom, isTrue);
      controller.dispose();
    });

    test('课程名是空的就不建', () async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      final ScheduleController controller = build(store: store);
      await settle();

      final CustomCourse? added = await controller.addCustomCourse(
        name: '   ',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 1,
        endWeek: 10,
      );

      expect(added, isNull);
      expect(controller.customCourses, isEmpty);
      expect(store.writes, 0, reason: '没建成就不该写盘');
      controller.dispose();
    });

    test('详情补充：旧接口把学分与课程属性补上', () async {
      final RecordingTransport recorder = RecordingTransport();
      final ScheduleController controller = build(transport: recorder.call);
      await settle();

      final int week = controller.todayWeek;
      final CourseSession session = controller
          .sessionsOfWeek(week)
          .firstWhere((CourseSession s) => s.course.name == '线性代数');
      expect(session.course.credits, isNull);
      expect(session.course.category, isNull);

      final CourseSession? enriched = await controller.loadEnrichedSession(
        session,
        week,
      );

      // 表单按日期提交：rq = 该周的星期一（本应用第 N 周从周日开始，+1 天才是
      // 教务口径第 N 周的星期一），sjmsValue 留空。
      final DateTime monday = controller.term.startOfWeek(week).add(
        const Duration(days: 1),
      );
      final String mm = monday.month.toString().padLeft(2, '0');
      final String dd = monday.day.toString().padLeft(2, '0');
      expect(recorder.loadkbBodies.single, 'rq=${monday.year}-$mm-$dd&sjmsValue=');

      expect(enriched, isNotNull);
      expect(enriched!.course.credits, '3');
      expect(enriched.course.category, '必修');
      // 本来就有的信息一律保留（新接口的老师、教室更准）。
      expect(enriched.course.teacher, session.course.teacher);
      expect(enriched.course.location, session.course.location);
      expect(enriched.startPeriod, session.startPeriod);
      expect(enriched.endPeriod, session.endPeriod);
      controller.dispose();
    });

    test('详情补充：第二次不再发请求（每周缓存）', () async {
      final RecordingTransport recorder = RecordingTransport();
      final ScheduleController controller = build(transport: recorder.call);
      await settle();

      final int week = controller.todayWeek;
      final CourseSession session = controller
          .sessionsOfWeek(week)
          .firstWhere((CourseSession s) => s.course.name == '线性代数');
      await controller.loadEnrichedSession(session, week);
      final CourseSession other = controller
          .sessionsOfWeek(week)
          .firstWhere((CourseSession s) => s.course.name == '概率论与数理统计');
      final CourseSession? second = await controller.loadEnrichedSession(
        other,
        week,
      );

      expect(recorder.loadkbBodies, hasLength(1));
      // 同周其它课直接用缓存的旧接口结果匹配（真实夹具里概率论 周一 3-4 也有）。
      expect(second, isNotNull);
      expect(second!.course.credits, '3');
      expect(second.course.category, '必修');
      controller.dispose();
    });

    test('详情补充：旧接口失败时安静返回 null', () async {
      final RecordingTransport recorder = RecordingTransport(
        loadkbError: const SocketException('boom'),
      );
      final ScheduleController controller = build(transport: recorder.call);
      await settle();

      final int week = controller.todayWeek;
      final CourseSession session = controller
          .sessionsOfWeek(week)
          .firstWhere((CourseSession s) => s.course.name == '线性代数');
      final CourseSession? enriched = await controller.loadEnrichedSession(
        session,
        week,
      );

      expect(enriched, isNull);
      expect(recorder.loadkbBodies, hasLength(1));
      controller.dispose();
    });

    test('越界钳制，起止给反了自动摆正', () async {
      final ScheduleController controller = build();
      await settle();

      final CustomCourse? added = await controller.addCustomCourse(
        name: '反着的课',
        weekday: 9,
        startPeriod: 6,
        endPeriod: 2,
        startWeek: 12,
        endWeek: 3,
      );

      expect(added!.weekday, DateTime.sunday);
      expect(added.startPeriod, 2);
      expect(added.endPeriod, 6);
      expect(added.startWeek, 3);
      expect(added.endWeek, 12);
      controller.dispose();
    });

    test('编辑覆盖同一条并落库', () async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      final ScheduleController controller = build(store: store);
      await settle();
      final CustomCourse added = (await controller.addCustomCourse(
        name: '高数',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 1,
        endWeek: 16,
      ))!;

      await controller.updateCustomCourse(added.copyWith(name: '高等数学'));

      expect(controller.customCourses, hasLength(1));
      expect(controller.customCourses.single.name, '高等数学');
      expect(store.value.single.name, '高等数学');
      controller.dispose();
    });

    test('删除后就从课表上消失', () async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      final ScheduleController controller = build(store: store);
      await settle();
      final CustomCourse added = (await controller.addCustomCourse(
        name: '临时课',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: controller.todayWeek,
        endWeek: controller.todayWeek,
      ))!;

      await controller.removeCustomCourse(added.id);

      expect(controller.customCourses, isEmpty);
      expect(controller.customCourseById(added.id), isNull);
      expect(store.value, isEmpty);
      controller.dispose();
    });

    test('冷启动立刻能用本机存着的课，不必等网络', () async {
      const CustomCourse saved = CustomCourse(
        id: 'c1',
        name: '自己加的课',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      );
      final ScheduleController controller = build(
        restored: <CustomCourse>[saved],
      );

      // 一帧都不等：本机数据应该已经在了。
      expect(controller.customCourses.single.name, '自己加的课');
      expect(controller.isReady, isTrue, reason: '只有自建课程的周也要能画出网格');
      controller.dispose();
    });

    test('退出登录不会带走自己加的课', () async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      final ScheduleController controller = build(store: store);
      await settle();
      await controller.addCustomCourse(
        name: '留着的课',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 1,
        endWeek: 16,
      );

      await controller.signOut();

      expect(controller.customCourses.single.name, '留着的课');
      expect(store.value, hasLength(1), reason: '登出只清教务侧的数据');
      controller.dispose();
    });

    test('教务课和自己加的课合并到同一周', () async {
      final ScheduleController controller = build();
      await settle();
      final int week = controller.todayWeek;
      final int remoteCount = controller
          .sessionsOfWeek(week)
          .where((CourseSession s) => !s.isCustom)
          .length;
      expect(remoteCount, greaterThan(0), reason: '夹具里这一周应该有教务课');

      await controller.addCustomCourse(
        name: '自习',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: week,
        endWeek: week,
      );

      final List<CourseSession> merged = controller.sessionsOfWeek(week);
      expect(merged.where((CourseSession s) => s.isCustom), hasLength(1));
      expect(
        merged.where((CourseSession s) => !s.isCustom),
        hasLength(remoteCount),
        reason: '合并不该动到教务那边的数据',
      );
      controller.dispose();
    });

    test('自己加的课也会排上课提醒', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = build(notifier: notifier);
      await settle();

      // 挂到「明天」：提醒时刻一定还在未来（planner 不补发已经过去的课）。
      final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
      final int week = controller.term.weekOf(tomorrow);
      expect(week, inInclusiveRange(1, controller.term.totalWeeks));

      // 起始节次用 2：提醒按「周×1000 + 星期×100 + 起始节次」去重，夹具课表的
      // 起始节次只落在 1/3/5/7/9 —— 用 2 保证无论明天是星期几都不会跟夹具撞号。
      await controller.addCustomCourse(
        name: '明天的自习',
        weekday: tomorrow.weekday,
        startPeriod: 2,
        endPeriod: 3,
        startWeek: week,
        endWeek: week,
      );

      expect(
        notifier.synced.where((ClassReminder r) => r.courseName == '明天的自习'),
        hasLength(1),
      );
      controller.dispose();
    });
  });

  group('课表页上的加号', () {
    /// 默认 800×600 太小：网格和表单都要撑开才有东西可点。
    Future<void> pumpApp(
      WidgetTester tester, {
      FakeCustomCourseStore? store,
      List<CustomCourse>? restored,
      JwTransport? transport,
    }) async {
      tester.view.physicalSize = const Size(1500, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        jwApp(customCourseStore: store, restoredCustomCourses: restored, transport: transport),
      );
      await tester.pumpAndSettle();
    }

    /// 旧课表接口返回带学分/课程属性的夹具，其余请求走默认夹具。
    Future<String> transportWithLoadkb(
      String method,
      Uri url,
      String body,
      Map<String, String> headers,
    ) async {
      if (url.path.contains('main_index_loadkb')) {
        return fixtureLoadkbHtml;
      }
      return jwOkTransport(method, url, body, headers);
    }

    testWidgets('右下角有加号，点开是添加课程表单', (WidgetTester tester) async {
      await pumpApp(tester);

      expect(find.byIcon(FLucideIcons.plus), findsOneWidget);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text('添加课程'), findsOneWidget);
      expect(find.text('星期'), findsOneWidget);
      expect(find.text('节次'), findsOneWidget);
      expect(find.text('周次'), findsOneWidget);
    });

    testWidgets('点「星期」行弹出全部选项列表，选中后更新行值', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      // 表单里「星期」是行标签；点这一行（默认值是「今天」）。
      await tester.tap(find.text('星期'));
      await tester.pumpAndSettle();

      // 弹层列出周一到周日共 7 个选项，当前值打勾。
      // 注：弹层当前值那项会和背后表单行的值文字重复，所以用 findsWidgets。
      expect(find.text('选择星期'), findsOneWidget);
      for (final String day in <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(find.text(day), findsWidgets, reason: day);
      }

      // 选「周三」：弹层关掉，行值更新。
      // 注意取 .last：表单星期行的默认值是「今天」——测试恰好在周三跑时行值
      // 也是「周三」，和弹层选项重名；弹层选项在组件树上更靠后，last 才是它。
      // （CI 曾因此固定在周三红：find.text('周三') 撞出两个、tap 拒绝歧义目标。）
      await tester.tap(find.text('周三').last);
      await tester.pumpAndSettle();

      expect(find.text('周三'), findsOneWidget);
      expect(find.text('选择星期'), findsNothing);
    });

    testWidgets('点「开始」节次行弹列表选择，把范围顶过去时结束节次跟着走', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();

      expect(find.text('选择开始节次'), findsOneWidget);
      expect(find.text('第 ${CustomCourse.maxPeriod} 节'), findsOneWidget);

      // 选最后一节：开始超过结束（默认 2），结束要被抬到同一节。
      await tester.tap(find.text('第 ${CustomCourse.maxPeriod} 节'));
      await tester.pumpAndSettle();

      expect(find.text('第 ${CustomCourse.maxPeriod} 节'), findsNWidgets(2));
    });

    testWidgets('点「到」周次行弹列表选择，选到更早的周时开始周跟着走', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      // 先把「从」选到第 5 周（默认 1 → 5）。
      await tester.tap(find.text('从'));
      await tester.pumpAndSettle();
      expect(find.text('选择开始周'), findsOneWidget);
      await tester.tap(find.text('第 5 周'));
      await tester.pumpAndSettle();
      expect(find.text('第 5 周'), findsOneWidget);

      // 再把「到」选到第 3 周：结束被拉到开始（第 5 周）之前，开始周要跟着走到第 3 周。
      await tester.tap(find.text('到'));
      await tester.pumpAndSettle();

      expect(find.text('选择结束周'), findsOneWidget);
      // 「第 1 周」在弹层里和背后表单「从」行各出现一次。
      expect(find.text('第 ${CustomCourse.minWeek} 周'), findsWidgets);

      await tester.tap(find.text('第 3 周'));
      await tester.pumpAndSettle();

      expect(find.text('选择结束周'), findsNothing);
      expect(find.text('第 3 周'), findsNWidgets(2));
    });

    testWidgets('填好课程名保存后，课表上多出一门课', (WidgetTester tester) async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      await pumpApp(tester, store: store);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();
      expect(find.text('晚自习'), findsNothing);

      await tester.enterText(find.byType(EditableText).first, '晚自习');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(store.value.single.name, '晚自习');
      expect(find.text('晚自习'), findsOneWidget);
    });

    testWidgets('课程名空着时保存按钮点不动', (WidgetTester tester) async {
      final FakeCustomCourseStore store = FakeCustomCourseStore();
      await pumpApp(tester, store: store);

      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, '保存')).onPress,
        isNull,
      );
      expect(store.writes, 0);
    });

    testWidgets('自己加的课能进编辑表单', (WidgetTester tester) async {
      const CustomCourse saved = CustomCourse(
        id: 'c1',
        name: '自己加的课',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      );
      await pumpApp(tester, restored: <CustomCourse>[saved]);

      await tester.tap(find.text('自己加的课'));
      await tester.pumpAndSettle();
      expect(find.text('编辑这门课'), findsOneWidget);

      // 详情收完再弹表单，表单里应该带着原来的课程名。
      await tester.tap(find.text('编辑这门课'));
      await tester.pumpAndSettle();
      expect(find.text('编辑课程'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText).first).controller.text,
        '自己加的课',
      );
    });

    testWidgets('教务系统拉的课没有编辑入口', (WidgetTester tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('线性代数').first);
      await tester.pumpAndSettle();

      expect(find.text('课程详情'), findsOneWidget);
      expect(find.text('编辑这门课'), findsNothing);
    });

    testWidgets('教务课详情会用旧接口补上学分与课程属性', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, transport: transportWithLoadkb);

      await tester.tap(find.text('线性代数').first);
      await tester.pumpAndSettle();

      // 旧接口夹具里线性代数学分 3、必修；补上后详情里要出现这两行。
      expect(find.text('学分'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('课程属性'), findsOneWidget);
      expect(find.text('必修'), findsOneWidget);
      expect(find.text('正在补充学分等信息…'), findsNothing);
    });

    testWidgets('编辑表单里两步确认可以删掉这门课', (WidgetTester tester) async {
      const CustomCourse saved = CustomCourse(
        id: 'c1',
        name: '要删的课',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
      );
      final FakeCustomCourseStore store = FakeCustomCourseStore(
        <CustomCourse>[saved],
      );
      await pumpApp(tester, store: store, restored: <CustomCourse>[saved]);

      await tester.tap(find.text('要删的课'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑这门课'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除这门课'));
      await tester.pumpAndSettle();
      expect(find.text('确认删除'), findsOneWidget);

      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();

      expect(store.value, isEmpty);
      expect(find.text('要删的课'), findsNothing);
    });
  });
}

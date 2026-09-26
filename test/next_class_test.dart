import 'package:class_schedule/models/course.dart';
import 'package:class_schedule/models/custom_course.dart';
import 'package:class_schedule/models/next_class.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 「下一节课」桌面小组件：条目计算（模型）与推送时机（控制器）。
///
/// 模型测试的「现在」是注入的，任何一天跑都一样；
/// 控制器测试涉及真实时钟，只断言与「明天」的相对关系（见已知坑 #7）。
void main() {
  // defaultTerm：第 1 周周日 = 2026-08-30，共 20 周。
  // 选 2026-09-21（周一，第 4 周）10:30 当「现在」：第一节刚下课、第三四节正上着。
  final DateTime now = DateTime(2026, 9, 21, 10, 30);

  CourseSession session(
    String name,
    int weekday,
    int startPeriod,
    int endPeriod, {
    String location = 'A-101',
    String teacher = '张三',
  }) => CourseSession(
    course: Course(name: name, location: location, teacher: teacher),
    weekday: weekday,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    startWeek: 1,
    endWeek: 20,
  );

  group('条目计算', () {
    test('正在上的课排第一，时间换算正确', () {
      final List<NextClassEntry> entries = buildNextClassEntries(
        term: defaultTerm,
        sessionsOf: (_) => <CourseSession>[
          session('体育', DateTime.tuesday, 3, 4),
          session('高数', DateTime.monday, 3, 4),
          session('英语', DateTime.monday, 1, 2),
        ],
        now: now,
      );

      final NextClassEntry first = entries.first;
      expect(first.name, '高数');
      expect(first.start, DateTime(2026, 9, 21, 10, 15));
      expect(first.end, DateTime(2026, 9, 21, 11, 50));
      expect(first.timeLabel, '10:15-11:50');
      expect(first.periodLabel, '第 3-4 节');
      expect(first.location, 'A-101');
      expect(first.teacher, '张三');
    });

    test('已下课的不再出现，其余按开始节次排序', () {
      final List<NextClassEntry> entries = buildNextClassEntries(
        term: defaultTerm,
        sessionsOf: (_) => <CourseSession>[
          session('第四节', DateTime.monday, 4, 4),
          session('第一节', DateTime.monday, 1, 2), // 9:05 已下课
        ],
        now: now,
      );

      expect(entries.map((NextClassEntry e) => e.name), <String>['第四节']);
    });

    test('今天没课就取明天的', () {
      final List<NextClassEntry> entries = buildNextClassEntries(
        term: defaultTerm,
        sessionsOf: (_) => <CourseSession>[
          session('大物', DateTime.tuesday, 1, 2),
        ],
        now: now,
      );

      expect(entries, hasLength(1));
      expect(entries.single.name, '大物');
      expect(entries.single.start, DateTime(2026, 9, 22, 8, 20));
    });

    test('三天外的不进列表（周日也照常映射）', () {
      // 2026-09-24 是周四（3 天外），2026-09-27 是周日（6 天外）。
      final List<NextClassEntry> entries = buildNextClassEntries(
        term: defaultTerm,
        sessionsOf: (_) => <CourseSession>[
          session('周四的课', DateTime.thursday, 1, 2),
          session('周日的课', DateTime.sunday, 1, 2),
        ],
        now: now,
      );

      expect(entries, isEmpty);
    });

    test('假期（学期外）没有条目', () {
      final List<NextClassEntry> entries = buildNextClassEntries(
        term: defaultTerm,
        sessionsOf: (_) => <CourseSession>[
          session('居然还在上课', DateTime.monday, 1, 2),
        ],
        now: DateTime(2027, 3, 1, 10, 0),
      );

      expect(entries, isEmpty);
    });
  });

  group('控制器推送', () {
    ScheduleController build({
      FakeCustomCourseStore? store,
      FakeWidgetUpdater? updater,
    }) => ScheduleController(
      transport: jwOkTransport,
      accountStore: FakeAccountStore(),
      reminderNotifier: FakeReminderNotifier(),
      reminderStore: FakeReminderStore(),
      customCourseStore: store ?? FakeCustomCourseStore(),
      widgetUpdater: updater ?? FakeWidgetUpdater(),
      swipeDebounce: Duration.zero,
    );

    /// 等冷启动那几件异步事（校准周次、取课表）跑完。
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 120));

    test('启动与课表到手后都会推送', () async {
      final FakeWidgetUpdater updater = FakeWidgetUpdater();
      final ScheduleController controller = build(updater: updater);
      expect(updater.pushes, 1, reason: '构造时先把手里已有的（自建课）推一遍');
      await settle();
      expect(updater.pushes, greaterThanOrEqualTo(2), reason: '第 4 周课表拉回后再推');
      controller.dispose();
    });

    test('加自建课后推送的内容里有这门课（定在明天）', () async {
      final FakeWidgetUpdater updater = FakeWidgetUpdater();
      final ScheduleController controller = build(updater: updater);
      await settle();

      final DateTime tomorrow = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      ).add(const Duration(days: 1));
      // 学期末跑测试时明天可能已经出了学期，那时跳过内容断言（相对日期测试的边界）。
      if (controller.term.weekOf(tomorrow) < 1 ||
          controller.term.weekOf(tomorrow) > controller.term.totalWeeks) {
        controller.dispose();
        return;
      }

      // 周次得用**明天**所在的那一周：本课表以周日为一周第一天，周六跑测试时
      // 「明天」（周日）已经落到下一周了，用今天所在的周会加不进这节课。
      final int tomorrowWeek = controller.term.weekOf(tomorrow);
      await controller.addCustomCourse(
        name: '毛概',
        weekday: tomorrow.weekday,
        startPeriod: 3,
        endPeriod: 4,
        startWeek: tomorrowWeek,
        endWeek: tomorrowWeek,
      );

      expect(updater.pushes, greaterThanOrEqualTo(3));
      final NextClassEntry mine = updater.last
          .firstWhere((NextClassEntry e) => e.name == '毛概');
      expect(mine.start, tomorrow.add(const Duration(hours: 10, minutes: 15)));
      expect(mine.timeLabel, '10:15-11:50');
      controller.dispose();
    });

    test('删除自建课后同样会推送', () async {
      final FakeWidgetUpdater updater = FakeWidgetUpdater();
      final ScheduleController controller = build(updater: updater);
      await settle();
      final int before = updater.pushes;

      final CustomCourse added = (await controller.addCustomCourse(
        name: '要删的课',
        weekday: DateTime.now().weekday,
        startPeriod: 9,
        endPeriod: 10,
        startWeek: 1,
        endWeek: 20,
      ))!;
      await controller.removeCustomCourse(added.id);

      expect(updater.pushes, greaterThan(before));
      controller.dispose();
    });

    test('推送失败不影响主流程', () async {
      final FakeWidgetUpdater updater = FakeWidgetUpdater()..error = Exception('炸了');
      final ScheduleController controller = build(updater: updater);
      await settle();

      await controller.addCustomCourse(
        name: '背锅课',
        weekday: DateTime.now().weekday,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 1,
        endWeek: 20,
      );
      expect(controller.customCourses.single.name, '背锅课');
      controller.dispose();
    });
  });
}

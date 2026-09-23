import 'package:class_schedule/data/class_notifier.dart';
import 'package:class_schedule/data/jw_account_store.dart';
import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/reminder_ring_platform.dart';
import 'package:class_schedule/data/reminder_store.dart';
import 'package:class_schedule/models/course.dart';
import 'package:class_schedule/models/reminder.dart';
import 'package:class_schedule/models/week.dart';
import 'package:class_schedule/state/reminder_planner.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// 轮询等待 [cond] 成立（异步收尾如延伸拉取不好精确计时，最多等 2 秒）。
Future<void> waitUntil(bool Function() cond) async {
  for (var i = 0; i < 100 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 一门课在第 [weekday] 天第 [startPeriod] 节。[weekday] 用 `DateTime.monday` 这类常量。
CourseSession session({
  required int weekday,
  required int startPeriod,
  int? endPeriod,
  int startWeek = 1,
  int endWeek = 20,
  String name = '高等数学',
  String location = 'J1-102',
}) => CourseSession(
  course: Course(name: name, location: location),
  weekday: weekday,
  startPeriod: startPeriod,
  endPeriod: endPeriod ?? startPeriod,
  startWeek: startWeek,
  endWeek: endWeek,
);

/// 排期用的固定学期：和 [defaultTerm] 一样是 2026-08-30（周日）开学、20 周。
///
/// 由此推出固定的日期坐标，下面所有断言都写死日期而不是「今天」，
/// 这样测试在周一到周日任何一天跑都得到同一个结果：
/// 第 4 周 = 9/20（日）~ 9/26（六），第 5 周 = 9/27 ~ 10/3，第 6 周 = 10/4 ~ 10/10。
final Term term = defaultTerm;

/// 第 4 周的周一（9/21）早上 7 点 —— 这一天这一周的课都还没上。
final DateTime mondayMorning = DateTime(2026, 9, 21, 7);

void main() {
  group('上课提醒设置', () {
    test('默认开着、提前 10 分钟', () {
      const ClassReminderSettings settings = ClassReminderSettings();
      expect(settings.enabled, isTrue);
      expect(settings.leadMinutes, 10);
      expect(settings.lead, const Duration(minutes: 10));
    });

    test('存下去读回来字段一个不少', () {
      const ClassReminderSettings source = ClassReminderSettings(
        enabled: false,
        leadMinutes: 30,
      );
      expect(ClassReminderSettings.fromJson(source.toJson()), source);
    });

    test('本地内容被改坏时退回默认值，而不是抛异常', () {
      expect(
        ClassReminderSettings.fromJson(<String, dynamic>{}),
        const ClassReminderSettings(),
      );
      expect(
        ClassReminderSettings.fromJson(<String, dynamic>{
          'enabled': '是',
          'lead': '十分钟',
        }),
        const ClassReminderSettings(),
      );
    });

    test('提前量超出范围时夹回范围内', () {
      expect(
        ClassReminderSettings.fromJson(<String, dynamic>{'lead': 0})
            .leadMinutes,
        ClassReminderSettings.minLeadMinutes,
      );
      expect(
        ClassReminderSettings.fromJson(<String, dynamic>{'lead': 9999})
            .leadMinutes,
        ClassReminderSettings.maxLeadMinutes,
      );
    });

    test('提前量文案', () {
      expect(
        const ClassReminderSettings(leadMinutes: 10).leadLabel,
        '提前 10 分钟',
      );
      expect(
        const ClassReminderSettings(leadMinutes: 45).leadLabel,
        '提前 45 分钟',
      );
      expect(const ClassReminderSettings(leadMinutes: 60).leadLabel, '提前 1 小时');
    });
  });

  group('提醒排期', () {
    List<ClassReminder> plan({
      required Map<int, List<CourseSession>> sessions,
      DateTime? now,
      bool enabled = true,
      int lead = ClassReminderSettings.defaultLeadMinutes,
    }) => planClassReminders(
      term: term,
      sessionsByWeek: sessions,
      settings: ClassReminderSettings(enabled: enabled, leadMinutes: lead),
      now: now ?? mondayMorning,
    );

    /// 第 4 周周一第 1-2 节的一门课。
    Map<int, List<CourseSession>> oneMondayClass() =>
        <int, List<CourseSession>>{
          4: <CourseSession>[
            session(weekday: DateTime.monday, startPeriod: 1, endPeriod: 2),
          ],
        };

    test('提醒时刻就是上课时刻往前推提前量', () {
      final List<ClassReminder> result = plan(sessions: oneMondayClass());

      expect(result, hasLength(1));
      final ClassReminder item = result.single;
      expect(item.startsAt, DateTime(2026, 9, 21, 8, 20));
      expect(item.endsAt, DateTime(2026, 9, 21, 9, 55));
      expect(item.at, DateTime(2026, 9, 21, 8, 10));
      expect(item.title, '还有 10 分钟上课');
      expect(item.body, '高等数学 · J1-102 · 08:20-09:55');
      expect(item.periodsLabel, '第 1-2 节');
      expect(item.whenLabel, '周一 9/21 08:20');
    });

    test('系统通知 id 由「周次 + 星期 + 起始节次」决定，同一节课每次算出来一样', () {
      final List<ClassReminder> first = plan(sessions: oneMondayClass());
      final List<ClassReminder> again = plan(
        sessions: oneMondayClass(),
        now: DateTime(2026, 9, 21, 7, 30),
      );

      expect(first.single.id, 4 * 1000 + 1 * 100 + 1);
      expect(
        again.single.id,
        first.single.id,
        reason: 'id 稳定，重排时才能精确覆盖掉上一次排的那条',
      );
    });

    test('关掉开关就什么都不排', () {
      expect(plan(sessions: oneMondayClass(), enabled: false), isEmpty);
    });

    test('已经上过的课不再提醒', () {
      expect(
        plan(sessions: oneMondayClass(), now: DateTime(2026, 9, 21, 10)),
        isEmpty,
      );
    });

    test('该提醒的时刻已经过去就不补发（免得每次冷启动都弹一串）', () {
      // 08:15 才打开 App，提前量 10 分钟意味着 08:10 该提醒 —— 已经过了
      expect(
        plan(sessions: oneMondayClass(), now: DateTime(2026, 9, 21, 8, 15)),
        isEmpty,
      );
      // 但把提前量缩到 3 分钟就还赶得上
      final List<ClassReminder> result = plan(
        sessions: oneMondayClass(),
        now: DateTime(2026, 9, 21, 8, 15),
        lead: 3,
      );
      expect(result, hasLength(1));
      expect(result.single.at, DateTime(2026, 9, 21, 8, 17));
    });

    test('周日是本周第一天（学期以周日开头）', () {
      final List<ClassReminder> result = plan(
        sessions: <int, List<CourseSession>>{
          4: <CourseSession>[session(weekday: DateTime.sunday, startPeriod: 1)],
        },
        now: DateTime(2026, 9, 19, 6), // 周六，早于 9/20
      );

      expect(result.single.startsAt, DateTime(2026, 9, 20, 8, 20));
      expect(result.single.whenLabel, '周日 9/20 08:20');
    });

    test('这门课这一周不上就不排', () {
      final Map<int, List<CourseSession>> sessions = <int, List<CourseSession>>{
        // 只在第 5 周上，却挂在第 4 周的数据里
        4: <CourseSession>[
          session(
            weekday: DateTime.monday,
            startPeriod: 1,
            startWeek: 5,
            endWeek: 5,
          ),
        ],
      };
      expect(plan(sessions: sessions), isEmpty);
    });

    test('排期窗口之外的课先不排（课表不落盘，只排手上这两周）', () {
      final Map<int, List<CourseSession>> sessions = <int, List<CourseSession>>{
        5: <CourseSession>[session(weekday: DateTime.monday, startPeriod: 1)],
        6: <CourseSession>[session(weekday: DateTime.monday, startPeriod: 1)],
      };

      // 9/21 07:00 + 14 天 = 10/5 07:00。第 5 周周一 9/28 在窗口内，
      // 第 6 周周一 10/5 的课要 10/5 08:10 提醒，已经出了窗口。
      final List<ClassReminder> result = plan(sessions: sessions);
      expect(result.map((ClassReminder item) => item.week), <int>[5]);
    });

    test('按提醒时刻从近到远排序', () {
      final Map<int, List<CourseSession>> sessions = <int, List<CourseSession>>{
        4: <CourseSession>[
          session(weekday: DateTime.wednesday, startPeriod: 1),
          session(weekday: DateTime.monday, startPeriod: 5),
          session(weekday: DateTime.monday, startPeriod: 1),
        ],
      };

      final List<ClassReminder> result = plan(
        sessions: sessions,
        now: DateTime(2026, 9, 20, 6),
      );
      expect(
        result.map((ClassReminder item) => item.whenLabel).toList(),
        <String>['周一 9/21 08:20', '周一 9/21 14:30', '周三 9/23 08:20'],
      );
    });

    test('节次表里没有的节次算不出时间，跳过', () {
      expect(
        plan(
          sessions: <int, List<CourseSession>>{
            4: <CourseSession>[
              session(weekday: DateTime.monday, startPeriod: 99),
            ],
          },
        ),
        isEmpty,
      );
    });

    test('学期外的周次不排', () {
      final List<ClassReminder> result = planClassReminders(
        term: Term(startDate: DateTime(2026, 8, 30), totalWeeks: 4),
        sessionsByWeek: <int, List<CourseSession>>{
          4: <CourseSession>[session(weekday: DateTime.monday, startPeriod: 1)],
          5: <CourseSession>[session(weekday: DateTime.monday, startPeriod: 1)],
        },
        settings: const ClassReminderSettings(),
        now: mondayMorning,
      );

      expect(result.map((ClassReminder item) => item.week), <int>[4]);
    });

    test('同一格重复的数据只排一条', () {
      final Map<int, List<CourseSession>> sessions = <int, List<CourseSession>>{
        4: <CourseSession>[
          session(weekday: DateTime.monday, startPeriod: 1),
          session(
            weekday: DateTime.monday,
            startPeriod: 1,
            name: '高等数学（重复的一条）',
          ),
        ],
      };
      expect(plan(sessions: sessions), hasLength(1));
    });

    test('提前量一改，提醒时刻和文案都跟着变', () {
      final List<ClassReminder> result = plan(
        sessions: oneMondayClass(),
        lead: 30,
      );

      expect(result.single.at, DateTime(2026, 9, 21, 7, 50));
      expect(result.single.title, '还有 30 分钟上课');
      expect(result.single.body, '高等数学 · J1-102 · 08:20-09:55');
    });
  });

  group('SharedPreferences 里的提醒设置', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('没存过时读到 null（调用方用默认值）', () async {
      expect(await const PrefsReminderStore().read(), isNull);
    });

    test('存下去能读回来', () async {
      const PrefsReminderStore store = PrefsReminderStore();
      await store.write(
        const ClassReminderSettings(enabled: false, leadMinutes: 20),
      );

      final ClassReminderSettings? back = await store.read();
      expect(back?.enabled, isFalse);
      expect(back?.leadMinutes, 20);
    });

    test('本地内容不是 JSON、或者不是对象时当作没存过', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsReminderStore.storageKey: '这不是 JSON',
      });
      expect(await const PrefsReminderStore().read(), isNull);

      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsReminderStore.storageKey: '[1, 2, 3]',
      });
      expect(await const PrefsReminderStore().read(), isNull);
    });
  });

  group('控制器里的上课提醒', () {
    Future<ScheduleController> boot({
      ClassReminderNotifier? notifier,
      ReminderStore? store,
      ClassReminderSettings? restored,
      JwTransport? transport,
      JwStoredAccount? account,
      ReminderRingPlatform? ring,
    }) async {
      final ScheduleController controller = ScheduleController(
        transport: transport ?? RecordingTransport().call,
        accountStore: FakeAccountStore(account),
        restoredAccount: account,
        reminderNotifier: notifier ?? FakeReminderNotifier(),
        reminderStore: store ?? FakeReminderStore(),
        restoredReminder: restored,
        ringPlatform: ring ?? FakeReminderRingPlatform(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return controller;
    }

    test('冷启动就按现有课表把提醒排上，内存里能读到同一份', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(notifier: notifier);

      expect(notifier.syncs, greaterThanOrEqualTo(1));
      expect(controller.reminders, notifier.synced);
      expect(controller.reminderError, isNull);
      controller.dispose();
    });

    test('关掉开关立刻清掉已排的提醒，并且落盘', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final FakeReminderStore store = FakeReminderStore();
      final ScheduleController controller = await boot(
        notifier: notifier,
        store: store,
      );

      await controller.updateReminderSettings(
        const ClassReminderSettings(enabled: false),
      );

      expect(controller.reminders, isEmpty);
      expect(notifier.synced, isEmpty);
      expect(notifier.cancels, greaterThanOrEqualTo(1));
      expect(store.value?.enabled, isFalse);
      expect(store.writes, 1);
      controller.dispose();
    });

    test('提前量可以自定义，改完按新值重排', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final FakeReminderStore store = FakeReminderStore();
      final ScheduleController controller = await boot(
        notifier: notifier,
        store: store,
      );

      await controller.updateReminderSettings(
        const ClassReminderSettings(leadMinutes: 45),
      );

      expect(controller.reminderSettings.leadMinutes, 45);
      expect(store.value?.leadMinutes, 45);
      controller.dispose();
    });

    test('本机存过的设置会先认下来（关着就一条都不排）', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(
        notifier: notifier,
        restored: const ClassReminderSettings(enabled: false),
      );

      expect(controller.reminderSettings.enabled, isFalse);
      expect(notifier.syncs, 0, reason: '关着的时候不该去碰系统闹钟');
      expect(notifier.permissionRequests, 0, reason: '没开提醒就别弹权限框');
      controller.dispose();
    });

    test('重新打开开关会申请权限，拿到就排期', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier(
        granted: false,
      );
      final ScheduleController controller = await boot(
        notifier: notifier,
        restored: const ClassReminderSettings(enabled: false),
      );

      notifier.granted = true;
      await controller.updateReminderSettings(
        const ClassReminderSettings(enabled: true),
      );
      final bool granted = await controller.requestReminderPermission();

      expect(granted, isTrue);
      expect(controller.reminderPermissionGranted, isTrue);
      expect(notifier.permissionRequests, greaterThanOrEqualTo(1));
      expect(notifier.syncs, greaterThanOrEqualTo(1));
      controller.dispose();
    });

    test('拿到通知权限后顺手带去开响铃（响铃默认化）', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier(
        granted: false,
      );
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: false,
      );
      final ScheduleController controller = await boot(
        notifier: notifier,
        ring: ring,
        restored: const ClassReminderSettings(enabled: false),
      );

      notifier.granted = true;
      await controller.updateReminderSettings(
        const ClassReminderSettings(enabled: true),
      );
      await controller.requestReminderPermission();

      expect(
        ring.openSettingsCalls,
        1,
        reason: '还没拿到勿扰豁免就带用户去开「允许勿扰打扰」',
      );
      controller.dispose();
    });

    test('响铃已授权时申请权限不再跳设置', () async {
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: true,
      );
      final ScheduleController controller = await boot(
        notifier: FakeReminderNotifier(granted: false),
        ring: ring,
        restored: const ClassReminderSettings(enabled: false),
      );

      await controller.requestReminderPermission();

      expect(ring.openSettingsCalls, 0);
      controller.dispose();
    });

    test('权限被拒时不去跳响铃设置', () async {
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: false,
      );
      final ScheduleController controller = await boot(
        notifier: FakeReminderNotifier(granted: false),
        ring: ring,
        restored: const ClassReminderSettings(enabled: false),
      );

      await controller.requestReminderPermission();

      expect(controller.reminderPermissionGranted, isFalse);
      expect(ring.openSettingsCalls, 0);
      controller.dispose();
    });

    test('权限被拒时提醒照样排，只是界面要提示去放行', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier(
        granted: false,
      );
      final ScheduleController controller = await boot(notifier: notifier);

      expect(controller.reminderPermissionGranted, isFalse);
      expect(
        controller.reminderSettings.enabled,
        isTrue,
        reason: '用户的开关不该被系统权限状态改掉',
      );
      expect(
        notifier.syncs,
        greaterThanOrEqualTo(1),
        reason: '权限没给也要排上，用户一放行就立刻生效',
      );
      controller.dispose();
    });

    test('平台不支持系统通知时完全不碰系统', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier(
        supported: false,
      );
      final ScheduleController controller = await boot(notifier: notifier);

      expect(controller.reminderSupported, isFalse);
      expect(notifier.syncs, 0);
      expect(notifier.permissionRequests, 0);
      controller.dispose();
    });

    test('排期内容没变就不重复折腾系统闹钟', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(notifier: notifier);
      final int before = notifier.syncs;

      await controller.resyncReminders();
      expect(notifier.syncs, before + 1, reason: '强制重排要真的下发一遍');

      controller.updateSettings(controller.settings); // 学期设置没变
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(notifier.syncs, before + 1, reason: '内容和上次一样就别再下发');
      controller.dispose();
    });

    test('退出登录后已排的提醒会被清掉', () async {
      const JwStoredAccount account = JwStoredAccount(cookie: 'JSESSIONID=a');
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(
        notifier: notifier,
        transport: jwExpiredTransport,
        account: account,
      );
      final int before = notifier.syncs;

      await controller.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(controller.reminders, isEmpty);
      expect(notifier.synced, isEmpty);
      expect(
        notifier.syncs,
        greaterThan(before),
        reason: '清空也要主动下发一次空排期，不能只在内存里抹掉',
      );
      controller.dispose();
    });

    test('冷启动就把提醒窗口覆盖到的周自动往下拉回来', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(notifier: notifier);

      // 窗口末端（now + 14 天）可能落在还没预取的周上，等它拉完。
      final DateTime now = DateTime.now();
      final int first = controller.term.weekOf(now);
      final int last = controller.term.weekOf(now.add(reminderHorizon));
      await waitUntil(
        () =>
            first > last ||
            controller.serverWeekOf(
                  last.clamp(1, controller.term.totalWeeks),
                ) !=
                null,
      );

      for (int week = first; week <= last; week++) {
        if (week < 1 || week > controller.term.totalWeeks) {
          continue;
        }
        expect(controller.serverWeekOf(week), isNotNull, reason: '第 $week 周');
      }
      controller.dispose();
    });

    test('回到前台时接着往下延伸排期（提醒触发后窗口往前挪）', () async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(notifier: notifier);
      final int syncedAfterBoot = notifier.syncs;

      await controller.onAppResumed();

      expect(notifier.syncs, greaterThanOrEqualTo(syncedAfterBoot));
      final int last = controller.term.weekOf(
        DateTime.now().add(reminderHorizon),
      );
      if (last <= controller.term.totalWeeks) {
        expect(controller.serverWeekOf(last), isNotNull);
      }
      controller.dispose();
    });

    test('拉不到课表（会话失效）时往下查询安静失败，不炸也不重试循环', () async {
      const JwStoredAccount account = JwStoredAccount(cookie: 'JSESSIONID=a');
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final ScheduleController controller = await boot(
        notifier: notifier,
        transport: jwExpiredTransport,
        account: account,
      );

      // 能在超时内跑完（没有死循环重试）就是这条测试要验证的。
      await controller.onAppResumed();

      expect(controller.reminderSupported, isTrue);
      controller.dispose();
    });

    test('冷启动顺手查一遍勿扰豁免状态（响铃用）', () async {
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: true,
      );
      final ScheduleController controller = await boot(ring: ring);

      expect(controller.ringSupported, isTrue);
      expect(controller.dndAccess, isTrue);
      controller.dispose();
    });

    test('没授权时跳转走的是勿扰授权页', () async {
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: false,
      );
      final ScheduleController controller = await boot(ring: ring);

      expect(controller.dndAccess, isFalse);
      expect(await controller.openRingSettings(), isTrue);
      expect(ring.openSettingsCalls, 1);
      controller.dispose();
    });

    test('平台不支持勿扰豁免时状态保持未知，不瞎给状态', () async {
      final ScheduleController controller = await boot(
        ring: FakeReminderRingPlatform(supported: false),
      );

      expect(controller.ringSupported, isFalse);
      expect(controller.dndAccess, isNull);
      controller.dispose();
    });
  });

  group('设置页的上课提醒', () {
    /// 打开设置页。[height] 给大一点：ListView 不会构建视口外的子项，
    /// 默认 800×600 的画布下「上课提醒」后半截根本不在树里。
    Future<void> openSettings(
      WidgetTester tester, {
      required ClassReminderNotifier notifier,
      required ReminderStore store,
      ReminderRingPlatform? ring,
    }) async {
      tester.view.physicalSize = const Size(1500, 4200);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        jwApp(
          reminderNotifier: notifier,
          reminderStore: store,
          ringPlatform: ring,
        ),
      );
      await tester.pumpAndSettle();
      // 三个点菜单已移除，设置入口在「我的信息」页。
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      // 设置页改成了二级页面结构：提醒类在「上课提醒」子页里。
      await tester.tap(find.text('上课提醒'));
      await tester.pumpAndSettle();
    }

    testWidgets('能关掉提醒、能改提前量，改完都落盘', (WidgetTester tester) async {
      final FakeReminderNotifier notifier = FakeReminderNotifier();
      final FakeReminderStore store = FakeReminderStore();
      await openSettings(tester, notifier: notifier, store: store);

      expect(find.text('上课提醒'), findsOneWidget);
      expect(find.text('上课前提醒'), findsOneWidget);
      expect(find.text('提前时间'), findsOneWidget);
      expect(find.text('提前 10 分钟'), findsOneWidget);

      // 改提前量：点「30 分钟」那一格
      await tester.tap(find.text('30 分钟'));
      await tester.pumpAndSettle();
      expect(find.text('提前 30 分钟'), findsOneWidget);
      expect(store.value?.leadMinutes, 30);

      // 关掉开关（「上课提醒」区在最前面，所以第一个开关就是它）
      await tester.tap(find.byType(FSwitch).first);
      await tester.pumpAndSettle();
      expect(store.value?.enabled, isFalse);
      expect(
        find.text('提前时间'),
        findsOneWidget,
        reason: '关掉之后提前量的设置本身还在，只是暂时不生效',
      );
      expect(find.text('已排提醒'), findsNothing);
    });

    testWidgets('平台不支持时说明原因，不给一个点不动的假开关', (WidgetTester tester) async {
      await openSettings(
        tester,
        notifier: FakeReminderNotifier(supported: false),
        store: FakeReminderStore(),
      );

      expect(find.text('上课前提醒'), findsOneWidget);
      expect(find.textContaining('当前平台不支持系统通知'), findsOneWidget);
      expect(find.text('已排提醒'), findsNothing);
    });

    testWidgets('没授权勿扰豁免时提示去授权，点「去授权」跳系统页', (
      WidgetTester tester,
    ) async {
      final FakeReminderRingPlatform ring = FakeReminderRingPlatform(
        granted: false,
      );
      await openSettings(
        tester,
        notifier: FakeReminderNotifier(),
        store: FakeReminderStore(),
        ring: ring,
      );

      expect(find.textContaining('提醒不会响铃'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);

      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();
      expect(ring.openSettingsCalls, 1);
    });

    testWidgets('已授权勿扰豁免时显示响铃状态，不再提示', (
      WidgetTester tester,
    ) async {
      await openSettings(
        tester,
        notifier: FakeReminderNotifier(),
        store: FakeReminderStore(),
        ring: FakeReminderRingPlatform(granted: true),
      );

      expect(find.text('响铃'), findsOneWidget);
      expect(find.textContaining('照常响铃'), findsOneWidget);
      expect(find.text('去设置'), findsNothing);
    });

    testWidgets('勿扰豁免状态未知（查不到）时两边都不显示', (
      WidgetTester tester,
    ) async {
      await openSettings(
        tester,
        notifier: FakeReminderNotifier(),
        store: FakeReminderStore(),
        ring: FakeReminderRingPlatform(granted: null),
      );

      expect(find.text('去设置'), findsNothing);
      expect(find.text('响铃'), findsNothing);
    });
  });
}

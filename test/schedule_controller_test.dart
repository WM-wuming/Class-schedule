import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/data/jw_account_store.dart';
import 'package:class_schedule/models/course.dart';
import 'package:class_schedule/state/reminder_planner.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 加载策略：快照水合、总课表补拉、内存复用、请求去重、滑动防抖、失败降级。
///
/// 课表的**加载源是本地的整学期 JSON 快照**（见 `timetable_cache.dart`）：
/// 快照齐全时冷启动零课表请求；快照缺周、登录新账号或手动刷新时，
/// 才用课表接口（`xskb_list.do`）逐周拉「总课表」合并回快照。
Future<void> waitUntilReady(bool Function() cond) async {
  for (var i = 0; i < 200 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

CourseSession sessionOf(String name) => CourseSession(
  course: Course(name: name, location: 'J3-311', teacher: '王可芸'),
  weekday: DateTime.monday,
  startPeriod: 1,
  endPeriod: 2,
  startWeek: 1,
  endWeek: 20,
);

Map<int, List<CourseSession>> fullCache([int totalWeeks = 20]) => <int,
  List<CourseSession>>{
  for (var week = 1; week <= totalWeeks; week++) week: <CourseSession>[
    sessionOf('第 $week 周的课'),
  ],
};

void main() {
  test('启动时拉取当前周并预取相邻周（没有任何快照时的首次启动）', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      timetableCacheStore: FakeTimetableCacheStore(),
      swipeDebounce: Duration.zero,
    );
    // 等当前周加载完 + 预取防抖（300ms）触发
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final int week = controller.currentWeek;
    expect(controller.isReady, isTrue);
    expect(controller.sessionsOfWeek(week), isNotEmpty);

    // 没有会话时不会去拉总课表（拉了也只会被教务系统打回登录页），
    // 冷启动只拉当前周 + 相邻周（预取让左右滑动秒开）+ 提醒排期窗口覆盖的周。
    final DateTime now = DateTime.now();
    final int horizonFirst = controller.term.weekOf(now);
    final int horizonLast = controller.term.weekOf(now.add(reminderHorizon));
    final Set<int> expectedWeeks = <int>{
      week - 1,
      for (int w = horizonFirst; w <= horizonLast; w++) w,
    };
    final int expected = expectedWeeks
        .where((int w) => w >= 1 && w <= controller.term.totalWeeks)
        .length;
    expect(transport.callCount, expected, reason: '当前周 + 相邻周 + 提醒窗口周');
    controller.dispose();
  });

  test('本地快照齐全时冷启动零课表请求，任何一周都从快照加载', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      timetableCacheStore: FakeTimetableCacheStore(),
      restoredTimetableCache: fullCache(),
      swipeDebounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // 唯一的请求是主页面周次校准（GET），课表接口一次都没发。
    expect(transport.bodies, isEmpty, reason: '课表全部来自本地快照');
    for (final int week in <int>[1, 7, controller.currentWeek, 20]) {
      expect(controller.sessionsOfWeek(week), isNotEmpty, reason: '第 $week 周');
    }
    controller.dispose();
  });

  test('有会话且快照缺周时，后台只补拉缺失的周并整份写回快照', () async {
    final RecordingTransport transport = RecordingTransport();
    final FakeTimetableCacheStore cacheStore = FakeTimetableCacheStore();
    const JwStoredAccount account = JwStoredAccount(cookie: 'JSESSIONID=x');
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      accountStore: FakeAccountStore(account),
      restoredAccount: account,
      timetableCacheStore: cacheStore,
      restoredTimetableCache: <int, List<CourseSession>>{
        for (final int week in <int>[3, 4, 5]) week: <CourseSession>[
          sessionOf('快照里第 $week 周'),
        ],
      },
      swipeDebounce: Duration.zero,
    );

    // 等总课表补拉完成：第 1..20 周里除快照已有的 3/4/5 周外都要各发一次请求。
    final int total = controller.term.totalWeeks;
    await waitUntilReady(() => transport.callCount >= total - 3);

    final Set<int> requested = <int>{
      for (final String body in transport.bodies)
        int.parse(
          RegExp(r'zc=(\d+)').firstMatch(body)!.group(1)!,
        ),
    };
    expect(requested, <int>{
      for (var week = 1; week <= total; week++)
        if (week != 3 && week != 4 && week != 5) week,
    }, reason: '快照里已有的周不重复联网');

    // 快照整份写回：20 周全在（含补拉的），原有的 3/4/5 周内容保留。
    await waitUntilReady(() => cacheStore.writes > 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cacheStore.value.keys, containsAll(<int>[1, 3, 10, total]));
    expect(
      cacheStore.value[3]!.single.course.name,
      '快照里第 3 周',
      reason: '快照已有的周不该被补拉覆盖',
    );
    controller.dispose();
  });

  test('快速连续滑动基本不发请求，只在停下的那周请求', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      timetableCacheStore: FakeTimetableCacheStore(),
      swipeDebounce: const Duration(milliseconds: 120),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final int start = controller.currentWeek;
    transport.bodies.clear();

    // 连续滑 8 周：滑过的周次都不该各发一次请求
    for (var i = 0; i < 8; i++) {
      controller.nextWeek();
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));

    String bodyOf(int week) => JwTimetableClient.weekQueryBody(week);

    final int landed = controller.currentWeek;
    expect(landed, greaterThan(start));
    expect(
      transport.bodies.where((String b) => b == bodyOf(landed)).length,
      1,
      reason: '最终停留的周只请求一次',
    );
    expect(
      transport.bodies.length,
      lessThanOrEqualTo(3),
      reason: '8 次滑动最多只应产生「停留周 + 相邻两周」的请求',
    );
    controller.dispose();
  });

  test('并发 refresh 只跑一轮总拉取：整学期每周恰好请求一次', () async {
    final RecordingTransport transport = RecordingTransport(
      delay: const Duration(milliseconds: 20),
    );
    final FakeTimetableCacheStore cacheStore = FakeTimetableCacheStore();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      timetableCacheStore: cacheStore,
      swipeDebounce: Duration.zero,
    );
    // 等启动阶段（当前周 + 提醒窗口）完全结束，再清零后只数刷新的请求。
    await Future<void>.delayed(const Duration(milliseconds: 700));
    transport.bodies.clear();
    cacheStore.value = <int, List<CourseSession>>{};

    await Future.wait<void>(<Future<void>>[
      controller.refresh(),
      controller.refresh(),
      controller.refresh(),
    ]);

    final int total = controller.term.totalWeeks;
    expect(transport.callCount, total, reason: '一轮总拉取 = 每周一次');
    for (var week = 1; week <= total; week++) {
      expect(
        transport.bodies.where(
          (String b) => b == JwTimetableClient.weekQueryBody(week),
        ),
        hasLength(1),
        reason: '第 $week 周只请求一次',
      );
    }
    // 拉完全部落盘成快照，每周都在。
    expect(cacheStore.value.keys.length, total);
    controller.dispose();
  });

  test('同一次会话内回到已加载的周不再发请求', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      timetableCacheStore: FakeTimetableCacheStore(),
      swipeDebounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final int week = controller.currentWeek;
    expect(controller.sessionsOfWeek(week), isNotEmpty);

    final String bodyOf = JwTimetableClient.weekQueryBody(week);
    transport.bodies.clear();

    controller.nextWeek();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    controller.previousWeek();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.currentWeek, week);
    expect(
      transport.bodies,
      isNot(contains(bodyOf)),
      reason: '已经拿过的周直接复用内存数据，不该再联网',
    );
    controller.dispose();
  });

  test('刷新失败：降级为提示，不清空已有课表', () async {
    final RecordingTransport transport = RecordingTransport();
    bool fail = false;
    final ScheduleController controller = ScheduleController(
      transport:
          (
            String method,
            Uri url,
            String body,
            Map<String, String> requestHeaders,
          ) async {
            if (fail) {
              throw const JwException('会话已失效');
            }
            return transport.call(method, url, body, requestHeaders);
          },
      timetableCacheStore: FakeTimetableCacheStore(),
      swipeDebounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final int week = controller.currentWeek;
    expect(controller.sessionsOfWeek(week), isNotEmpty);

    fail = true;
    await controller.refresh();

    expect(controller.sessionsOfWeek(week), isNotEmpty, reason: '已有课表不该被清空');
    expect(controller.error, isNull, reason: '有旧数据时不该是致命错误');
    expect(controller.notice, contains('会话已失效'));
    controller.dispose();
  });
}

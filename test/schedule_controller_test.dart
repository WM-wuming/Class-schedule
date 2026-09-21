import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 加载策略：内存复用、请求去重、滑动防抖、相邻周预取、失败降级。
///
/// 课表不落盘（落盘的只有账户信息，见 `jw_account_store_test.dart`），
/// 所以「重启后秒开」这类断言不存在 —— 冷启动一定先联网，这里只验证同一进程内的行为。
void main() {
  test('启动时拉取当前周并预取相邻周', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      swipeDebounce: Duration.zero,
    );
    // 等当前周加载完 + 预取防抖（300ms）触发
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final int week = controller.currentWeek;
    expect(controller.isReady, isTrue);
    expect(controller.sessionsOfWeek(week), isNotEmpty);

    final int expected = <int>[
      week - 1,
      week,
      week + 1,
    ].where((int w) => w >= 1 && w <= controller.term.totalWeeks).length;
    expect(transport.callCount, expected, reason: '当前周 + 相邻周（预取让左右滑动秒开）');
    controller.dispose();
  });

  test('快速连续滑动基本不发请求，只在停下的那周请求', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
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

  test('同一周并发刷新会去重', () async {
    final RecordingTransport transport = RecordingTransport(
      delay: const Duration(milliseconds: 60),
    );
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      swipeDebounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    transport.bodies.clear();

    await Future.wait<void>(<Future<void>>[
      controller.refresh(),
      controller.refresh(),
      controller.refresh(),
    ]);

    expect(transport.callCount, 1);
    controller.dispose();
  });

  test('同一次会话内回到已加载的周不再发请求', () async {
    final RecordingTransport transport = RecordingTransport();
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
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

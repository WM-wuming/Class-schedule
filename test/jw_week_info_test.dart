import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/models/week.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 用主页面（`xsMain_new_*.jsp`）确定当前周次，并校准学期起止。
void main() {
  group('主页面周次解析', () {
    test('从真实主页面读出「第3周/20周」', () {
      final JwWeekInfo info = JwWeekInfoParser.parseMainPage(
        fixtureWeekInfoHtml,
      );
      expect(info.week, 3);
      expect(info.totalWeeks, 20);
    });

    test('主页面用脚本赋值周次时也能读出来', () {
      expect(
        JwWeekInfoParser.parseMainPage(
          '<div id="li_showWeek"><span class="x">第4周</span>/20周</div>',
        ).week,
        4,
      );
      expect(
        JwWeekInfoParser.parseMainPage(
          '<script>\$("#li_showWeek").html("<span>第5周</span>/18周");</script>',
        ).totalWeeks,
        18,
      );
    });

    test('登录页会给出可读错误', () {
      expect(
        () => JwWeekInfoParser.parseMainPage(
          '<html><head><title>用户登录</title></head><body>统一身份认证</body></html>',
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('会话'),
          ),
        ),
      );
    });
  });

  test('用主页面周次校准开学日期与总周数（本地设置错了也能纠正）', () async {
    // 刻意钉住静态夹具（「第 3 周」）：这条测的是校准公式本身，周次要写死在断言里
    final RecordingTransport transport = RecordingTransport(
      weekInfoHtml: fixtureWeekInfoHtml,
    );
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      swipeDebounce: Duration.zero,
      // 故意给一个错的学期：开学日期错、总周数错
      settings: AppSettings(
        term: Term(startDate: DateTime(2026, 1, 4), totalWeeks: 8),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 主页面说「现在第 3 周」，其周一 = 今天所在周的周一
    final DateTime monday = JwTimetableClient.mondayOf(DateTime.now());
    final DateTime expectedStart = monday.subtract(
      Duration(days: (3 - 1) * 7 + 1),
    );

    expect(transport.weekInfoCalls, 1, reason: '启动时读一次主页面');
    expect(controller.serverCurrentWeek, 3);
    expect(controller.term.totalWeeks, 20);
    expect(controller.term.startDate, expectedStart);
    expect(controller.weekInfoError, isNull);

    // 校准后「当前周」按本应用（周日到周六）的口径重新算：
    // 教务系统周一到周日算第 3 周时，若今天已是周日，本应用看到的是下一周。
    final int expectedWeek = Term(
      startDate: expectedStart,
      totalWeeks: 20,
    ).weekOf(DateTime.now());
    expect(controller.currentWeek, expectedWeek);
    controller.dispose();
  });

  test('主页面读失败不影响课表：仅记录错误、本地推算仍可用', () async {
    final RecordingTransport transport = RecordingTransport(
      weekInfoError: const JwException('会话已失效'),
    );
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      swipeDebounce: Duration.zero,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(controller.weekInfoError, contains('会话已失效'));
    expect(controller.serverCurrentWeek, isNull);
    // 课表照常拿到，学期设置保持原样（示例学期 8/30 起、20 周）
    expect(controller.sessionsOfWeek(controller.currentWeek), isNotEmpty);
    expect(controller.term.totalWeeks, 20);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('主页面读不到时保持本地学期设置（课表页不再提供总周数）', () async {
    final RecordingTransport transport = RecordingTransport(
      weekInfoError: const JwException('主页面不可用'),
    );
    final ScheduleController controller = ScheduleController(
      transport: transport.call,
      swipeDebounce: Duration.zero,
      settings: AppSettings(
        term: Term(startDate: DateTime(2026, 8, 30), totalWeeks: 18),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(controller.serverCurrentWeek, isNull);
    // 新的课表接口（xskb_list.do）不带总周数，所以不会被改掉，
    // 仍然是设置页里那个值 —— 想改只能主页面读取成功或用户手动调。
    expect(controller.term.totalWeeks, 18);
    expect(controller.sessionsOfWeek(controller.currentWeek), isNotEmpty);
    controller.dispose();
  });
}

import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/models/classroom.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 一整天（第 1-12 节）。
const JwPeriodRange wholeDay = JwPeriodRange(start: 1, end: 12);

JwClassroom roomOf(JwClassroomBoard board, String name) =>
    board.classrooms.firstWhere((JwClassroom room) => room.name == name);

void main() {
  group('教室空余表解析', () {
    test('读出教室、节次列与容量列', () {
      final JwClassroomBoard board = JwClassroomParser.parse(
        fixtureClassroomHtml,
        fallbackWeek: 3,
        fallbackWeekday: 1,
      );

      expect(
        board.classrooms.map((JwClassroom room) => room.name),
        <String>['J1-101', 'J1-102', 'J1-103', 'J1-201'],
      );
      expect(board.week, 3);
      expect(board.weekday, 1);
      expect(
        board.periodColumns.map((JwPeriodRange item) => item.label),
        <String>['第 1-2 节', '第 3-4 节', '第 5-6 节', '第 7-8 节', '第 9-10 节', '第 11-12 节'],
      );
      // 表头里的「星期几」决定了每一列属于哪一天
      expect(roomOf(board, 'J1-101').busy.first.weekday, 1);
      // 容量这种没写星期/节次的列，按表头文字收进 extras
      expect(roomOf(board, 'J1-101').extras['容量'], '60');
      expect(roomOf(board, 'J1-103').extras['容量'], '120');
    });

    test('格子里有内容 = 有课，空格 = 空闲', () {
      final JwClassroomBoard board = JwClassroomParser.parse(
        fixtureClassroomHtml,
        fallbackWeek: 3,
        fallbackWeekday: 1,
      );

      final JwClassroom room = roomOf(board, 'J1-101');
      expect(room.busy, hasLength(2));
      expect(room.busy.first.periods, const JwPeriodRange(start: 3, end: 4));
      expect(room.busy.first.label, '高等数学');
      expect(room.busy.first.detail, '王可芸');
      expect(room.busy.last.periods, const JwPeriodRange(start: 9, end: 10));
      expect(room.busy.last.label, '大学英语');

      expect(roomOf(board, 'J1-102').isFreeAllDay, isTrue);

      // 「这一段时间空不空」按重叠判断
      expect(room.isBusyIn(const JwPeriodRange(start: 1, end: 2)), isFalse);
      expect(room.isBusyIn(const JwPeriodRange(start: 2, end: 3)), isTrue);
      expect(room.isBusyIn(wholeDay), isTrue);
      expect(board.freeIn(wholeDay).map((JwClassroom item) => item.name), <String>['J1-102']);
      expect(
        board.freeIn(const JwPeriodRange(start: 1, end: 2)).map((JwClassroom item) => item.name),
        <String>['J1-101', 'J1-102', 'J1-201'],
      );
    });

    test('读出校区与教学楼下拉选项', () {
      final JwClassroomBoard board = JwClassroomParser.parse(
        fixtureClassroomHtml,
        fallbackWeek: 3,
        fallbackWeekday: 1,
      );

      expect(
        board.campusOptions.map((JwClassroomOption item) => item.id),
        <String>['', '19'],
      );
      expect(board.campusOptions.last.name, '肇庆校区');
      expect(
        board.buildingOptions.map((JwClassroomOption item) => item.name),
        <String>['全部教学楼', '第一教学楼', '第二教学楼'],
      );
      expect(board.buildingOptions[1].id, '00001');
    });

    test('真实模板：表头用 <td> 且按时段分组时，不多出「教室/节次」这一间', () {
      // 有的学校模板表头全用 <td>：第一行是「教室/节次 + 上午/下午/晚上」，
      // 第二行才是节次 —— 旧解析会把第一行当成一间叫「教室/节次」的教室。
      const String html =
          '<table>'
          '<tr>'
          '<td rowspan="2">教室/节次</td>'
          '<td rowspan="2">容量</td>'
          '<td colspan="2">上午</td>'
          '<td colspan="2">下午</td>'
          '<td colspan="2">晚上</td>'
          '</tr>'
          '<tr>'
          '<td>第1-2节</td><td>第3-4节</td><td>第5-6节</td>'
          '<td>第7-8节</td><td>第9-10节</td><td>第11-12节</td>'
          '</tr>'
          '<tr><td>J2-301</td><td>80</td><td>数据结构<br/>赵六</td>'
          '<td></td><td></td><td></td><td></td><td></td></tr>'
          '</table>';

      final JwClassroomBoard board = JwClassroomParser.parse(
        html,
        fallbackWeek: 4,
        fallbackWeekday: 2,
      );

      // 表头行不再被当成教室
      expect(
        board.classrooms.map((JwClassroom room) => room.name),
        <String>['J2-301'],
      );
      // 时段行只是表头：6 个节次列照常读出，容量列照常收进 extras
      expect(board.periodColumns, hasLength(6));
      expect(board.periodColumns.first, const JwPeriodRange(start: 1, end: 2));
      expect(roomOf(board, 'J2-301').extras['容量'], '80');
      expect(roomOf(board, 'J2-301').busy.single.label, '数据结构');
      expect(
        roomOf(board, 'J2-301').busy.single.periods,
        const JwPeriodRange(start: 1, end: 2),
      );
    });

    test('表头没写节次时，按列顺序兜底成「一天 6 个大节」', () {
      const String html =
          '<table>'
          '<tr><td>J1-101</td><td>高等数学</td><td></td></tr>'
          '<tr><td>J1-102</td><td></td><td></td></tr>'
          '</table>';

      final JwClassroomBoard board = JwClassroomParser.parse(
        html,
        fallbackWeek: 5,
        fallbackWeekday: 3,
      );

      expect(
        board.periodColumns,
        <JwPeriodRange>[JwPeriodRange(start: 1, end: 2), JwPeriodRange(start: 3, end: 4)],
      );
      // 表头没写星期几，就用请求参数里的那一天
      expect(roomOf(board, 'J1-101').busy.single.weekday, 3);
      expect(roomOf(board, 'J1-101').busy.single.periods, const JwPeriodRange(start: 1, end: 2));
      expect(roomOf(board, 'J1-102').isFreeAllDay, isTrue);
    });

    test('会话失效 / 不是教室页面时给出可读错误', () {
      expect(
        () => JwClassroomParser.parse(
          '{"flag1":2,"msgContent":"请先登录系统"}',
          fallbackWeek: 1,
          fallbackWeekday: 1,
        ),
        throwsA(
          isA<JwException>().having(
            (JwException error) => error.message,
            'message',
            contains('请先登录系统'),
          ),
        ),
      );
      expect(
        () => JwClassroomParser.parse(
          '<html><head><title>用户登录</title></head></html>',
          fallbackWeek: 1,
          fallbackWeekday: 1,
        ),
        throwsA(
          isA<JwException>().having(
            (JwException error) => error.message,
            'message',
            contains('会话已失效'),
          ),
        ),
      );
    });
  });

  group('教室查询接口', () {
    test('表单体与教务系统页面一致', () {
      expect(
        JwTimetableClient.classroomQueryBody(
          campusId: '19',
          buildingId: '',
          week: 6,
          weekday: 2,
        ),
        'xqid=19&jzwid=&skjsid=&skjs=&zc1=6&zc2=6&skxq1=2&skxq2=2&jc1=&jc2=',
      );
    });

    test('请求打到教室查询接口，不带 Cookie 也照常发', () async {
      final RecordingTransport transport = RecordingTransport();
      final JwTimetableClient client = JwTimetableClient(
        cookie: 'JSESSIONID=abc',
        transport: transport.call,
      );

      final JwClassroomBoard board = await client.fetchClassroomBoard(
        campusId: '19',
        buildingId: '00001',
        week: 3,
        weekday: 1,
      );

      expect(transport.urls.single.path, endsWith('/kbcx/kbxx_classroom_ifr'));
      expect(transport.methods.single, 'POST');
      expect(
        transport.classroomBodies.single,
        'xqid=19&jzwid=00001&skjsid=&skjs=&zc1=3&zc2=3&skxq1=1&skxq2=1&jc1=&jc2=',
      );
      expect(transport.headers.single['X-JW-Cookie'], 'JSESSIONID=abc');
      expect(board.classrooms, hasLength(4));
    });

    test('查询失败时控制器给出可读错误', () async {
      final RecordingTransport transport = RecordingTransport(
        classroomError: const JwException('会话已失效或未登录'),
      );
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await controller.ensureClassroomBoard();

      expect(controller.classroomBoard, isNull);
      expect(controller.classroomError, contains('会话已失效或未登录'));
      controller.dispose();
    });
  });

  group('控制器里的教室查询', () {
    test('查过一次就不重复请求；换星期才会重新联网', () async {
      final RecordingTransport transport = RecordingTransport();
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await controller.ensureClassroomBoard();
      expect(controller.classroomBoard!.classrooms, hasLength(4));
      final int calls = transport.classroomBodies.length;

      await controller.ensureClassroomBoard(); // 本次会话已查过
      expect(transport.classroomBodies.length, calls);

      // 换星期：请求参数变了 → 重新联网
      await controller.updateClassroomQuery(
        controller.classroomQuery.copyWith(weekday: 5),
      );
      expect(transport.classroomBodies.length, calls + 1);
      expect(transport.classroomBodies.last, contains('skxq1=5'));

      // 换成同样的条件：不该再发请求
      await controller.updateClassroomQuery(controller.classroomQuery);
      expect(transport.classroomBodies.length, calls + 1);

      controller.dispose();
    });

    test('退出登录会清掉教室占用表', () async {
      final RecordingTransport transport = RecordingTransport();
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      await controller.ensureClassroomBoard();
      expect(controller.classroomBoard, isNotNull);

      await controller.signOut();
      expect(controller.classroomBoard, isNull);
      controller.dispose();
    });
  });
}

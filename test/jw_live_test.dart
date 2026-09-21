import 'dart:io';

import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_credentials.dart';
import 'package:class_schedule/data/jw_transport_io.dart';
import 'package:class_schedule/models/classroom.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 需要联网 + 有效会话，默认跳过。手动运行（会话用构建参数注入，仓库里不存会话）：
/// ```powershell
/// flutter test --dart-define=JW_LIVE=true --dart-define=JW_COOKIE="JSESSIONID=..." test/jw_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('JW_LIVE');

/// 跳过原因；null 表示照常跑。
String? get _skipLive {
  if (!_live) {
    return '联网测试，需要 --dart-define=JW_LIVE=true';
  }
  if (jwCookie.isEmpty) {
    return '未提供会话，需再加 --dart-define=JW_COOKIE="JSESSIONID=..."';
  }
  return null;
}

Future<int> _timeMs(Future<void> Function() body) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  await body();
  return stopwatch.elapsedMilliseconds;
}

void main() {
  test('真实访问教务系统并解析出课表', () async {
    // flutter_test 默认用假 HttpClient 拦截所有请求，这里放开走真实网络。
    HttpOverrides.global = null;

    final JwTimetableClient client = JwTimetableClient();
    final JwTimetable timetable = await client.fetchWeekByZc(4);

    debugPrint(
      '教务系统周次=${timetable.week}，解析到 ${timetable.sessions.length} 条排课：',
    );
    for (final session in timetable.sessions) {
      debugPrint(
        '  ${session.course.name} @${session.course.location} '
        '星期${session.weekday} ${session.periodsLabel} '
        '${session.weeksLabel} 老师=${session.course.teacher}',
      );
    }

    expect(timetable.sessions, isNotEmpty);
    expect(timetable.sessions.every((s) => s.course.name.isNotEmpty), isTrue);
  }, skip: _skipLive);

  test('从主页面读取当前周次（周一到周日口径）', () async {
    HttpOverrides.global = null;
    final JwTimetableClient client = JwTimetableClient();

    final JwMainPageInfo page = await client.fetchMainPage();
    final JwWeekInfo info = page.week;
    debugPrint(
      '主页面：当前第 ${info.week} 周 / 共 ${info.totalWeeks} 周'
      '（地址 ${client.mainPageEndpoint}）',
    );
    debugPrint(
      '学生信息：${page.student.name} / ${page.student.studentId} / '
      '${page.student.department ?? '-'} / ${page.student.major ?? '-'} / '
      '${page.student.className ?? '-'}',
    );

    final List<JwSelectionRound> rounds = await client.fetchSelectionRounds();
    debugPrint(
      '选课中心：${rounds.isEmpty ? '当前没有开放轮次' : '${rounds.length} 个轮次'}'
      '（地址 ${client.selectionEndpoint}）',
    );

    // 用主页面周次反推第 1 周周日，应与课表接口对得上
    final DateTime start = JwTimetableClient.mondayOf(DateTime.now())
        .subtract(Duration(days: (info.week - 1) * 7 + 1));
    debugPrint('反推第 1 周周日 = ${start.toIso8601String().substring(0, 10)}');

    final JwTimetable timetable = await client.fetchWeekByZc(info.week);
    debugPrint(
      '课表接口对 zc=${info.week} 返回：第 ${timetable.week} 周，'
      '${timetable.sessions.length} 条排课',
    );

    expect(info.week, greaterThanOrEqualTo(1));
    expect(info.totalWeeks, greaterThan(info.week - 1));
    expect(timetable.week, info.week);
  }, skip: _skipLive);

  test('真实访问教室空余查询接口并解析出教室表', () async {
    HttpOverrides.global = null;
    final JwTimetableClient client = JwTimetableClient();

    final JwMainPageInfo page = await client.fetchMainPage();
    final int week = page.week.week;

    // 先不带条件查一次：能看到校区/教学楼选项，也能看出表格长什么样。
    final JwClassroomBoard board = await client.fetchClassroomBoard(
      campusId: '19',
      buildingId: '',
      week: week,
      weekday: 1,
    );

    debugPrint(
      '教室空余查询（第 $week 周 星期一）：${board.classrooms.length} 间教室，'
      '节次列 ${board.periodColumns.map((JwPeriodRange p) => p.label).join(' / ')}',
    );
    debugPrint(
      '校区选项：${board.campusOptions.map((JwClassroomOption o) => '${o.id}=${o.name}').join('，')}',
    );
    debugPrint(
      '教学楼选项：${board.buildingOptions.map((JwClassroomOption o) => '${o.id}=${o.name}').join('，')}',
    );
    for (final JwClassroom room in board.classrooms.take(8)) {
      debugPrint(
        '  ${room.name} ${room.extras.entries.map((e) => '${e.key}=${e.value}').join(' ')} '
        '有课 ${room.busy.length} 段'
        '${room.busy.isEmpty ? '' : '（${room.busy.map((JwClassroomBusy b) => '${b.periods.label} ${b.label}').join('；')}）'}',
      );
    }

    expect(board.classrooms, isNotEmpty);
  }, skip: _skipLive);

  test('性能实测：连接复用 vs 每次重新握手', () async {
    HttpOverrides.global = null;
    final JwTimetableClient client = JwTimetableClient();

    // 冷启动：先关掉共享连接，强制重新 TCP + TLS 握手
    closeSharedClient();
    final int cold1 = await _timeMs(() async {
      await client.fetchWeekByZc(4);
    });

    // 紧接着再取下一周：复用已建立的连接
    final int warm = await _timeMs(() async {
      await client.fetchWeekByZc(5);
    });

    final int warm2 = await _timeMs(() async {
      await client.fetchWeekByZc(6);
    });

    closeSharedClient();
    final int cold2 = await _timeMs(() async {
      await client.fetchWeekByZc(7);
    });

    debugPrint(
      '性能实测（真实教务系统）：\n'
      '  冷启动（重新握手）  ${cold1}ms\n'
      '  复用连接            ${warm}ms\n'
      '  复用连接            ${warm2}ms\n'
      '  再次冷启动          ${cold2}ms',
    );

    expect(warm, greaterThan(0));
  }, skip: _skipLive);

  test('解析耗时（200 次）', () async {
    final String html = await File('test/fixtures/xskb_week4.html')
        .readAsString();

    final Stopwatch stopwatch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      JwTimetableParser.parse(html);
    }
    stopwatch.stop();
    debugPrint(
      '解析 39KB 课表 HTML：200 次共 ${stopwatch.elapsedMilliseconds}ms '
      '（约 ${(stopwatch.elapsedMicroseconds / 200).toStringAsFixed(1)}µs/次）',
    );
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });
}

import 'dart:io';

import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/models/course.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  // 真实抓取到的响应（POST xskb/xskb_list.do，zc=4），见 test/fixtures/xskb_week4.html
  final String fixture = File('test/fixtures/xskb_week4.html')
      .readAsStringSync();

  group('课表 HTML 解析', () {
    final JwTimetable timetable = JwTimetableParser.parse(fixture);

    test('解析出 10 条排课与周次', () {
      expect(timetable.sessions, hasLength(10));
      expect(timetable.week, 4); // 周次下拉里被选中的那一项
    });

    test('按星期与节次排好序', () {
      final List<CourseSession> sessions = timetable.sessions;
      for (var i = 1; i < sessions.length; i++) {
        final CourseSession previous = sessions[i - 1];
        final CourseSession current = sessions[i];
        expect(
          previous.weekday < current.weekday ||
              (previous.weekday == current.weekday &&
                  previous.startPeriod <= current.startPeriod),
          isTrue,
          reason:
              '第 $i 条顺序不对：${previous.course.name} 排到了 ${current.course.name} 前面',
        );
      }
      expect(sessions.first.course.name, '概率论与数理统计');
      expect(sessions.first.weekday, DateTime.monday);
      expect(sessions.last.course.name, 'Python程序设计');
      expect(sessions.last.weekday, DateTime.friday);
    });

    test('课名、星期、节次、地点、老师都解析正确', () {
      final CourseSession military = timetable.sessions.firstWhere(
        (CourseSession s) => s.course.name == '军事理论',
      );
      expect(military.weekday, DateTime.tuesday);
      expect(military.startPeriod, 9);
      expect(military.endPeriod, 11);
      expect(military.periodCount, 3);
      expect(military.course.location, 'J2-401');
      expect(military.course.teacher, '朱嘉婧');
      expect(military.course.hasTeacher, isTrue);
      // 这个接口不返回学分与课程属性
      expect(military.course.credits, isNull);
      expect(military.course.category, isNull);
      // 正文里的周次是区间，不是「这一周」
      expect(military.startWeek, 4);
      expect(military.endWeek, 12);

      final CourseSession algebra = timetable.sessions.firstWhere(
        (CourseSession s) => s.startPeriod == 1,
      );
      expect(algebra.course.name, '线性代数');
      expect(algebra.weekday, DateTime.wednesday);
      expect(algebra.endPeriod, 2);
      expect(algebra.course.location, 'J3-311');
      expect(algebra.course.teacher, '王可芸');
    });

    test('同一门课的多节课都算独立的排课', () {
      expect(
        timetable.sessions
            .where((CourseSession s) => s.course.name == '概率论与数理统计')
            .length,
        2,
      );
      expect(
        timetable.sessions
            .where((CourseSession s) => s.course.name == 'Python程序设计')
            .length,
        2,
      );
      expect(
        timetable.sessions
            .where((CourseSession s) => s.course.name == '线性代数')
            .length,
        2,
      );
    });

    test('多位老师原样保留，课名不被截断', () {
      final CourseSession python = timetable.sessions.firstWhere(
        (CourseSession s) => s.course.name == 'Python程序设计',
      );
      expect(python.course.teacher, '段润英,宋旭');
      expect(python.course.location, 'S5704AI全流程实验室');

      expect(
        timetable.sessions.any((CourseSession s) => s.course.name == '大学日语Ⅰ'),
        isTrue,
      );
      expect(
        timetable.sessions.any(
          (CourseSession s) => s.course.name == '中国近现代史纲要',
        ),
        isTrue,
      );
      // 页面上显示的是「概率论与数理..」这类截断文字，不该被当成课名
      expect(
        timetable.sessions.any(
          (CourseSession s) => s.course.name.contains('..'),
        ),
        isFalse,
      );
    });

    test('会话失效时接口返回 JSON，换成可读提示', () {
      expect(
        () => JwTimetableParser.parse('{"flag1":2,"msgContent":"请先登录系统"}'),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('会话已失效'),
          ),
        ),
      );
    });

    test('登录页、空内容、非课表页面都抛出可读错误', () {
      expect(
        () => JwTimetableParser.parse(
          '<html><head><title>用户登录</title></head><body>统一身份认证</body></html>',
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('会话已失效'),
          ),
        ),
      );
      expect(() => JwTimetableParser.parse(''), throwsA(isA<JwException>()));
      expect(
        () =>
            JwTimetableParser.parse('<html><body>403 Forbidden</body></html>'),
        throwsA(isA<JwException>()),
      );
    });

    test('格子里的周次读不出来时用 fallbackWeek 兜底', () {
      const String html =
          '<table id="kbtable">'
          '<tr><th>&nbsp;</th><th>星期一</th><th>星期二</th></tr>'
          '<tr><th>第一二节&nbsp;<br/>08:20-09:55</th>'
          '<td><div style="display: none;" class="kbcontent">测试课<br/>'
          "<font title='老师'>某老师</font><br/>"
          "<font title='周次(节次)'>[01-02节]</font><br/>"
          "<font title='教室'>A101</font><br/></div></td>"
          '<td>&nbsp;</td></tr></table>';
      final JwTimetable parsed = JwTimetableParser.parse(html, fallbackWeek: 7);
      expect(parsed.week, 7);
      expect(parsed.sessions, hasLength(1));
      expect(parsed.sessions.single.startWeek, 7);
      expect(parsed.sessions.single.endWeek, 7);
      expect(parsed.sessions.single.course.location, 'A101');
      expect(parsed.sessions.single.course.teacher, '某老师');
      expect(parsed.sessions.single.course.category, isNull);
      expect(parsed.sessions.single.course.credits, isNull);
    });

    test('正文没写节次时用行首的「第X节」兜底', () {
      const String html =
          '<table id="kbtable">'
          '<tr><th>&nbsp;</th><th>星期一</th></tr>'
          '<tr><th>第九十十一节&nbsp;<br/>19:00-21:25</th>'
          '<td><div class="kbcontent">晚课<br/>'
          "<font title='周次(节次)'>3-16(周)</font><br/>"
          "<font title='教室'>B203</font><br/></div></td>"
          '</tr></table>';
      final JwTimetable parsed = JwTimetableParser.parse(html, fallbackWeek: 3);
      final CourseSession session = parsed.sessions.single;
      expect(session.course.name, '晚课');
      expect(session.startPeriod, 9);
      expect(session.endPeriod, 11);
      expect(session.startWeek, 3);
      expect(session.endWeek, 16);
    });

    test('同一个格子里的多门课都会解析', () {
      const String html =
          '<table id="kbtable">'
          '<tr><th>&nbsp;</th><th>星期一</th></tr>'
          '<tr><th>第三四节</th>'
          '<td><div class="kbcontent">甲课<br/>'
          "<font title='周次(节次)'>第2周[03-04节]</font><br/>"
          "<font title='教室'>A1</font><hr/>"
          '乙课<br/>'
          "<font title='周次(节次)'>第2周[03-04节]</font><br/>"
          "<font title='教室'>A2</font></div></td>"
          '</tr></table>';
      final JwTimetable parsed = JwTimetableParser.parse(html);
      expect(parsed.sessions, hasLength(2));
      expect(
        parsed.sessions.map((CourseSession s) => s.course.name).toList(),
        <String>['甲课', '乙课'],
      );
      expect(parsed.sessions.first.weekday, DateTime.monday);
      expect(parsed.sessions.first.startPeriod, 3);
      expect(parsed.sessions.first.course.location, 'A1');
    });

    test('备注行里的课（没有节次）不进网格', () {
      const String html =
          '<table id="kbtable">'
          '<tr><th>&nbsp;</th><th>星期一</th></tr>'
          '<tr><th>备注:</th><td colspan="7">劳动教育 李灏良 8-11周;</td></tr>'
          '</table>';
      expect(JwTimetableParser.parse(html).sessions, isEmpty);
    });
  });

  group('请求参数', () {
    test('提交周次表单，并带上 Cookie 与必要请求头', () async {
      late String method;
      late Uri url;
      late String body;
      late Map<String, String> headers;
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: 'https://jw.example.edu.cn/gzasc_jsxsd/',
        cookie: 'JSESSIONID=abc; HWWAFSESID=def',
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          method = m;
          url = u;
          body = b;
          headers = h;
          return fixture;
        },
      );

      await client.fetchWeekByZc(6);

      expect(method, 'POST');
      expect(
        url.toString(),
        'https://jw.example.edu.cn/gzasc_jsxsd/xskb/xskb_list.do',
      );
      expect(body, 'jx0404id=&cj0701id=&zc=6&demo=&sfFD=1');
      // 统一用 X-JW-Cookie（浏览器禁止 JS 设置 Cookie 头），由传输层翻译
      expect(headers['X-JW-Cookie'], 'JSESSIONID=abc; HWWAFSESID=def');
      expect(headers.containsKey('Cookie'), isFalse);
      expect(
        headers['Referer'],
        'https://jw.example.edu.cn/gzasc_jsxsd/framework/main_index.jsp',
      );
      expect(headers['User-Agent'], isNotEmpty);
    });

    test('表单体里的周次跟着参数走', () {
      expect(
        JwTimetableClient.weekQueryBody(1),
        'jx0404id=&cj0701id=&zc=1&demo=&sfFD=1',
      );
      expect(
        JwTimetableClient.weekQueryBody(18),
        'jx0404id=&cj0701id=&zc=18&demo=&sfFD=1',
      );
    });

    test('周日也会换算到所在周的周一', () {
      expect(
        JwTimetableClient.mondayOf(DateTime(2026, 9, 27)),
        DateTime(2026, 9, 21),
      );
      expect(
        JwTimetableClient.mondayOf(DateTime(2026, 9, 21)),
        DateTime(2026, 9, 21),
      );
    });

    test('没有会话时照常发请求，只是不带 Cookie 头', () async {
      late Map<String, String> headers;
      final JwTimetableClient client = JwTimetableClient(
        cookie: '',
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          headers = h;
          return fixture;
        },
      );

      // 「还没登录」是正常状态，不是错误：会话可能由用户在 App 内登录后补上，
      // 也可能由 Web 网关持有，所以这里只负责把请求发出去（不冒充任何身份）。
      await client.fetchWeekByZc(4);
      expect(headers.containsKey('X-JW-Cookie'), isFalse);
    });

    test('未登录时服务端把请求打回登录页，报可读的登录提示', () async {
      final JwTimetableClient client = JwTimetableClient(
        cookie: '',
        transport: (String m, Uri u, String b, Map<String, String> h) async =>
            '<html><head><title>用户登录</title></head></html>',
      );

      await expectLater(
        client.fetchWeekByZc(4),
        throwsA(
          isA<JwException>().having(
            (JwException error) => error.message,
            'message',
            contains('请到「我的信息」页登录'),
          ),
        ),
      );
    });
  });

  group('旧课表接口（副数据源 loadkb.jsp）', () {
    test('按日期提交表单，并带上 Cookie 与必要请求头', () async {
      late String method;
      late Uri url;
      late String body;
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: 'https://jw.example.edu.cn/gzasc_jsxsd',
        cookie: 'JSESSIONID=abc',
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          method = m;
          url = u;
          body = b;
          return fixtureLoadkbHtml;
        },
      );

      await client.fetchWeekByLoadkb(DateTime(2026, 9, 21));

      expect(method, 'POST');
      expect(
        url.toString(),
        'https://jw.example.edu.cn/gzasc_jsxsd/framework/main_index_loadkb.jsp',
      );
      // 页面脚本提交的就是 {rq: 日期, sjmsValue: 时间模式(空)}。
      expect(body, 'rq=2026-09-21&sjmsValue=');
    });

    test('表单体里的日期跟着参数走', () {
      expect(
        JwTimetableClient.loadkbQueryBody(DateTime(2026, 8, 30)),
        'rq=2026-08-30&sjmsValue=',
      );
      expect(
        JwTimetableClient.loadkbQueryBody(DateTime(2026, 9, 5)),
        'rq=2026-09-05&sjmsValue=',
      );
    });

    test('解析真实响应：学分、课程属性、节次与周次（结构与新接口完全不同）', () {
      // 用真实抓取的响应（2026-09-21，rq=2026-09-21 → 教务第 4 周）。
      final JwTimetable timetable = JwLoadkbParser.parse(fixtureLoadkbHtml);

      // 夹具里 10 门课；周次来自 li_showWeek（第4周），不在夹具里时不炸。
      expect(timetable.week, 4);
      expect(timetable.sessions, hasLength(10));

      // 线性代数 周一 5-6 节：学分/属性来自 title 字段。
      final CourseSession linear = timetable.sessions
          .singleWhere((CourseSession s) => s.weekday == DateTime.monday &&
              s.startPeriod == 5);
      expect(linear.course.name, '线性代数');
      expect(linear.course.credits, '3');
      expect(linear.course.category, '必修');
      expect(linear.course.location, 'J1-507');
      // 旧接口格子里没有老师。
      expect(linear.course.hasTeacher, isFalse);
      expect(linear.startPeriod, 5);
      expect(linear.endPeriod, 6);
      expect(linear.startWeek, 4);
      expect(linear.endWeek, 4);

      // 三节连堂的节次区间 (09,10,11小节) → 9-11。
      final CourseSession military = timetable.sessions
          .singleWhere((CourseSession s) => s.course.name == '军事理论');
      expect(military.weekday, DateTime.tuesday);
      expect(military.startPeriod, 9);
      expect(military.endPeriod, 11);

      // 全名来自 title 的「课程名称：」，不是被截断的显示文本「概率论与数理..」。
      expect(
        timetable.sessions
            .where((CourseSession s) => s.course.name == '概率论与数理统计')
            .length,
        2,
      );
    });

    test('响应不是 tab1 表格（会话失效返回 JSON）时抛可读错误', () {
      expect(
        () => JwLoadkbParser.parse('{"flag1":2,"msgContent":"请先登录系统"}'),
        throwsA(
          isA<JwException>().having(
            (JwException error) => error.message,
            'message',
            contains('请先登录系统'),
          ),
        ),
      );
    });
  });
}

import 'package:flutter/foundation.dart';

import '../models/classroom.dart';
import '../models/course.dart';
import 'jw_credentials.dart';
import 'jw_exception.dart';
import 'jw_http.dart';
import 'jw_login.dart';
import 'jw_transport_stub.dart'
    if (dart.library.io) 'jw_transport_io.dart'
    if (dart.library.js_interop) 'jw_transport_web.dart'
    as net;

/// 发送一次 HTTP 请求并返回响应文本。抽成函数类型是为了测试时可替换。
typedef JwTransport = Future<String> Function(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
);

/// 一次周课表查询的结果。
@immutable
class JwTimetable {
  const JwTimetable({required this.week, required this.sessions});

  /// 教务系统给出的周次；页面里没有周次信息时为 null。
  final int? week;

  /// 该周的排课。
  final List<CourseSession> sessions;

  /// 是否没有任何课程。
  bool get isEmpty => sessions.isEmpty;
}

/// 教务系统主页面给出的周次信息。
@immutable
class JwWeekInfo {
  const JwWeekInfo({required this.week, required this.totalWeeks});

  /// 教务系统认为「现在是第几周」。
  ///
  /// 注意口径：教务系统按**周一到周日**分周，所以周日的「当前周」是它所在周的上一周
  /// （例如 9/20 周日属于 9/14 那一周）。本应用的周次按设计稿从**周日到周六**，
  /// 两者对周一到周六是同一个周次编号，周日会差 1 —— 校准学期起止用的就是这个值。
  final int week;

  /// 学期总周数。
  final int totalWeeks;
}

/// 学生基本信息（来自教务系统主页面，和当前周次同一个响应）。
@immutable
class JwStudentInfo {
  const JwStudentInfo({
    required this.name,
    required this.studentId,
    this.department,
    this.major,
    this.className,
  });

  /// 姓名。
  final String name;

  /// 学号（主页面写的是「学生编号」）。
  final String studentId;

  /// 所属院系。
  final String? department;

  /// 专业名称。
  final String? major;

  /// 班级名称。
  final String? className;

  /// 是否什么都没解析到。
  bool get isEmpty => name.isEmpty && studentId.isEmpty;
}

/// 一条选课轮次（学生选课中心 `xsxk/xklc_list`）。
@immutable
class JwSelectionRound {
  const JwSelectionRound({
    required this.term,
    required this.name,
    required this.timeRange,
    this.roundId,
  });

  /// 学年学期，例如「2026-2027-1」。
  final String term;

  /// 选课名称。
  final String name;

  /// 选课时间，例如「2026-09-20 08:00 ~ 2026-09-25 23:59」。
  final String timeRange;

  /// 轮次 id（页面 JS 里的 `jx0502zbid`），用于在教务系统里进入该轮次。
  final String? roundId;
}

/// 正方教务系统（`jsxsd`）客户端。
///
/// 实测（2026-09）：
/// * `POST xskb/xskb_list.do`，表单 `jx0404id=&cj0701id=&zc=<周次>&demo=&sfFD=1` → 课表 HTML；
/// * `GET framework/xsMain_new_*.jsp?t1=1` → 当前周次、总周数、学生信息；
/// * `GET xsxk/xklc_list` → 学生选课中心的轮次列表；
/// * `GET verifycode.servlet` + `POST xk/LoginToXk` → 用学号密码登录，换一份会话。
class JwTimetableClient {
  JwTimetableClient({
    String? baseUrl,
    String? cookie,
    JwTransport? transport,
    JwDetailedTransport? detailedTransport,
  }) : baseUrl = _trimTrailingSlash(baseUrl ?? jwBaseUrl),
       cookie = cookie ?? jwCookie,
       _transport = transport ?? net.sendRequest,
       _detailed = detailedTransport ?? net.sendDetailed;

  /// 教务系统根地址，例如 `https://jw.educationgroup.cn/gzasc_jsxsd`。
  final String baseUrl;

  /// 登录会话 Cookie。
  ///
  /// 不是 final：登录成功后会被换成新会话（见 [login]），此后同一个客户端的所有
  /// 请求都用新会话。
  String cookie;

  final JwTransport _transport;

  /// 需要读响应头/原始字节的请求走这条通道（登录流程）。
  final JwDetailedTransport _detailed;

  /// 浏览器 UA：WAF 对空 UA 会直接拒绝。
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 课表接口地址。
  ///
  /// 取的是「学期理论课表」页面自己提交的地址：它按**周次**（`zc`）筛选，
  /// 比旧的 `framework/main_index_loadkb.jsp`（要传该周周一的日期）直接。
  Uri get endpoint => Uri.parse('$baseUrl/xskb/xskb_list.do');

  /// 主页面地址：用来读「当前第几周 / 总周数 / 学生信息」。
  Uri get mainPageEndpoint => Uri.parse('$baseUrl$jwMainPagePath');

  /// 学生选课中心（选课轮次列表）。
  Uri get selectionEndpoint => Uri.parse('$baseUrl$jwSelectionPath');

  /// 教室空余查询。
  Uri get classroomEndpoint => Uri.parse('$baseUrl$jwClassroomPath');

  /// 登录验证码图片（80×40 JPEG）。
  Uri get captchaEndpoint => Uri.parse('$baseUrl/verifycode.servlet');

  /// 登录提交地址。`xk/LoginToXk` 是选课中心的登录入口，主页面的登录也走它。
  Uri get loginEndpoint => Uri.parse('$baseUrl/xk/LoginToXk');

  /// 是否已配置会话 Cookie。
  ///
  /// 可能为空的两种正常情况：
  /// * 还没登录（新装的 App）——用户去「我的信息」页登录即可；
  /// * Web 端把会话交给**同源网关**持有（`flutter build web --dart-define=JW_COOKIE=`），
  ///   由 `dart run tool/jw_proxy.dart --cookie="..."` 在网关侧补上。
  bool get hasCookie => cookie.trim().isNotEmpty;

  /// 读取主页面：当前第几周、总周数、学生信息。
  ///
  /// 这是确定当前周次的**权威来源**：不依赖本地推算的开学日期。
  Future<JwMainPageInfo> fetchMainPage() async {
    final String html = await _transport(
      'GET',
      mainPageEndpoint,
      '',
      <String, String>{
        if (hasCookie) 'X-JW-Cookie': cookie.trim(),
        'User-Agent': defaultUserAgent,
        'Referer': '$baseUrl/framework/main_index.jsp',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    return JwMainPageParser.parse(html);
  }

  /// 读取学生选课中心的轮次列表（只读）。
  Future<List<JwSelectionRound>> fetchSelectionRounds() async {
    final String html = await _transport(
      'GET',
      selectionEndpoint,
      '',
      <String, String>{
        if (hasCookie) 'X-JW-Cookie': cookie.trim(),
        'User-Agent': defaultUserAgent,
        'Referer': '$baseUrl/framework/xsMain_new_13657.jsp?t1=1',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    return JwSelectionParser.parse(html);
  }

  /// 教室空余查询的表单体。
  ///
  /// 教务系统页面上提交的就是这些字段：
  /// * `xqid` 校区、`jzwid` 教学楼（都可以为空 = 不限）；
  /// * `zc1`/`zc2` 周次范围（这里两端都填同一个周次 = 只看这一周）；
  /// * `skxq1`/`skxq2` 星期范围（同上，两端同一个 = 只看这一天）；
  /// * `skjsid`/`skjs` 上课教师（本应用不用，留空）；
  /// * `jc1`/`jc2` 节次范围，**留空 = 全天**（本应用固定全天，节次筛选在本地做，
  ///   这样切换「只看第几节」不用重新联网）。
  static String classroomQueryBody({
    required String campusId,
    required String buildingId,
    required int week,
    required int weekday,
  }) {
    final String campus = Uri.encodeQueryComponent(campusId);
    final String building = Uri.encodeQueryComponent(buildingId);
    return 'xqid=$campus&jzwid=$building&skjsid=&skjs='
        '&zc1=$week&zc2=$week&skxq1=$weekday&skxq2=$weekday&jc1=&jc2=';
  }

  /// 查询教室空余情况（只读，不预约任何教室）。
  Future<JwClassroomBoard> fetchClassroomBoard({
    String campusId = '',
    String buildingId = '',
    required int week,
    required int weekday,
  }) async {
    final String html = await _transport(
      'POST',
      classroomEndpoint,
      classroomQueryBody(
        campusId: campusId,
        buildingId: buildingId,
        week: week,
        weekday: weekday,
      ),
      <String, String>{
        if (hasCookie) 'X-JW-Cookie': cookie.trim(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': defaultUserAgent,
        'Referer': '$baseUrl$jwClassroomPath',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    return JwClassroomParser.parse(
      html,
      fallbackWeek: week,
      fallbackWeekday: weekday,
    );
  }

  /// 课表接口的表单体。[week] 是周次。
  ///
  /// 另外三个字段教务系统页面提交的就是空值 ——
  /// `jx0404id`/`cj0701id` 是「点某门课进去看详情」时的课程 id，`demo` 是模板开关。
  static String weekQueryBody(int week) =>
      'jx0404id=&cj0701id=&zc=$week&demo=&sfFD=1';

  /// 拉取第 [week] 周的课表。
  ///
  /// 教务系统按 `zc` 只返回**该周有课**的排课，所以这里不需要先算日期，
  /// 也就不依赖本地推算的开学日期 —— 周次对不上也不会取错周。
  Future<JwTimetable> fetchWeekByZc(int week) async {
    final String html = await _transport(
      'POST',
      endpoint,
      weekQueryBody(week),
      <String, String>{
        // 统一用 X-JW-Cookie 传会话：浏览器不允许 JS 设置 Cookie 头，
        // 由各平台传输层负责翻译成真正的 Cookie（见 jw_transport_*.dart）。
        if (hasCookie) 'X-JW-Cookie': cookie.trim(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': defaultUserAgent,
        'Referer': '$baseUrl/framework/main_index.jsp',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'X-Requested-With': 'XMLHttpRequest',
      },
    );

    return JwTimetableParser.parse(html, fallbackWeek: week);
  }

  /// 旧课表接口地址：`framework/main_index_loadkb.jsp`，按**日期**（`rq`）取课。
  ///
  /// 现在是**副数据源**：新接口 `xskb_list.do` 比它多了老师、少了学分与课程属性，
  /// 所以只拿它来补课程详情弹窗里的附加信息，课表本身仍以新接口为准。
  Uri get loadkbEndpoint =>
      Uri.parse('$baseUrl/framework/main_index_loadkb.jsp');

  /// 旧课表接口的表单体。[date] 是该周任意一天的日期（教务按周一到周日分周，
  /// 传该周的星期一最稳）。
  ///
  /// `sjmsValue` 是主页面上「时间模式」下拉的值（正常课表就是空串），
  /// 页面脚本 `$("#kbLoading").load("/…/main_index_loadkb.jsp", {rq: rq, sjmsValue: sjmsValue})`
  /// 提交的就是这两个字段。
  static String loadkbQueryBody(DateTime date) {
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return 'rq=${date.year}-$mm-$dd&sjmsValue=';
  }

  /// 拉取 [date] 所在周的课表（旧接口，副数据源，只用来补附加信息）。
  ///
  /// 返回结构与新接口一致，但格子里**没有老师**、**有学分与课程属性**
  /// （解析见 [JwLoadkbParser]，响应结构与新课表完全不同，别混用）。
  Future<JwTimetable> fetchWeekByLoadkb(DateTime date) async {
    final String html = await _transport(
      'POST',
      loadkbEndpoint,
      loadkbQueryBody(date),
      <String, String>{
        if (hasCookie) 'X-JW-Cookie': cookie.trim(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': defaultUserAgent,
        'Referer': '$baseUrl/framework/main_index.jsp',
        'Origin': baseUrl,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'X-Requested-With': 'XMLHttpRequest',
      },
    );

    return JwLoadkbParser.parse(html);
  }

  /// 开始登录：拉一张验证码。失败或想换一张时重新调用即可。
  ///
  /// 返回的会话对象**一次有效**：验证码是消耗品，提交失败后必须重新取。
  Future<JwLoginSession> beginLogin() => JwLoginSession.begin(
    transport: _detailed,
    captchaUrl: captchaEndpoint,
    loginUrl: loginEndpoint,
    userAgent: defaultUserAgent,
  );

  /// 用 [session] 提交账号密码与验证码；成功后替换 [cookie] 并返回主页面信息。
  ///
  /// **成功与否不看登录接口的响应体**：它可能被跳转到索引页，也可能被 WAF 改写，
  /// 唯一可靠的判据是「拿着新会话读主页面能不能读通」。所以这里顺手把主页面读掉 ——
  /// 它本来就是登录后马上要显示的东西（学生信息 + 当前周次），不算白跑一次请求。
  ///
  /// 失败时抛出的 [JwException] 优先用登录页写明的原因（例如「验证码错误!!」）。
  Future<JwMainPageInfo> login(
    JwLoginSession session, {
    required String account,
    required String password,
    required String captcha,
  }) async {
    final JwLoginAttempt attempt = await session.submit(
      account: account,
      password: password,
      captcha: captcha,
    );

    final String previous = cookie;
    final String next = attempt.cookie.trim().isEmpty
        ? previous
        : attempt.cookie;
    if (next.trim().isEmpty) {
      throw JwException(attempt.errorMessage ?? '登录没有拿到会话 Cookie，教务系统可能已改版');
    }

    cookie = next;
    try {
      return await fetchMainPage();
    } on JwException catch (error) {
      final String? reported = attempt.errorMessage;
      if (reported != null) {
        cookie = previous; // 登录页明确报了错，说明会话没变，恢复原样
        throw JwException(reported);
      }
      // 没报错却读不通：登录很可能已经成功，保留新会话，只说明读不到主页面。
      throw JwException('已提交登录，但读取教务系统主页面失败：${error.message}');
    }
  }

  /// [day] 所在周的周一。
  ///
  /// 课表接口已经改成按周次取数，这里只剩「用教务系统的当前周次反推学期起点」
  /// 这一处还在用（见 `ScheduleController._adoptMainPage`）。
  static DateTime mondayOf(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(days: day.weekday - 1));

  static String _trimTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// 主页面一次能拿到的全部信息。
@immutable
class JwMainPageInfo {
  const JwMainPageInfo({required this.week, required this.student});

  final JwWeekInfo week;
  final JwStudentInfo student;
}

/// 解析主页面上的周次。
///
/// 主页面 `xsMain_new_*.jsp` 靠 `#li_showWeek` 显示「第 N 周/20 周」：
/// `<div id="li_showWeek">…<span>第3周</span>/20周</div>`，
/// 这里的 N 是**教务系统认为的当前周**（按周一到周日）。
///
/// 课表页（`xskb/xskb_list.do`）不带总周数 —— 它只有一个 1~30 的周次下拉，
/// 那是「能选的范围」而不是「学期长度」。所以总周数只认主页面这一个来源。
abstract final class JwWeekInfoParser {
  /// 主页面里的 `<div id="li_showWeek">…</div>`。
  static final RegExp _divPattern = RegExp(
    'id\\s*=\\s*["\']li_showWeek["\'][^>]*>(.*?)</div>',
    dotAll: true,
    caseSensitive: false,
  );

  /// `$("#li_showWeek").html("…")` 形式（有些模板用脚本赋值）。
  static final RegExp _jsPattern = RegExp(
    'li_showWeek["\']\\s*\\)\\s*\\.html\\(\\s*["\'](.*?)["\']\\s*\\)',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _weekPattern = RegExp('第\\s*(\\d+)\\s*周');
  static final RegExp _totalPattern = RegExp('/\\s*(\\d+)\\s*周');

  /// 解析主页面，拿到「当前第几周 + 总周数」。
  ///
  /// 解析不到（例如会话失效返回登录页）时抛 [JwException]。
  static JwWeekInfo parseMainPage(String html) {
    final String fragment = _showWeekFragment(html) ?? html;
    final int? week = _intOrNull(_weekPattern.firstMatch(fragment)?.group(1));
    if (week == null) {
      throw JwException(JwTimetableParser._diagnose(html));
    }
    return JwWeekInfo(
      week: week,
      totalWeeks:
          _intOrNull(_totalPattern.firstMatch(fragment)?.group(1)) ?? 20,
    );
  }

  /// `#li_showWeek` 里显示的那段文本（先找 div，再找 jQuery 赋值）。
  static String? _showWeekFragment(String html) =>
      _divPattern.firstMatch(html)?.group(1) ??
      _jsPattern.firstMatch(html)?.group(1);

  static int? _intOrNull(String? value) =>
      value == null ? null : int.tryParse(value);
}

/// 解析主页面上的周次 + 学生信息。
abstract final class JwMainPageParser {
  /// 解析主页面；周次解析失败时抛 [JwException]。
  static JwMainPageInfo parse(String html) => JwMainPageInfo(
    week: JwWeekInfoParser.parseMainPage(html),
    student: JwStudentInfoParser.parse(html),
  );
}

/// 解析主页面上的学生信息。
///
/// 页面结构（实测）：
/// ```html
/// <div><div class="f14 blue middletopdwxxtit">学生姓名：</div><div class="middletopdwxxcont">张三</div></div>
/// ```
abstract final class JwStudentInfoParser {
  static const List<String> _nameLabels = <String>['学生姓名', '姓名'];
  static const List<String> _idLabels = <String>['学生编号', '学号'];
  static const List<String> _departmentLabels = <String>[
    '所属院系',
    '院系',
    '所在学院',
    '学院',
  ];
  static const List<String> _majorLabels = <String>['专业名称', '专业'];
  static const List<String> _classLabels = <String>['班级名称', '班级'];

  /// 解析学生信息；没有这些字段时返回空对象（不抛异常）。
  static JwStudentInfo parse(String html) => JwStudentInfo(
    name: _first(html, _nameLabels) ?? '',
    studentId: _first(html, _idLabels) ?? '',
    department: _first(html, _departmentLabels),
    major: _first(html, _majorLabels),
    className: _first(html, _classLabels),
  );

  /// 形如 `学生姓名：</div><div class="…">张三</div>`，取标签后面那个 div 的文本。
  static String? _valueOf(String html, String label) {
    final RegExp pattern = RegExp(
      '$label\\s*[：:]\\s*</div>\\s*<div[^>]*>\\s*([^<]*)',
      caseSensitive: false,
    );
    final String? raw = pattern.firstMatch(html)?.group(1);
    if (raw == null) {
      return null;
    }
    final String value = JwStudentInfoParser._clean(raw);
    return value.isEmpty ? null : value;
  }

  static String? _first(String html, List<String> labels) {
    for (final String label in labels) {
      final String? value = _valueOf(html, label);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static String _clean(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

/// 解析学生选课中心（`xsxk/xklc_list`）的轮次列表。
///
/// 表格结构（实测）：
/// ```html
/// <table id="tbKxkc" …>
///   <tr><th>学年学期</th><th>选课名称</th><th>选课时间</th><th>操作</th></tr>
///   <tr><td colspan="4">未查询到数据</td></tr>   <!-- 没有开放轮次时 -->
/// ```
/// 有轮次时每行是 `<td>` 单元格，操作列里带 `jrxk('轮次id')` 或 `comeInXkIndx('轮次id')`。
abstract final class JwSelectionParser {
  static final RegExp _tablePattern = RegExp(
    '<table[^>]*id\\s*=\\s*["\']tbKxkc["\'][^>]*>(.*?)</table>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _rowPattern = RegExp(
    '<tr[^>]*>(.*?)</tr>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _cellPattern = RegExp(
    '<td[^>]*>(.*?)</td>',
    dotAll: true,
    caseSensitive: false,
  );
  static final RegExp _roundIdPattern = RegExp(
    '(?:jrxk|comeInXkIndx|comeInXk)\\s*\\(\\s*["\']?([A-Za-z0-9_-]+)',
  );
  static final RegExp _tagPattern = RegExp(r'<[^>]*>');

  /// 解析轮次列表；没有轮次（页面显示「未查询到数据」）时返回空列表。
  static List<JwSelectionRound> parse(String html) {
    final RegExpMatch? table = _tablePattern.firstMatch(html);
    if (table == null) {
      // 不是选课页面（例如会话失效）时给出可读错误
      throw JwException(JwTimetableParser._diagnose(html));
    }

    final List<JwSelectionRound> rounds = <JwSelectionRound>[];
    for (final RegExpMatch row in _rowPattern.allMatches(table.group(1)!)) {
      final String rowHtml = row.group(1)!;
      if (rowHtml.contains('<th')) {
        continue; // 表头
      }
      final List<String> cells = _cellPattern
          .allMatches(rowHtml)
          .map((RegExpMatch cell) => _text(cell.group(1)!))
          .toList();
      if (cells.isEmpty || cells.first.contains('未查询到数据')) {
        continue;
      }
      rounds.add(
        JwSelectionRound(
          term: cells.isNotEmpty ? cells[0] : '',
          name: cells.length > 1 ? cells[1] : '',
          timeRange: cells.length > 2 ? cells[2] : '',
          roundId: _roundIdPattern.firstMatch(rowHtml)?.group(1),
        ),
      );
    }
    return rounds;
  }

  static String _text(String html) => html
      .replaceAll(_tagPattern, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}

/// 解析 `xskb/xskb_list.do` 返回的课表 HTML（「学期理论课表」）。
///
/// 实测页面结构（强智 jsxsd 的经典 `kbtable`）：
/// ```html
/// <table id="kbtable" …>
///   <tr><th>&nbsp;</th><th>星期一</th>…<th>星期日</th></tr>   <!-- 表头：没有 <td> -->
///   <tr>
///     <th>第一二节 08:20-09:55</th>                            <!-- 行首写明节次 -->
///     <td>…<div id="HASH-1-2" style="display: none;" class="kbcontent"
///          >线性代数<br/><font title='老师'>王可芸</font><br/>
///           <font title='周次(节次)'>4-18(周)[01-02节]</font><br/>
///           <font title='教室'>J3-311</font><br/></div>…</td>
///     …                                                        <!-- 7 个 <td> -->
///   </tr>
///   …
///   <tr><th>备注:</th><td colspan="7">劳动教育 李灏良 8-11周;</td></tr>
/// </table>
/// ```
///
/// 四个坑：
/// 1. 每个格子里有**两个**课程 div：`class="kbcontent1"` 是页面上显示的精简版
///    （没有老师、没有节次），`class="kbcontent"` 才是完整版；后面还跟着一堆
///    `class="kbcontent sykb2"` 的空 div（切换「实验课表」用）。只认完整版且非空的。
/// 2. 星期几由 `<td>` 的**位置**决定（第一个就是星期一），不看 div 的 id。
/// 3. 正文里的周次是 `4-18(周)`（一格课横跨多周），节次是 `[01-02节]`；
///    本应用按周渲染，筛选交给调用方。
/// 4. 备注行里的课没有星期/节次，落不到网格上，直接忽略。
///
/// 与旧接口（`main_index_loadkb.jsp`）相比多了**老师**，少了学分与课程属性。
abstract final class JwTimetableParser {
  /// 课表表格本体。
  static final RegExp _tablePattern = RegExp(
    '<table[^>]*\\bid\\s*=\\s*[\'"]kbtable[\'"][^>]*>(.*?)</table>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _rowPattern = RegExp(
    '<tr[^>]*>(.*?)</tr>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 行首单元格（节次标签）。
  static final RegExp _headerPattern = RegExp(
    '<th[^>]*>(.*?)</th>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 一行里的星期格子，顺序就是星期一到星期日。
  static final RegExp _cellPattern = RegExp(
    '<td[^>]*>(.*?)</td>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 完整版课程 div（`class="kbcontent"`，不含 `kbcontent1` / `kbcontent sykb2`）。
  static final RegExp _fullCellPattern = RegExp(
    '<div\\b[^>]*\\bclass\\s*=\\s*[\'"]kbcontent[\'"][^>]*>(.*?)</div>',
    dotAll: true,
    caseSensitive: false,
  );

  /// `<font title='老师'>王可芸</font>`：字段名在标题里，值在正文里。
  static final RegExp _fontPattern = RegExp(
    '<font[^>]*\\btitle\\s*=\\s*[\'"]([^\'"]*)[\'"][^>]*>(.*?)</font>',
    dotAll: true,
    caseSensitive: false,
  );

  /// `[01-02节]`；也可能是 `[09-10-11节]`。
  static final RegExp _periodPattern = RegExp(r'\[\s*(\d+(?:-\d+)*)\s*节\s*\]');

  /// `4-18(周)` / `5(周)` / `4-18(单周)`。
  static final RegExp _weekRangePattern = RegExp(
    r'(\d+)\s*(?:-\s*(\d+))?\s*\(?\s*(?:单|双)?\s*周\s*\)?',
  );

  /// 被选中的周次下拉项，例如 `<option value="6"  selected="selected">`。
  static final RegExp _selectedWeekPattern = RegExp(
    'value\\s*=\\s*[\'"](\\d+)[\'"][^>]*\\bselected',
    caseSensitive: false,
  );

  static final RegExp _weekdayHeaderPattern = RegExp('星期[一二三四五六日天]');
  static final RegExp _breakPattern = RegExp(
    r'<br\s*/?>',
    caseSensitive: false,
  );
  static final RegExp _rulePattern = RegExp(r'<hr[^>]*>', caseSensitive: false);
  static final RegExp _tagPattern = RegExp(r'<[^>]*>');
  static final RegExp _spacePattern = RegExp(r'\s+');
  static final RegExp _entityPattern = RegExp(r'&#(\d+);');

  /// 会话失效时接口返回的 JSON 包装：`{"flag1":2,"msgContent":"请先登录系统"}`。
  static final RegExp _jsonPattern = RegExp(r'"flag1"\s*:');
  static final RegExp _messagePattern = RegExp(r'"msgContent"\s*:\s*"([^"]*)"');

  static final RegExp _loginPattern = RegExp(
    '用户登录|请先登录|重新登录|统一身份认证|login',
    caseSensitive: false,
  );

  /// 一个格里可能是多门课（用 `<hr>` 隔开），也可能是空的。
  static const Map<String, int> _digits = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  /// 解析课表 HTML。[fallbackWeek] 是周次下拉里读不出周次时的兜底。
  static JwTimetable parse(String html, {int? fallbackWeek}) {
    final RegExpMatch? table = _tablePattern.firstMatch(html);
    if (table == null) {
      throw JwException(_diagnose(html));
    }

    final int? requested = _selectedWeek(html);
    final int fallback = requested ?? fallbackWeek ?? 1;
    final List<CourseSession> sessions = <CourseSession>[];

    for (final RegExpMatch row in _rowPattern.allMatches(table.group(1)!)) {
      final String rowHtml = row.group(1)!;
      final String headerText = _plain(
        _headerPattern.firstMatch(rowHtml)?.group(1) ?? '',
      );
      if (_weekdayHeaderPattern.hasMatch(headerText)) {
        continue; // 星期的表头行
      }
      if (headerText.contains('备注')) {
        continue; // 备注里的课没有节次，画不到网格上
      }

      // 行首写的是「第一二节 08:20-09:55」，作为节次的兜底。
      final (int, int)? rowPeriods = _periodsOfLabel(headerText);
      final List<RegExpMatch> cells = _cellPattern.allMatches(rowHtml).toList();
      for (var index = 0; index < cells.length; index++) {
        // 第一个 <td> 是星期一，依次往后；第 8 个起不是星期（不该出现）。
        if (index >= 7) {
          break;
        }
        final int weekday = index + 1;
        for (final RegExpMatch block in _fullCellPattern.allMatches(
          cells[index].group(1)!,
        )) {
          for (final String piece in block.group(1)!.split(_rulePattern)) {
            final CourseSession? session = _parseCourse(
              piece,
              weekday: weekday,
              rowPeriods: rowPeriods,
              fallbackWeek: fallback,
            );
            if (session != null) {
              sessions.add(session);
            }
          }
        }
      }
    }

    sessions.sort((CourseSession a, CourseSession b) {
      final int byDay = a.weekday.compareTo(b.weekday);
      return byDay != 0 ? byDay : a.startPeriod.compareTo(b.startPeriod);
    });

    return JwTimetable(week: requested ?? fallbackWeek, sessions: sessions);
  }

  /// 解析一个课程格子；不是课程（空格子）或缺少节次时返回 null。
  static CourseSession? _parseCourse(
    String html, {
    required int weekday,
    required (int, int)? rowPeriods,
    required int fallbackWeek,
  }) {
    final String name = _plain(html.split(_breakPattern).first);
    if (name.isEmpty) {
      return null;
    }

    final Map<String, String> fields = _fontFields(html);
    String? weekField;
    for (final MapEntry<String, String> entry in fields.entries) {
      if (entry.key.contains('周次')) {
        weekField = entry.value;
        break;
      }
    }

    final (int, int)? periods = _periodsOf(weekField ?? '') ?? rowPeriods;
    if (periods == null) {
      return null; // 没有节次就落不到网格上
    }

    final (int, int) weeks = _weeksOf(weekField, fallbackWeek);
    return CourseSession(
      course: Course(
        name: name,
        location: fields['教室'] ?? '',
        teacher: fields['老师'] ?? '',
        // 新接口不返回学分与课程属性（旧接口 `main_index_loadkb.jsp` 有，
        // 由 ScheduleController.loadEnrichedSession 走旧接口补齐）。
        // 学分字段两种标题写法都认：新接口时代的「课程学分」与旧接口的「学分」。
        credits: _emptyToNull(fields['课程学分'] ?? fields['学分']),
        category: _emptyToNull(fields['课程属性']),
      ),
      weekday: weekday,
      startPeriod: periods.$1,
      endPeriod: periods.$2,
      startWeek: weeks.$1,
      endWeek: weeks.$2,
    );
  }

  /// 取格子正文里所有带标题的字段（老师 / 周次(节次) / 教室）。
  static Map<String, String> _fontFields(String html) {
    final Map<String, String> fields = <String, String>{};
    for (final RegExpMatch match in _fontPattern.allMatches(html)) {
      final String key = _plain(match.group(1)!);
      if (key.isEmpty) {
        continue;
      }
      fields[key] = _plain(match.group(2)!);
    }
    return fields;
  }

  /// 从 `[01-02节]` 里取节次范围；没有就返回 null。
  static (int, int)? _periodsOf(String field) {
    final RegExpMatch? match = _periodPattern.firstMatch(field);
    if (match == null) {
      return null;
    }
    final List<int> periods = match
        .group(1)!
        .split('-')
        .map(int.parse)
        .toList();
    if (periods.isEmpty) {
      return null;
    }
    final int start = periods.first;
    final int end = periods.last;
    return start <= end ? (start, end) : (end, start);
  }

  /// 从行首的「第一二节」这类标签里取节次范围（正文里没写节次时的兜底）。
  static (int, int)? _periodsOfLabel(String label) {
    final int start = label.indexOf('第');
    if (start < 0) {
      return null;
    }
    final int end = label.indexOf('节', start);
    if (end <= start) {
      return null;
    }

    final List<int> periods = <int>[];
    final String text = label.substring(start + 1, end);
    for (var i = 0; i < text.length; i++) {
      final String char = text[i];
      if (char == '十') {
        // 「十一」是 11，「十」单独出现是 10
        if (i + 1 < text.length && text[i + 1] == '一') {
          periods.add(11);
          i += 1;
        } else {
          periods.add(10);
        }
      } else if (_digits.containsKey(char)) {
        periods.add(_digits[char]!);
      }
    }

    if (periods.isEmpty) {
      return null;
    }
    return (periods.first, periods.last);
  }

  /// 从 `4-18(周)` 这类写法里取周次范围；读不出就用 [fallback]。
  ///
  /// 单双周（`4-18(单周)`）只取两端的数字，不记单双 —— 调用方会按请求的周次兜底，
  /// 所以不会出现「明明有课却被判成本周不上」。
  static (int, int) _weeksOf(String? field, int fallback) {
    final RegExpMatch? match = _weekRangePattern.firstMatch(field ?? '');
    if (match == null) {
      return (fallback, fallback);
    }
    final int first = int.parse(match.group(1)!);
    final int last = match.group(2) == null
        ? first
        : int.parse(match.group(2)!);
    return first <= last ? (first, last) : (last, first);
  }

  /// 周次下拉里被选中的那一项（教务系统对「你问的是第几周」的确认）。
  static int? _selectedWeek(String html) {
    final String? value = _selectedWeekPattern.firstMatch(html)?.group(1);
    return value == null ? null : int.tryParse(value);
  }

  static String? _emptyToNull(String? value) {
    final String trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 去标签、还原实体、收拢空白。
  static String _plain(String html) => html
      .replaceAll(_tagPattern, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAllMapped(
        _entityPattern,
        (Match match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAll(_spacePattern, ' ')
      .trim();

  /// 把「这个响应为什么读不出东西」讲成人话。
  ///
  /// [what] 是期望的页面类型，只用来拼最后那句兜底文案（课表页 / 教室空余表…）。
  static String _diagnose(String html, {String what = '课表页面'}) {
    final String trimmed = html.trim();
    // 会话失效时这个接口返回的是 JSON 而不是页面。
    if (_jsonPattern.hasMatch(trimmed)) {
      final String? reason = _messagePattern.firstMatch(trimmed)?.group(1);
      final String detail = (reason ?? '').trim();
      return detail.isEmpty ? '教务系统会话已失效或未登录，请到「我的信息」页登录' : '教务系统会话已失效：$detail';
    }
    if (_loginPattern.hasMatch(trimmed)) {
      return '教务系统会话已失效或未登录，请到「我的信息」页登录';
    }
    if (trimmed.isEmpty) {
      return '教务系统返回了空内容，请稍后重试';
    }
    return '教务系统返回的内容不是$what（可能被 WAF 拦截，或接口地址已变更）';
  }
}

/// 解析 `framework/main_index_loadkb.jsp`（旧接口）返回的课表片段。
///
/// 实测（2026-09-21 真实抓取）结构**与新课表接口的 `kbtable` 完全不同**：
/// ```html
/// <table id="tab1" class="table … kb_table">
///   <thead><tr><th>周/节次</th><th>星期一</th>…<th>星期日</th></tr></thead>
///   <tbody>
///     <tr>
///       <td>第一二节 <br/>(01,02小节) <br/>08:20-09:55</td>
///       <td>…</td>
///       <td><p title = '课程学分：3<br/>课程属性：必修<br/>课程名称：线性代数<br/>
///            上课时间：第4周 星期三 [01-02]节<br/>上课地点：J3-311'>线性代数</p></td>
///       …
///     </tr>
///   </tbody>
/// </table>
/// $("#li_showWeek").html("<span …>第4周</span>/20周");
/// ```
/// 坑：
/// * 表格 id 是 `tab1`（class 里才带 `kb_table`），行首与表头都是 `<td>`；
/// * 课名的显示文本可能被截断成「概率论与数理..」——全名只认 title 里的「课程名称：」；
/// * 格子里**没有老师**（这正是拿它当副数据源的原因）；会话失效时返回 JSON。
abstract final class JwLoadkbParser {
  /// 课表表格本体（`id="tab1"`）。
  static final RegExp _tablePattern = RegExp(
    '<table[^>]*\\bid\\s*=\\s*[\'"]tab1[\'"][^>]*>(.*?)</table>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _rowPattern = RegExp(
    '<tr[^>]*>(.*?)</tr>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 一行里的格子：第一个是节次标签，后面依次是星期一到星期日。
  static final RegExp _cellPattern = RegExp(
    '<td[^>]*>(.*?)</td>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 课程条目：字段全在 `title` 里，正文是（可能截断的）课名。
  static final RegExp _coursePattern = RegExp(
    '<p\\b[^>]*\\btitle\\s*=\\s*[\'"](.*?)[\'"][^>]*>(.*?)</p>',
    dotAll: true,
    caseSensitive: false,
  );

  /// 行首节次格里的 `(01,02小节)`。
  static final RegExp _slotPattern = RegExp(r'\((\d+(?:\s*,\s*\d+)*)\s*小节\)');

  /// 主页面周次脚本：`$("#li_showWeek").html("…第4周…")`。
  static final RegExp _showWeekPattern = RegExp(
    'li_showWeek[\'"]?\\s*\\)?\\.html\\(\\s*[\'"](.*?)[\'"]\\s*\\)',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _weekPattern = RegExp('第\\s*(\\d+)\\s*周');

  /// 解析旧接口的课表片段。[fallbackWeek] 是发起请求用的那一周。
  ///
  /// 返回结构与新接口一致（[JwTimetableParser.parse] 的平替）；格子里没有老师，
  /// 有学分与课程属性。解析不到表格时抛 [JwException]（含会话失效的人话说明）。
  static JwTimetable parse(String html, {int? fallbackWeek}) {
    final RegExpMatch? table = _tablePattern.firstMatch(html);
    if (table == null) {
      throw JwException(JwTimetableParser._diagnose(html));
    }
    final int week =
        _weekOf(html) ?? fallbackWeek ?? 1;
    final List<CourseSession> sessions = <CourseSession>[];

    for (final RegExpMatch row in _rowPattern.allMatches(table.group(1)!)) {
      final List<RegExpMatch> cells = _cellPattern
          .allMatches(row.group(1)!)
          .toList(growable: false);
      // 第一格是「第一二节 (01,02小节) 08:20-09:55」这种节次标签。
      if (cells.length < 2) {
        continue;
      }
      final RegExpMatch? slot = _slotPattern.firstMatch(cells.first.group(1)!);
      if (slot == null) {
        continue;
      }
      final List<int> periods = slot
          .group(1)!
          .split(',')
          .map((String value) => int.tryParse(value.trim()))
          .whereType<int>()
          .toList(growable: false);
      if (periods.isEmpty) {
        continue;
      }
      final int startPeriod = periods.first;
      final int endPeriod = periods.last;

      // 其余格子按位置对应星期一到星期日。
      for (var index = 1; index < cells.length && index <= 7; index++) {
        final int weekday = index;
        final String cell = cells[index].group(1)!;
        for (final RegExpMatch course in _coursePattern.allMatches(cell)) {
          final Map<String, String> fields = _titleFields(course.group(1)!);
          final String name = (fields['课程名称'] ??
                  JwTimetableParser._plain(course.group(2)!))
              .trim();
          if (name.isEmpty) {
            continue;
          }
          sessions.add(
            CourseSession(
              course: Course(
                name: name,
                location: (fields['上课地点'] ?? '').trim(),
                teacher: '',
                credits: _cleanField(fields['课程学分']),
                category: _cleanField(fields['课程属性']),
              ),
              weekday: weekday,
              startPeriod: startPeriod,
              endPeriod: endPeriod,
              // 接口按日期筛好了「这一周」的课，周次就用页面标注的当前周。
              startWeek: week,
              endWeek: week,
            ),
          );
        }
      }
    }

    sessions.sort((CourseSession a, CourseSession b) {
      final int byDay = a.weekday.compareTo(b.weekday);
      return byDay != 0 ? byDay : a.startPeriod.compareTo(b.startPeriod);
    });
    return JwTimetable(week: week, sessions: sessions);
  }

  /// 从 `li_showWeek` 的赋值里拿当前周次；拿不到返回 null。
  static int? _weekOf(String html) {
    final RegExpMatch? fragment = _showWeekPattern.firstMatch(html);
    if (fragment == null) {
      return null;
    }
    return int.tryParse(
      _weekPattern.firstMatch(fragment.group(1)!)?.group(1) ?? '',
    );
  }

  /// 把 `课程学分：3<br/>课程属性：必修<br/>…` 拆成字段表。
  static Map<String, String> _titleFields(String title) {
    final Map<String, String> fields = <String, String>{};
    for (final String part in title.split(RegExp(r'<br\s*/?>'))) {
      final int at = part.indexOf('：');
      if (at <= 0) {
        continue;
      }
      fields[part.substring(0, at).trim()] = part.substring(at + 1).trim();
    }
    return fields;
  }

  /// 字段值去掉 HTML 空格实体；空串归一成 null（调用方按「没有这个字段」处理）。
  static String? _cleanField(String? value) {
    if (value == null) {
      return null;
    }
    final String cleaned = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

/// 解析 `kbcx/kbxx_classroom_ifr` 返回的教室空余表。
///
/// 这个页面返回的是一张**整表**：一行一间教室，一列一个「大节」，
/// 格子里有内容 = 这节课被占用，空格子 = 空闲。表头两行，
/// 第一行写星期几（横跨若干列），第二行写节次：
/// ```html
/// <table>
///   <tr><th rowspan="2">教室</th><th colspan="2">星期一</th>…<th colspan="2">星期日</th></tr>
///   <tr><th>第1-2节</th><th>第3-4节</th>…</tr>
///   <tr><td>J1-101</td><td>高等数学<br/>王可芸</td><td></td>…</tr>
/// </table>
/// ```
///
/// 各校模板细节不一样（列数、有没有容量列、是不是只返回某一天、表头用 `<th>` 还是
/// `<td>`），所以这里**不硬编码列位**：先把表格按 `rowspan`/`colspan` 摊平成网格，
/// 再从**表头文字**反推每一列属于星期几、哪几节。只有节次表头也缺失时才退到
/// 「一周 6 个大节」的兜底排法（[bigPeriods]）。
abstract final class JwClassroomParser {
  /// 页面里可能有多张表（外层布局表 + 结果表），取「格子最多」的那张。
  ///
  /// 非贪婪匹配会让外层表的捕获在第一个 `</table>` 处结束 —— 那正好把内层表整段
  /// 包住，所以即使页面是嵌套结构，取到的内容也是完整的。
  static final RegExp _tablePattern = RegExp(
    '<table\\b[^>]*>(.*?)</table\\s*>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _rowPattern = RegExp(
    '<tr\\b[^>]*>(.*?)</tr\\s*>',
    dotAll: true,
    caseSensitive: false,
  );

  /// `<td …>…</td>` 或 `<th …>…</th>`；三个分组分别是标签名、属性、内容。
  static final RegExp _cellPattern = RegExp(
    '<(td|th)\\b([^>]*)>(.*?)</\\1\\s*>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _rowspanPattern = RegExp(
    'rowspan\\s*=\\s*["\']?\\s*(\\d+)',
    caseSensitive: false,
  );

  static final RegExp _colspanPattern = RegExp(
    'colspan\\s*=\\s*["\']?\\s*(\\d+)',
    caseSensitive: false,
  );

  /// 单元格里的换行：用来把「课程名 / 教师 / 班级」拆开。
  static final RegExp _lineBreakPattern = RegExp(
    r'<br\s*/?>|<hr[^>]*>',
    caseSensitive: false,
  );

  static final RegExp _tagPattern = RegExp(r'<[^>]*>');
  static final RegExp _spacePattern = RegExp(r'\s+');
  static final RegExp _entityPattern = RegExp(r'&#(\d+);');

  /// `星期一` / `星期天` / `星期末`。
  static final RegExp _weekdayPattern = RegExp('星期\\s*([一二三四五六日天末])');

  /// `第1-2节` / `第1,2节` / `第3节`。
  static final RegExp _periodPattern = RegExp(
    r'第\s*(\d+(?:\s*[-—~、,，]\s*\d+)*)\s*节',
  );

  static final RegExp _digitsPattern = RegExp(r'\d+');

  /// 教室名那一列的表头（不同学校写法不一）。
  static final RegExp _roomHeaderPattern = RegExp('教室|房间|课室|地点');

  /// 「上午 / 中午 / 下午 / 晚上」—— 有的学校表头用**时段行**给节次列分组
  /// （横跨若干列的「上午」…），它们是表头，不是数据列。
  static final RegExp _groupHeaderPattern = RegExp('上午|中午|下午|晚上');

  /// 星期几的中文数字。
  static const Map<String, int> _weekdayDigits = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
    '末': 7,
  };

  /// 节次表头缺失时的兜底：一天 6 个大节。
  ///
  /// 只在本校（11 节）这种「两节一段」的作息下成立，所以它只是最后一道兜底 ——
  /// 只要页面写了节次表头就绝不会用到。
  static const List<JwPeriodRange> bigPeriods = <JwPeriodRange>[
    JwPeriodRange(start: 1, end: 2),
    JwPeriodRange(start: 3, end: 4),
    JwPeriodRange(start: 5, end: 6),
    JwPeriodRange(start: 7, end: 8),
    JwPeriodRange(start: 9, end: 10),
    JwPeriodRange(start: 11, end: 12),
  ];

  /// 解析教室空余表。
  ///
  /// [fallbackWeek] / [fallbackWeekday] 是**请求参数本身** —— 页面可能不把「你问的是
  /// 哪一天」写进表头（只查一天时经常如此），这时就用请求值补上。
  static JwClassroomBoard parse(
    String html, {
    required int fallbackWeek,
    required int fallbackWeekday,
  }) {
    final String? table = _largestTable(html);
    if (table == null) {
      throw JwException(JwTimetableParser._diagnose(html, what: '教室空余表'));
    }

    final List<List<_GridCell>> grid = _expand(table);
    final int columnCount = grid.fold(
      0,
      (int max, List<_GridCell> row) => row.length > max ? row.length : max,
    );

    // 1) 从表头反推每一列的「星期几 / 哪几节 / 其它列名」。
    final Map<int, int> columnWeekday = <int, int>{};
    final Map<int, JwPeriodRange> columnPeriods = <int, JwPeriodRange>{};
    final Map<int, String> columnLabels = <int, String>{};
    for (final List<_GridCell> row in grid) {
      if (!_looksLikeHeader(row) || _isSpanningTitle(row)) {
        continue;
      }
      for (var c = 0; c < row.length; c++) {
        final _GridCell cell = row[c];
        if (cell.isEmpty) {
          continue;
        }
        final int? weekday = _weekdayOf(cell.full);
        if (weekday != null) {
          columnWeekday[c] = weekday;
          continue;
        }
        final JwPeriodRange? periods = _periodsOf(cell.full);
        if (periods != null) {
          columnPeriods[c] = periods;
          continue;
        }
        // 「上午 / 下午 / 晚上」这类时段分组表头横跨的是节次列，
        // 不能收进 columnLabels，否则这些列会被当成「其它列」丢掉。
        if (_groupHeaderPattern.hasMatch(cell.full)) {
          continue;
        }
        columnLabels.putIfAbsent(c, () => cell.label);
      }
    }

    // 2) 教室名那一列：优先认表头写着「教室 / 房间 / 地点」的那列，认不出就用第一列。
    var roomColumn = 0;
    for (final MapEntry<int, String> entry in columnLabels.entries) {
      if (_roomHeaderPattern.hasMatch(entry.value)) {
        roomColumn = entry.key;
        break;
      }
    }

    // 3) 节次表头缺失时的兜底：按列序，每个星期分组内依次填「大节」。
    final List<int> bodyColumns = <int>[
      for (var c = 0; c < columnCount; c++)
        if (c != roomColumn && !columnLabels.containsKey(c)) c,
    ];
    if (columnPeriods.isEmpty) {
      final Map<int, int> used = <int, int>{};
      for (final int c in bodyColumns) {
        final int weekday = columnWeekday[c] ?? fallbackWeekday;
        final int index = used[weekday] ?? 0;
        if (index >= bigPeriods.length) {
          continue;
        }
        columnWeekday[c] = weekday;
        columnPeriods[c] = bigPeriods[index];
        used[weekday] = index + 1;
      }
    }

    // 4) 逐行读教室。
    final List<JwClassroom> classrooms = <JwClassroom>[];
    for (final List<_GridCell> row in grid) {
      if (_looksLikeHeader(row) || _isSpanningTitle(row)) {
        continue;
      }
      final String name = roomColumn < row.length ? row[roomColumn].label : '';
      if (name.isEmpty) {
        continue;
      }
      // 表头没被 `<th>` 标记时可能混进数据行，这里再挡一层。
      if (_weekdayOf(name) != null || _periodsOf(name) != null) {
        continue;
      }
      // 「教室/节次」这种**表头文字**被当成教室名的兜底：有的模板表头
      // 全用 `<td>`（第一行只有「教室/节次 + 上午/下午/晚上」，认不出节次），
      // 摊平后它会变成一行假教室。表头字样 + 不带数字（真教室名如 J1-101
      // 都有数字）的一律不当教室。
      if ((_roomHeaderPattern.hasMatch(name) && !_digitsPattern.hasMatch(name)) ||
          name == columnLabels[roomColumn]) {
        continue;
      }

      final List<JwClassroomBusy> busy = <JwClassroomBusy>[];
      for (var c = 0; c < row.length; c++) {
        if (c == roomColumn) {
          continue;
        }
        final _GridCell cell = row[c];
        if (cell.isEmpty) {
          continue;
        }
        final JwPeriodRange? periods = columnPeriods[c];
        if (periods == null) {
          continue;
        }
        busy.add(
          JwClassroomBusy(
            weekday: columnWeekday[c] ?? fallbackWeekday,
            periods: periods,
            label: cell.label,
            detail: cell.detail,
          ),
        );
      }

      final Map<String, String> extras = <String, String>{};
      for (final MapEntry<int, String> entry in columnLabels.entries) {
        final int c = entry.key;
        if (c == roomColumn ||
            c >= row.length ||
            extras.containsKey(entry.value)) {
          continue;
        }
        final String value = row[c].label;
        if (value.isNotEmpty) {
          extras[entry.value] = value;
        }
      }

      classrooms.add(JwClassroom(name: name, busy: busy, extras: extras));
    }

    // 5) 节次列（给「只看第几节」的筛选用），按节次排序去重。
    final List<JwPeriodRange> periodColumns = <JwPeriodRange>[];
    for (final int c in bodyColumns) {
      final JwPeriodRange? periods = columnPeriods[c];
      if (periods != null && !periodColumns.contains(periods)) {
        periodColumns.add(periods);
      }
    }
    periodColumns.sort(
      (JwPeriodRange a, JwPeriodRange b) => a.start.compareTo(b.start),
    );

    return JwClassroomBoard(
      classrooms: classrooms,
      week: fallbackWeek,
      weekday: fallbackWeekday,
      periodColumns: periodColumns,
      campusOptions: _options(html, 'xqid'),
      buildingOptions: _options(html, 'jzwid'),
    );
  }

  /// 页面里格子最多的那张表；实在没有表时返回 null。
  static String? _largestTable(String html) {
    String? best;
    var bestCells = 0;
    for (final RegExpMatch match in _tablePattern.allMatches(html)) {
      final String body = match.group(1)!;
      final int cells = _cellPattern.allMatches(body).length;
      if (cells > bestCells) {
        bestCells = cells;
        best = body;
      }
    }
    return bestCells >= 2 ? best : null;
  }

  /// 把表格摊平成规整网格（把 rowspan / colspan 铺到它们覆盖的每一个位置）。
  static List<List<_GridCell>> _expand(String tableHtml) {
    final List<List<(_GridCell, int, int)>> raw =
        <List<(_GridCell, int, int)>>[];
    for (final RegExpMatch row in _rowPattern.allMatches(tableHtml)) {
      final List<(_GridCell, int, int)> cells = <(_GridCell, int, int)>[];
      for (final RegExpMatch cell in _cellPattern.allMatches(row.group(1)!)) {
        final String attrs = cell.group(2) ?? '';
        cells.add((
          _cell(cell.group(3)!, isHeader: cell.group(1)!.toLowerCase() == 'th'),
          _spanOf(_rowspanPattern, attrs),
          _spanOf(_colspanPattern, attrs),
        ));
      }
      if (cells.isNotEmpty) {
        raw.add(cells);
      }
    }

    final List<List<_GridCell?>> grid = <List<_GridCell?>>[];
    void ensure(int r, int c) {
      while (grid.length <= r) {
        grid.add(<_GridCell?>[]);
      }
      while (grid[r].length <= c) {
        grid[r].add(null);
      }
    }

    for (var r = 0; r < raw.length; r++) {
      var col = 0;
      for (final (_GridCell cell, int rowspan, int colspan) in raw[r]) {
        ensure(r, col);
        while (grid[r][col] != null) {
          col += 1;
          ensure(r, col);
        }
        for (var i = 0; i < colspan; i++) {
          for (var k = 0; k < rowspan; k++) {
            ensure(r + k, col + i);
            grid[r + k][col + i] ??= cell;
          }
        }
        col += colspan;
      }
    }

    return <List<_GridCell>>[
      for (final List<_GridCell?> row in grid)
        <_GridCell>[for (final _GridCell? cell in row) cell ?? _emptyCell],
    ];
  }

  /// 读一个单元格：第一行当「主文本」，其余行拼成一个补充说明。
  static _GridCell _cell(String inner, {required bool isHeader}) {
    final List<String> parts = inner
        .split(_lineBreakPattern)
        .map(_plain)
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return _GridCell(label: '', detail: null, isHeader: isHeader);
    }
    return _GridCell(
      label: parts.first,
      detail: parts.length > 1 ? parts.skip(1).join(' · ') : null,
      isHeader: isHeader,
    );
  }

  /// 这一行是不是表头：写了 `<th>`，或者出现了「星期几 / 第几节」这类文字。
  ///
  /// 不靠 `<th>` 单打独斗是因为不少模板的表头用的是 `<td>`。
  static bool _looksLikeHeader(List<_GridCell> row) {
    for (final _GridCell cell in row) {
      if (cell.isEmpty) {
        continue;
      }
      if (cell.isHeader ||
          _weekdayOf(cell.full) != null ||
          _periodsOf(cell.full) != null ||
          _groupHeaderPattern.hasMatch(cell.full)) {
        return true;
      }
    }
    return false;
  }

  /// 整行都是**同一个**单元格 —— 那是横跨全表的标题（如「教室空余查询」），不是数据。
  ///
  /// 用对象标识判断：展开 colspan 时同一个单元格会被写进多个格位，是同一个实例。
  static bool _isSpanningTitle(List<_GridCell> row) {
    final List<_GridCell> filled = <_GridCell>[
      for (final _GridCell cell in row)
        if (!cell.isEmpty) cell,
    ];
    if (filled.length < 2) {
      return false;
    }
    return filled.every((_GridCell cell) => identical(cell, filled.first));
  }

  /// `星期X` → 1~7。
  static int? _weekdayOf(String text) {
    final String? raw = _weekdayPattern.firstMatch(text)?.group(1);
    return raw == null ? null : _weekdayDigits[raw];
  }

  /// `第1-2节` → (1, 2)。取首尾数字，中间的顿号/逗号写法都认。
  static JwPeriodRange? _periodsOf(String text) {
    final RegExpMatch? match = _periodPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final List<int> numbers = _digitsPattern
        .allMatches(match.group(1)!)
        .map((RegExpMatch item) => int.parse(item.group(0)!))
        .toList();
    if (numbers.isEmpty) {
      return null;
    }
    final int first = numbers.first;
    final int last = numbers.last;
    return first <= last
        ? JwPeriodRange(start: first, end: last)
        : JwPeriodRange(start: last, end: first);
  }

  static int _spanOf(RegExp pattern, String attrs) {
    final String? raw = pattern.firstMatch(attrs)?.group(1);
    final int value = raw == null ? 1 : (int.tryParse(raw) ?? 1);
    return value < 1 ? 1 : value;
  }

  /// 读 `<select name="…">` 里的选项（校区 / 教学楼）。
  static List<JwClassroomOption> _options(String html, String name) {
    final RegExp selectPattern = RegExp(
      '<select\\b[^>]*\\b(?:name|id)\\s*=\\s*["\']$name["\'][^>]*>(.*?)</select\\s*>',
      dotAll: true,
      caseSensitive: false,
    );
    final RegExpMatch? select = selectPattern.firstMatch(html);
    if (select == null) {
      return const <JwClassroomOption>[];
    }
    final RegExp optionPattern = RegExp(
      '<option\\b([^>]*)>(.*?)</option\\s*>',
      dotAll: true,
      caseSensitive: false,
    );
    final RegExp valuePattern = RegExp(
      'value\\s*=\\s*["\']([^"\']*)["\']',
      caseSensitive: false,
    );

    final List<JwClassroomOption> options = <JwClassroomOption>[];
    for (final RegExpMatch option in optionPattern.allMatches(
      select.group(1)!,
    )) {
      final String label = _plain(option.group(2)!);
      if (label.isEmpty) {
        continue;
      }
      options.add(
        JwClassroomOption(
          id: valuePattern.firstMatch(option.group(1) ?? '')?.group(1) ?? '',
          name: label,
        ),
      );
    }
    return options;
  }

  /// 去标签、还原实体、收拢空白。
  static String _plain(String html) => html
      .replaceAll(_tagPattern, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAllMapped(
        _entityPattern,
        (Match match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAll(_spacePattern, ' ')
      .trim();
}

/// 展开后网格里的一个单元格。
@immutable
class _GridCell {
  const _GridCell({
    required this.label,
    required this.detail,
    required this.isHeader,
  });

  /// 单元格第一行（课程名 / 表头文字 / 教室名）。
  final String label;

  /// 其余行拼起来的补充说明。
  final String? detail;

  /// 是不是 `<th>`。
  final bool isHeader;

  /// 全部文字（表头识别要用完整内容，例如「上午<br/>第1-2节」）。
  String get full => detail == null ? label : '$label $detail';

  /// 没有任何内容。
  bool get isEmpty => label.isEmpty && (detail == null || detail!.isEmpty);
}

/// 空单元格的共享实例（网格里用它填被 colspan 略过、以及缺列的位置）。
const _GridCell _emptyCell = _GridCell(
  label: '',
  detail: null,
  isHeader: false,
);

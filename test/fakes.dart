import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:class_schedule/data/class_notifier.dart';
import 'package:class_schedule/data/custom_course_store.dart';
import 'package:class_schedule/data/jw_account_store.dart';
import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_http.dart';
import 'package:class_schedule/data/keep_alive_platform.dart';
import 'package:class_schedule/data/keep_alive_store.dart';
import 'package:class_schedule/data/reminder_store.dart';
import 'package:class_schedule/data/widget_updater.dart';
import 'package:class_schedule/main.dart';
import 'package:class_schedule/models/custom_course.dart';
import 'package:class_schedule/models/keep_alive.dart';
import 'package:class_schedule/models/next_class.dart';
import 'package:class_schedule/models/reminder.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/widgets.dart';

/// 真实抓取到的课表响应（`POST xskb/xskb_list.do`，`zc=4`）。
final String fixtureHtml = File('test/fixtures/xskb_week4.html')
    .readAsStringSync();

/// 真实抓取到的主页面响应（页面上写着「第3周/20周」+ 学生信息）。
///
/// **只用于解析类测试**：它是某一天（2026-09-20 周日）抓下来的静态页面，页面上那个
/// 「第3周」只对那一天成立。要做「渲染出第 N 周课表」这类测试，用
/// [fixtureWeekInfoHtmlToday]。
final String fixtureWeekInfoHtml = File('test/fixtures/xsmain_week3.html')
    .readAsStringSync();

/// 教务系统口径的「今天第几周」（周一到周日算一周，起点取 [defaultTerm] 的第 1 周）。
///
/// 反推公式和 `ScheduleController._adoptMainPage` 是一对：
/// `学期起点 = 今天所在周的周一 - ((教务周次 - 1) * 7 + 1) 天`。
/// 把这里的 [schoolWeekToday] 填进主页面，校验出来的学期起点就正好是 [defaultTerm]。
int get schoolWeekToday {
  final DateTime monday = JwTimetableClient.mondayOf(DateTime.now());
  final int days = monday.difference(defaultTerm.startOfWeek(1)).inDays;
  return (days - 1) ~/ 7 + 1;
}

/// 主页面夹具，但「第 N 周」换成**按今天算出来的教务周次**。
///
/// 为什么不能直接用 [fixtureWeekInfoHtml]：教务系统按周一到周日分周，而它是静态页面。
/// 拿它当响应，校准出来的学期起点会随「今天是星期几」前后挪一周 ——
/// 周日跑恰好对得上（9/20 那天学校正是第 3 周，与第 4 周课表夹具相邻），
/// 周一跑就整体错开，网格里一门课都渲染不出来。所以这里把周次算成「今天」的值，
/// 让校准后的学期起点恒等于 [defaultTerm]，夹具内容与当前周永远对得上。
final String fixtureWeekInfoHtmlToday = fixtureWeekInfoHtml.replaceFirst(
  RegExp(r'第\s*\d+\s*周'),
  '第$schoolWeekToday周',
);

/// 真实抓取到的选课中心响应（当前没有开放轮次）。
final String fixtureSelectionEmptyHtml = File('test/fixtures/xk_empty.html')
    .readAsStringSync();

/// 合成夹具：选课轮次列表（结构照抄真实页面）。
final String fixtureSelectionRoundsHtml = File(
  'test/fixtures/xk_rounds_synthetic.html',
).readAsStringSync();

/// 合成夹具：教室空余查询的返回页面（教室表 + 校区/教学楼下拉）。
///
/// 结构照抄强智 jsxsd 的教室查询页：一行一间教室，一列一个大节，
/// 表头两行（第一行星期几、第二行节次），格子里有内容就是有课。
final String fixtureClassroomHtml = File(
  'test/fixtures/kbxx_classroom.html',
).readAsStringSync();

/// 真实抓取到的**登录失败**响应（用错账号密码提交后，教务系统把登录页打回来，
/// 并且把原因写进 `#showMsg`）。
final String fixtureLoginFailedHtml = File('test/fixtures/login_failed.html')
    .readAsStringSync();

/// 登录成功的响应：合成内容。
///
/// 真实成功响应长什么样**不重要** —— 判据不是它，而是「拿新会话读主页面能不能读通」
/// （见 `JwTimetableClient.login`）。这里按跳转页的样子造一个。
const String fixtureLoginOkHtml =
    '<html><body><script>window.location.href="indexx.jsp";</script></body></html>';

/// 一张 2×2 的红色 PNG，冒充登录验证码。
///
/// 真的验证码是 80×40 的 JPEG，但测试只需要「能被 `Image.memory` 解码的真实图片」，
/// PNG 的 base64 最短。
final Uint8List fakeCaptchaImage = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZ'
  'YAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
);

/// 解析好的夹具内容，方便断言。
final JwTimetable fixtureTimetable = JwTimetableParser.parse(fixtureHtml);

/// 正常响应的传输层：主页面给出「今天的教务周次 / 20 周」
/// （反推第 1 周周日 = 2026-08-30，与 [defaultTerm] 一致），课表接口返回第 4 周夹具。
Future<String> jwOkTransport(
  String method,
  Uri url,
  String body,
  Map<String, String> requestHeaders,
) async {
  if (url.path.contains('xsMain')) {
    return fixtureWeekInfoHtmlToday;
  }
  if (url.path.contains('kbxx_classroom')) {
    return fixtureClassroomHtml;
  }
  return fixtureHtml;
}

/// 会话过期的传输层：教务系统把请求打回登录页。
Future<String> jwExpiredTransport(
  String method,
  Uri url,
  String body,
  Map<String, String> requestHeaders,
) async => '<html><head><title>用户登录</title></head></html>';

/// 测试用应用外壳：走夹具数据（**不联网**）、零防抖。
///
/// 课表数据只来自教务系统，所以任何 widget 测试都必须注入传输层，
/// 否则会真的去请求教务系统。[loginTransport] 管登录流程（要读响应头与图片字节）。
/// 账户存储、上课提醒与自建课程都默认给内存实现 —— 测试不该碰真实磁盘，
/// 更不该往系统里真的排闹钟。
Widget jwApp({
  JwTransport? transport,
  JwDetailedTransport? loginTransport,
  JwAccountStore? accountStore,
  JwStoredAccount? restoredAccount,
  ClassReminderNotifier? reminderNotifier,
  ReminderStore? reminderStore,
  ClassReminderSettings? restoredReminder,
  CustomCourseStore? customCourseStore,
  List<CustomCourse>? restoredCustomCourses,
  KeepAliveStore? keepAliveStore,
  KeepAlivePlatform? keepAlivePlatform,
  KeepAliveSettings? restoredKeepAlive,
  WidgetUpdater? widgetUpdater,
}) => ClassScheduleApp(
  transport: transport ?? jwOkTransport,
  detailedTransport: loginTransport ?? FakeLoginTransport().call,
  accountStore: accountStore ?? FakeAccountStore(),
  restoredAccount: restoredAccount,
  reminderNotifier: reminderNotifier ?? FakeReminderNotifier(),
  reminderStore: reminderStore ?? FakeReminderStore(),
  restoredReminder: restoredReminder,
  customCourseStore: customCourseStore ?? FakeCustomCourseStore(),
  restoredCustomCourses: restoredCustomCourses,
  keepAliveStore: keepAliveStore ?? FakeKeepAliveStore(),
  keepAlivePlatform: keepAlivePlatform ?? FakeKeepAlivePlatform(),
  restoredKeepAlive: restoredKeepAlive,
  widgetUpdater: widgetUpdater ?? FakeWidgetUpdater(),
  swipeDebounce: Duration.zero,
);

/// 内存里的账户存储：不碰磁盘，顺便记下写 / 清了几次。
class FakeAccountStore implements JwAccountStore {
  FakeAccountStore([this.value]);

  /// 当前存着的内容。
  JwStoredAccount? value;

  /// 写入次数。
  int writes = 0;

  /// 清除次数。
  int clears = 0;

  @override
  Future<JwStoredAccount?> read() async => value;

  @override
  Future<void> write(JwStoredAccount account) async {
    writes += 1;
    value = account;
  }

  @override
  Future<void> clear() async {
    clears += 1;
    value = null;
  }
}

/// 登录流程的假传输层：验证码给一张小图片，登录提交按脚本返回。
///
/// 登录成功与否由「新会话能不能读通主页面」决定，所以这里只管给出响应，
/// 主页面仍由 [RecordingTransport] / [jwOkTransport] 提供。
class FakeLoginTransport {
  FakeLoginTransport({
    this.loginHtml = fixtureLoginOkHtml,
    this.loginError,
    this.captchaError,
    this.captchaCookie = 'JSESSIONID=login-before; HWWAFSESID=waf123',
    this.loginCookie = 'JSESSIONID=after-login; HWWAFSESID=waf123',
    this.captchaContentType = 'image/png',
  });

  /// 登录提交的响应正文。
  final String loginHtml;

  /// 登录提交要抛的异常（null 表示成功返回）。
  final Object? loginError;

  /// 取验证码要抛的异常（null 表示正常给一张图）。
  final Object? captchaError;

  /// 验证码响应下发的临时会话。
  final String captchaCookie;

  /// 登录成功后响应下发的新会话。
  final String loginCookie;

  /// 验证码响应的 MIME 类型，用来测「接口没返回图片」的分支。
  final String captchaContentType;

  /// 验证码请求次数。
  int captchaCalls = 0;

  /// 登录提交次数。
  int loginCalls = 0;

  /// 最后一次登录提交的表单正文。
  String? lastLoginBody;

  /// 最后一次登录提交带的会话（`X-JW-Cookie`）。
  String? lastLoginCookie;

  Future<JwHttpResponse> call(
    String method,
    Uri url,
    String body,
    Map<String, String> requestHeaders,
  ) async {
    if (url.path.contains('verifycode')) {
      captchaCalls += 1;
      final Object? captchaFailure = captchaError;
      if (captchaFailure != null) {
        throw captchaFailure;
      }
      return JwHttpResponse(
        statusCode: 200,
        bytes: fakeCaptchaImage,
        cookie: captchaCookie,
        contentType: captchaContentType,
      );
    }

    loginCalls += 1;
    lastLoginBody = body;
    lastLoginCookie = requestHeaders['X-JW-Cookie'];

    final Object? failure = loginError;
    if (failure != null) {
      throw failure;
    }
    return JwHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(utf8.encode(loginHtml)),
      cookie: loginCookie,
      contentType: 'text/html',
      charset: 'utf-8',
    );
  }
}

/// 记录调用的假传输层：按 URL 区分「主页面」「课表」「选课中心」「教室查询」四种请求。
class RecordingTransport {
  RecordingTransport({
    this.error,
    this.weekInfoError,
    this.selectionError,
    this.classroomError,
    this.delay = Duration.zero,
    String? weekInfoHtml,
    String? timetableHtml,
    String? selectionHtml,
    String? classroomHtml,
  }) : weekInfoHtml = weekInfoHtml ?? fixtureWeekInfoHtmlToday,
       timetableHtml = timetableHtml ?? fixtureHtml,
       selectionHtml = selectionHtml ?? fixtureSelectionEmptyHtml,
       classroomHtml = classroomHtml ?? fixtureClassroomHtml;

  /// 课表请求要抛的异常（null 表示成功）。
  final Object? error;

  /// 主页面请求要抛的异常（null 表示成功）。
  final Object? weekInfoError;

  /// 选课中心请求要抛的异常（null 表示成功）。
  final Object? selectionError;

  /// 教室空余查询要抛的异常（null 表示成功）。
  final Object? classroomError;

  /// 模拟网络耗时。
  final Duration delay;

  final String weekInfoHtml;
  final String timetableHtml;
  final String selectionHtml;
  final String classroomHtml;

  /// 全部请求的方法。
  final List<String> methods = <String>[];

  /// 全部请求的地址。
  final List<Uri> urls = <Uri>[];

  /// 课表 POST 的表单体（`jx0404id=&cj0701id=&zc=<周次>&demo=&sfFD=1`）。
  final List<String> bodies = <String>[];

  /// 教室查询 POST 的表单体（`xqid=&jzwid=&zc1=&…`）。
  final List<String> classroomBodies = <String>[];

  /// 每次请求的请求头。
  final List<Map<String, String>> headers = <Map<String, String>>[];

  /// 课表请求次数。
  int get callCount => bodies.length;

  /// 主页面（周次）请求次数。
  int get weekInfoCalls =>
      methods.where((String method) => method == 'GET').length;

  Future<String> call(
    String method,
    Uri url,
    String body,
    Map<String, String> requestHeaders,
  ) async {
    methods.add(method);
    urls.add(url);
    headers.add(requestHeaders);

    final bool isMainPage = url.path.contains('xsMain');
    final bool isSelection = url.path.contains('xklc');
    final bool isClassroom = url.path.contains('kbxx_classroom');
    if (isClassroom) {
      classroomBodies.add(body);
    } else if (!isMainPage && !isSelection) {
      bodies.add(body);
    }

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    if (isClassroom) {
      final Object? failure = classroomError;
      if (failure != null) {
        throw failure;
      }
      return classroomHtml;
    }

    if (isSelection) {
      final Object? failure = selectionError;
      if (failure != null) {
        throw failure;
      }
      return selectionHtml;
    }

    final Object? failure = isMainPage ? weekInfoError : error;
    if (failure != null) {
      throw failure;
    }
    return isMainPage ? weekInfoHtml : timetableHtml;
  }
}

/// 内存里的自建课程存储：不碰磁盘，顺便记下写了几次。
class FakeCustomCourseStore implements CustomCourseStore {
  FakeCustomCourseStore([List<CustomCourse>? value])
    : value = List<CustomCourse>.of(value ?? const <CustomCourse>[]);

  /// 当前存着的课程；空列表表示一门都没存过。
  ///
  /// 存的是副本，所以断言时不会被 controller 后续的写入改掉。
  List<CustomCourse> value;

  /// 写入次数。
  int writes = 0;

  @override
  Future<List<CustomCourse>> read() async => List<CustomCourse>.of(value);

  @override
  Future<void> write(List<CustomCourse> courses) async {
    writes += 1;
    value = List<CustomCourse>.of(courses);
  }
}

/// 内存里的上课提醒设置存储：不碰磁盘，顺便记下写了几次。
class FakeReminderStore implements ReminderStore {
  FakeReminderStore([this.value]);

  /// 当前存着的设置；null 表示没存过（冷启动会用默认值）。
  ClassReminderSettings? value;

  /// 写入次数。
  int writes = 0;

  @override
  Future<ClassReminderSettings?> read() async => value;

  @override
  Future<void> write(ClassReminderSettings settings) async {
    writes += 1;
    value = settings;
  }
}

/// 假的系统通知投递口：记下被要求排了什么，**不碰平台通道**。
///
/// widget / controller 测试必须用它，否则会去碰 `flutter_local_notifications`
/// 的方法通道（测试环境里没有实现），而且真的会往系统里排闹钟。
class FakeReminderNotifier implements ClassReminderNotifier {
  FakeReminderNotifier({this.supported = true, this.granted = true});

  /// 这个平台支不支持系统通知。
  bool supported;

  /// 通知权限给不给。
  bool granted;

  /// 最后一次下发的排期（覆盖式的，所以只留最新的）。
  List<ClassReminder> synced = <ClassReminder>[];

  /// 下发排期的次数。
  int syncs = 0;

  /// 清空的次数。
  int cancels = 0;

  /// 申请权限的次数。
  int permissionRequests = 0;

  /// 跳系统设置页的次数。
  int settingsOpened = 0;

  /// 让 [sync] 抛这个异常，用来测「排期失败」的分支。
  Object? syncError;

  @override
  bool get isSupported => supported;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    return granted;
  }

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> openNotificationSettings() async {
    settingsOpened += 1;
    return true;
  }

  @override
  Future<void> sync(List<ClassReminder> reminders) async {
    final Object? failure = syncError;
    if (failure != null) {
      throw failure;
    }
    syncs += 1;
    synced = List<ClassReminder>.of(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancels += 1;
    synced = <ClassReminder>[];
  }
}

/// 内存里的保活设置存储：不碰磁盘，顺便记下写了几次。
class FakeKeepAliveStore implements KeepAliveStore {
  FakeKeepAliveStore([this.value]);

  /// 当前存着的设置；null 表示没存过（冷启动会用默认值）。
  KeepAliveSettings? value;

  /// 写入次数。
  int writes = 0;

  @override
  Future<KeepAliveSettings?> read() async => value;

  @override
  Future<void> write(KeepAliveSettings settings) async {
    writes += 1;
    value = settings;
  }
}

/// 假的保活平台口：不碰 MethodChannel，只记录调用。
class FakeKeepAlivePlatform implements KeepAlivePlatform {
  FakeKeepAlivePlatform({this.supported = true, this.ignoring = false});

  /// 这个平台有没有保活概念（Web 上没有）。
  bool supported;

  /// 当前是否在电池优化白名单里。
  bool ignoring;

  /// 申请跳过电池优化的次数（模拟系统确认框被弹）。
  int batteryRequests = 0;

  /// 申请后的返回值（模拟用户在系统框里点了「允许」与否）。
  bool batteryRequestResult = true;

  /// 各跳转入口被点的次数。
  int autoStartOpens = 0;
  int batteryListOpens = 0;
  int appDetailsOpens = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => ignoring;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    batteryRequests += 1;
    ignoring = batteryRequestResult;
    return batteryRequestResult;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    batteryListOpens += 1;
    return true;
  }

  @override
  Future<bool> openAutoStartSettings() async {
    autoStartOpens += 1;
    return true;
  }

  @override
  Future<bool> openAppDetailsSettings() async {
    appDetailsOpens += 1;
    return true;
  }
}

/// 假的小组件投递口：只记录推了多少次、最后一次推了什么。
class FakeWidgetUpdater implements WidgetUpdater {
  /// 推送的次数。
  int pushes = 0;

  /// 最近一次推送的条目（覆盖式，只留最新的）。
  List<NextClassEntry> last = <NextClassEntry>[];

  /// 让 [update] 抛这个异常，用来测「推送失败不影响主流程」。
  Object? error;

  @override
  bool get isSupported => true;

  @override
  Future<void> update(List<NextClassEntry> entries) async {
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    pushes += 1;
    last = List<NextClassEntry>.of(entries);
  }
}

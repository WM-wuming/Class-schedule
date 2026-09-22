import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'data/class_notifier.dart';
import 'data/captcha_recognizer.dart';
import 'data/custom_course_store.dart';
import 'data/jw_account_store.dart';
import 'data/jw_client.dart';
import 'data/jw_http.dart';
import 'data/keep_alive_platform.dart';
import 'data/keep_alive_store.dart';
import 'data/reminder_ring_platform.dart';
import 'data/reminder_store.dart';
import 'data/timetable_cache.dart';
import 'data/widget_updater.dart';
import 'models/custom_course.dart';
import 'models/course.dart';
import 'models/keep_alive.dart';
import 'models/reminder.dart';
import 'screens/home_shell.dart';
import 'state/schedule_controller.dart';

/// 读本机保存的东西要先用平台通道，所以启动是异步的：
/// 先把账户信息、上课提醒设置与自建课程读出来，再建界面 —— 这样首帧就是「已登录」+
/// 正确的开关状态 + 自己加的课已经站在网格上，不会先闪一下未登录、也不会把用户关掉的
/// 提醒先显示成开着。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沉浸式：内容画到状态栏 / 导航栏底下，各页面自己的 SafeArea 负责避让。
  // 不开这个的话，「教室状态」页的蓝色头部盖不到状态栏，顶上会留一条系统底色。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  const JwAccountStore accountStore = PrefsAccountStore();
  const ReminderStore reminderStore = PrefsReminderStore();
  const CustomCourseStore customCourseStore = PrefsCustomCourseStore();
  const KeepAliveStore keepAliveStore = PrefsKeepAliveStore();
  const TimetableCacheStore timetableCacheStore = PrefsTimetableCacheStore();
  final JwStoredAccount? saved = await accountStore.read();
  final ClassReminderSettings? reminder = await reminderStore.read();
  final List<CustomCourse> customCourses = await customCourseStore.read();
  final KeepAliveSettings? keepAlive = await keepAliveStore.read();
  // 整学期课表的本地 JSON 快照：读好后传给控制器水合进内存，
  // 首帧就能渲染任何一周的课表，不用等联网。
  final Map<int, List<CourseSession>> timetableCache = await timetableCacheStore
      .read();
  runApp(
    ClassScheduleApp(
      accountStore: accountStore,
      restoredAccount: saved,
      reminderStore: reminderStore,
      restoredReminder: reminder,
      customCourseStore: customCourseStore,
      restoredCustomCourses: customCourses,
      keepAliveStore: keepAliveStore,
      restoredKeepAlive: keepAlive,
      timetableCacheStore: timetableCacheStore,
      restoredTimetableCache: timetableCache,
    ),
  );
}

/// 课程表应用。
class ClassScheduleApp extends StatefulWidget {
  const ClassScheduleApp({
    super.key,
    this.transport,
    this.detailedTransport,
    this.accountStore,
    this.restoredAccount,
    this.reminderNotifier,
    this.reminderStore,
    this.restoredReminder,
    this.customCourseStore,
    this.restoredCustomCourses,
    this.keepAliveStore,
    this.keepAlivePlatform,
    this.ringPlatform,
    this.restoredKeepAlive,
    this.widgetUpdater,
    this.timetableCacheStore,
    this.restoredTimetableCache,
    this.captchaRecognizer,
    this.swipeDebounce = const Duration(milliseconds: 220),
  });

  /// 替换网络层，仅用于测试。
  final JwTransport? transport;

  /// 替换登录用的网络层（要读响应头与图片字节），仅用于测试。
  final JwDetailedTransport? detailedTransport;

  /// 账户信息的本地存储；null 时用 [PrefsAccountStore]。
  final JwAccountStore? accountStore;

  /// 启动时已经从本机读到的账户信息（正式启动由 `main()` 读好后传进来）。
  final JwStoredAccount? restoredAccount;

  /// 系统通知的投递口；null 时按当前平台真发通知。
  ///
  /// 测试里必须传假的：不然 widget 测试会去碰平台通道，而且真的往系统里排闹钟。
  final ClassReminderNotifier? reminderNotifier;

  /// 上课提醒设置的本地存储；null 时用 [PrefsReminderStore]。
  final ReminderStore? reminderStore;

  /// 启动时已经从本机读到的提醒设置（没存过就传 null，用默认值）。
  final ClassReminderSettings? restoredReminder;

  /// 自建课程的本地存储；null 时用 [PrefsCustomCourseStore]。
  final CustomCourseStore? customCourseStore;

  /// 启动时已经从本机读到的自建课程（没存过就传 null，按空列表处理）。
  final List<CustomCourse>? restoredCustomCourses;

  /// 保活设置的本地存储；null 时用 [PrefsKeepAliveStore]。
  final KeepAliveStore? keepAliveStore;

  /// 保活要碰系统的口子；null 时按当前平台建（测试里必须传假的）。
  final KeepAlivePlatform? keepAlivePlatform;

  /// 提醒「响铃」（勿扰豁免）要碰系统的口子；null 时按当前平台建（测试里必须传假的）。
  final ReminderRingPlatform? ringPlatform;

  /// 启动时已经从本机读到的保活设置（没存过就传 null，用默认值）。
  final KeepAliveSettings? restoredKeepAlive;

  /// 「下一节课」桌面小组件的投递口；null 时按当前平台建（测试里必须传假的）。
  final WidgetUpdater? widgetUpdater;

  /// 课表快照（整学期 JSON）的本地存储；null 时用 [PrefsTimetableCacheStore]。
  final TimetableCacheStore? timetableCacheStore;

  /// 启动时已经从本机读到的课表快照（正式启动由 `main()` 读好后传进来）。
  final Map<int, List<CourseSession>>? restoredTimetableCache;

  /// 登录验证码识别口；null 时按当前平台建（测试里传假的）。
  final CaptchaRecognizer? captchaRecognizer;

  /// 连续滑动换周的防抖时长，测试里传 [Duration.zero]。
  final Duration swipeDebounce;

  @override
  State<ClassScheduleApp> createState() => _ClassScheduleAppState();
}

class _ClassScheduleAppState extends State<ClassScheduleApp> {
  late final ScheduleController _controller = ScheduleController(
    transport: widget.transport,
    detailedTransport: widget.detailedTransport,
    accountStore: widget.accountStore,
    restoredAccount: widget.restoredAccount,
    reminderNotifier: widget.reminderNotifier,
    reminderStore: widget.reminderStore,
    restoredReminder: widget.restoredReminder,
    customCourseStore: widget.customCourseStore,
    restoredCustomCourses: widget.restoredCustomCourses,
    keepAliveStore: widget.keepAliveStore,
    keepAlivePlatform: widget.keepAlivePlatform,
    ringPlatform: widget.ringPlatform,
    restoredKeepAlive: widget.restoredKeepAlive,
    widgetUpdater: widget.widgetUpdater,
    timetableCacheStore: widget.timetableCacheStore,
    restoredTimetableCache: widget.restoredTimetableCache,
    captchaRecognizer: widget.captchaRecognizer,
    swipeDebounce: widget.swipeDebounce,
  );

  final FThemeData _theme = FThemeData(
    // forui 0.26 没有 seed 生成器，只有 neutralLight / neutralDark 两套配色，
    // 用 copyWith 把主色换成与课程表一致的蓝色。
    colors: FColors.neutralLight.copyWith(primary: const Color(0xFF2C63D4)),
    touch: true,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScheduleScope(
    controller: _controller,
    child: MaterialApp(
      title: '广应科课表',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      builder: (BuildContext context, Widget? child) =>
          FTheme(data: _theme, child: child!),
      home: const HomeShell(),
    ),
  );
}

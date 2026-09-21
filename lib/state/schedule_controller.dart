import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/class_notifier.dart';
import '../data/custom_course_store.dart';
import '../data/jw_account_store.dart';
import '../data/jw_client.dart';
import '../data/jw_credentials.dart';
import '../data/jw_exception.dart';
import '../data/jw_http.dart';
import '../data/jw_login.dart';
import '../data/keep_alive_platform.dart';
import '../data/keep_alive_store.dart';
import '../data/reminder_store.dart';
import '../data/widget_updater.dart';
import '../models/classroom.dart';
import '../models/course.dart';
import '../models/custom_course.dart';
import '../models/keep_alive.dart';
import '../models/next_class.dart';
import '../models/period.dart';
import '../models/reminder.dart';
import '../models/week.dart';
import 'reminder_planner.dart';

/// 学期兜底值。
///
/// 课表数据只来自教务系统，启动后 [ScheduleController.syncTermWithServer]
/// 会用主页面上的「第 N 周 / 共 N 周」反推出真实开学日期并覆盖这里，
/// 所以它只在**联网返回之前**那一瞬间、以及断网时起作用。
/// 留成 2026-08-30 是因为它对应本学期的第 1 周，断网时周次也不会错。
final Term defaultTerm = Term(startDate: DateTime(2026, 8, 30), totalWeeks: 20);

/// 用户可调的课表设置。
@immutable
class AppSettings {
  const AppSettings({
    required this.term,
    this.showWeekend = true,
    this.dimInactiveCourses = true,
    this.showTeacher = true,
    this.showPeriodTime = true,
  });

  /// 默认设置：[defaultTerm] + 打开全部显示选项。
  factory AppSettings.initial() => AppSettings(term: defaultTerm);

  /// 学期设置。
  final Term term;

  /// 是否显示周六、周日。
  final bool showWeekend;

  /// 是否淡化本周不上课的课程。
  final bool dimInactiveCourses;

  /// 是否在课程卡片上显示教师。
  final bool showTeacher;

  /// 是否在左侧时间轴上显示每节的起止时间。
  final bool showPeriodTime;

  /// 节次表。
  List<Period> get periods => Period.defaults;

  AppSettings copyWith({
    Term? term,
    bool? showWeekend,
    bool? dimInactiveCourses,
    bool? showTeacher,
    bool? showPeriodTime,
  }) => AppSettings(
    term: term ?? this.term,
    showWeekend: showWeekend ?? this.showWeekend,
    dimInactiveCourses: dimInactiveCourses ?? this.dimInactiveCourses,
    showTeacher: showTeacher ?? this.showTeacher,
    showPeriodTime: showPeriodTime ?? this.showPeriodTime,
  );
}

/// 课表页面状态：当前周次、每周数据与加载状态。
///
/// 网格里的课有两个来源，分开对待：
/// * **教务系统**抓回来的排课：**不落盘**，每周实时请求，内部 [Map] 只是本次会话的内存
///   数据，用来来回切周时不重复请求；换账号时整份作废（见 [_dropRemoteData]）。
/// * **用户自己添加的课程**（[CustomCourse]）：属于用户数据，**一直留在本机**
///   （见 [CustomCourseStore]），刷新课表、换账号、退出登录都不动它。
///
/// 另外持久化的还有账户信息（登录会话、学号、学生信息快照 —— 见 [JwStoredAccount]）
/// 与上课提醒设置，它们都由 `main()` 启动时读好后通过 `restored*` 参数传进来。
/// 两来源在 [sessionsOfWeek] 里合并，界面只看到一套 [CourseSession]。
///
/// 加载策略：
/// 1. 内存里已有该周 → 直接渲染，不发请求；
/// 2. 否则防抖后请求教务系统，成功后**顺便预取相邻周**。
///
/// 快速连续滑动时只会为最终停留的那一周发请求（防抖），同一周不会并发请求两次（去重）。
class ScheduleController extends ChangeNotifier {
  ScheduleController({
    AppSettings? settings,
    JwTimetableClient? client,
    JwTransport? transport,
    JwDetailedTransport? detailedTransport,
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
    this.swipeDebounce = const Duration(milliseconds: 220),
  }) : _settings = settings ?? AppSettings.initial(),
       _client =
           client ??
           JwTimetableClient(
             transport: transport,
             detailedTransport: detailedTransport,
             cookie: sessionCookieOf(restoredAccount),
           ),
       _store = accountStore ?? const PrefsAccountStore(),
       _savedAccount = restoredAccount,
       _notifier = reminderNotifier ?? createClassReminderNotifier(),
       _reminderStore = reminderStore ?? const PrefsReminderStore(),
       _reminderSettings = restoredReminder ?? const ClassReminderSettings(),
       _customCourseStore =
           customCourseStore ?? const PrefsCustomCourseStore(),
       _customCourses = List<CustomCourse>.of(
         restoredCustomCourses ?? const <CustomCourse>[],
       ),
       _keepAliveStore = keepAliveStore ?? const PrefsKeepAliveStore(),
       _keepAlivePlatform = keepAlivePlatform ?? createKeepAlivePlatform(),
       _keepAliveSettings = restoredKeepAlive ?? const KeepAliveSettings(),
       _widgetUpdater = widgetUpdater ?? createWidgetUpdater() {
    // 本机存过的账号先认下来：学生信息马上能显示，登录页也能回填学号
    // （密码只有用户勾过「记住密码」才有，同样只用来回填）。
    _savedAccountNumber = restoredAccount?.account ?? '';
    _savedPassword = restoredAccount?.password ?? '';
    _student = restoredAccount?.student;
    _studentFromStore = _student != null;

    _currentWeek = todayWeek;
    // 「空教室」默认查本周、今天（星期几直接用系统值，不受「当前显示第几周」影响）。
    _classroomQuery = JwClassroomQuery(
      week: _currentWeek,
      weekday: DateTime.now().weekday,
    );
    // 1) 先按教务系统主页面校准学期起止（权威周次），2) 同时拉当前周课表。
    unawaited(syncTermWithServer());
    _prepare(_currentWeek, immediate: true);
    // 3) 通知权限 + 把已有课表的提醒排上（课表到手后还会再排一次，见 [_fetch]）。
    unawaited(_bootstrapReminders());
    // 4) 查一遍电池优化白名单状态（只查不弹框），设置页的保活栏目好显示现状。
    unawaited(_bootstrapKeepAlive());
    // 5) 把自建课 / 上次会话剩下的数据先推给桌面小组件（课表拉回后还会再推）。
    _pushWidgetUpdate();
  }

  /// 启动时用的会话：`--dart-define=JW_COOKIE` > 本机保存的 > 空。
  ///
  /// 构建参数优先是为了本地调试 —— 显式传进来的值应该盖过磁盘上的旧会话；
  /// 两者都没有就返回 null，客户端会以「未登录」状态启动（这是正常状态，不是错误）。
  static String? sessionCookieOf(JwStoredAccount? saved) {
    if (jwCookie.trim().isNotEmpty) {
      return jwCookie;
    }
    final String stored = saved?.cookie.trim() ?? '';
    return stored.isEmpty ? null : stored;
  }

  /// 连续滑动换周时的防抖时长，避免为滑过的每一周都发请求。
  final Duration swipeDebounce;

  /// 滑停之后多久才去预取相邻周。
  static const Duration prefetchDelay = Duration(milliseconds: 300);

  /// 已持有的每周课表，键是**本地周次**。只活在本次会话里，不落盘。
  final Map<int, JwTimetable> _remote = <int, JwTimetable>{};

  /// 正在请求的周次。
  final Set<int> _loadingWeeks = <int>{};

  /// 已排入防抖队列、还没真正发请求的周次。
  final Set<int> _pendingWeeks = <int>{};

  final Map<int, String> _errors = <int, String>{};

  /// 每周的非致命提示（例如刷新失败但仍有旧数据），按周围维护，避免被其它周的请求覆盖。
  final Map<int, String> _notices = <int, String>{};

  final JwTimetableClient _client;
  AppSettings _settings;
  late int _currentWeek;
  Timer? _debounce;
  Timer? _prefetchDebounce;
  JwWeekInfo? _weekInfo;
  String? _weekInfoError;
  JwStudentInfo? _student;
  List<JwSelectionRound>? _selectionRounds;
  bool _selectionLoading = false;
  String? _selectionError;
  JwClassroomBoard? _classroomBoard;
  late JwClassroomQuery _classroomQuery;
  bool _classroomLoading = false;
  String? _classroomError;
  JwLoginSession? _loginSession;
  Uint8List? _captchaImage;
  bool _loginLoading = false;
  String? _loginError;

  /// 账户信息的本地存储。
  final JwAccountStore _store;

  /// 最近一次落盘的账户信息，用来判断「值没变就别再写一遍」。
  JwStoredAccount? _savedAccount;

  /// 登录页回填用的学号 / 账号。
  String _savedAccountNumber = '';

  /// 登录页回填用的密码；只在用户勾过「记住密码」时非空。
  String _savedPassword = '';

  /// 现在显示的学生信息是不是「本机保存的副本」（还没跟教务系统核对上）。
  bool _studentFromStore = false;

  /// 系统通知的投递口（Android/iOS/macOS 真发通知，Web 退化成不支持）。
  final ClassReminderNotifier _notifier;

  /// 上课提醒设置的本地存储。
  final ReminderStore _reminderStore;

  /// 上课提醒设置（开关 + 提前量）。
  ClassReminderSettings _reminderSettings;

  /// 自建课程的本地存储。
  final CustomCourseStore _customCourseStore;

  /// 用户自己添加的课程。
  ///
  /// 与 [_remote] 最大的区别是**跨会话保留**：增删改之后立刻整份写回 [_customCourseStore]，
  /// 冷启动由 `restoredCustomCourses` 还原。
  List<CustomCourse> _customCourses;

  /// 已经排给系统的提醒，按时间从近到远。只活在本次会话里，不落盘。
  List<ClassReminder> _reminders = const <ClassReminder>[];

  /// 当前有没有通知权限。**不代表排期成功** —— 没权限时提醒照样排，
  /// 只是系统不弹；界面要靠它如实提示用户去放行。
  bool _reminderPermission = false;

  /// 上一次真正下发给系统的排期签名。
  ///
  /// 课表每拉回一周都会触发一次重排，而一次重排要「清空 + 逐条排」几十次平台调用。
  /// 用签名比对把「内容没变的重排」挡掉，避免来回切周时反复折腾系统闹钟。
  String? _reminderSignature;

  /// 排期失败的原因（不影响课表，只是提醒没排上）。
  String? _reminderError;

  /// 正在下发排期；期间再来请求只标脏，等当前这轮跑完再补一轮。
  bool _reminderSyncing = false;
  bool _reminderDirty = false;

  /// 保活设置的本地存储。
  final KeepAliveStore _keepAliveStore;

  /// 保活要碰系统的口子（跳系统设置页、查/申请电池优化白名单）。
  final KeepAlivePlatform _keepAlivePlatform;

  /// 保活设置（目前只有开机自启意愿）。
  KeepAliveSettings _keepAliveSettings;

  /// 当前是否已在电池优化白名单里；null = 还没查到（启动后异步查一次）。
  bool? _ignoringBattery;

  /// 「下一节课」桌面小组件的投递口（Android 才有真实现，其余平台空操作）。
  final WidgetUpdater _widgetUpdater;

  /// 教务系统客户端（设置页展示状态用）。
  JwTimetableClient get client => _client;

  /// 当前周是否在加载（含防抖排队中）。
  bool get isLoading =>
      _loadingWeeks.contains(_currentWeek) ||
      _pendingWeeks.contains(_currentWeek);

  /// 当前周的致命错误（没有任何数据可显示时）。
  String? get error => _errors[_currentWeek];

  /// 非致命提示，例如「刷新失败，显示上次数据」。
  String? get notice => _notices[_currentWeek];

  /// 当前设置。
  AppSettings get settings => _settings;

  /// 学期设置。
  Term get term => _settings.term;

  /// 正在查看的周次。
  int get currentWeek => _currentWeek;

  /// 今天所在的周次，超出学期范围时钳制到 1 ~ [Term.totalWeeks]。
  int get todayWeek => _clampWeek(term.weekOf(DateTime.now()));

  /// 当前查看的是否就是本周。
  bool get isCurrentWeek => _currentWeek == todayWeek;

  /// 当前周要显示的日期列。
  List<ScheduleDay> get days =>
      term.daysOf(_currentWeek, includeWeekend: _settings.showWeekend);

  /// 今天的星期几；只有正在查看本周时才有意义。
  int? get todayWeekday => isCurrentWeek ? DateTime.now().weekday : null;

  /// 当前周的日期范围，例如「9/20 - 9/26」。
  String get currentWeekRange => term.rangeLabelOf(_currentWeek);

  /// 当前要显示的排课。
  List<CourseSession> get sessions => sessionsOfWeek(_currentWeek);

  /// 用户自己添加的课程（按添加顺序）。只读，改它请走 [addCustomCourse] 等方法。
  List<CustomCourse> get customCourses =>
      List<CustomCourse>.unmodifiable(_customCourses);

  /// 按 id 找一条自建课程；不是自建的（或已经被删掉）返回 null。
  CustomCourse? customCourseById(String? id) {
    if (id == null) {
      return null;
    }
    for (final CustomCourse course in _customCourses) {
      if (course.id == id) {
        return course;
      }
    }
    return null;
  }

  /// 第 [week] 周要显示的排课：教务系统抓回来的 + 用户自己添加的。
  ///
  /// 两个来源在这里合流，界面只认一套 [CourseSession]；自建课程都带着
  /// [CourseSession.customId]，所以卡片被点上时界面能认出「这条能改能删」。
  List<CourseSession> sessionsOfWeek(int week) => <CourseSession>[
    ...?_remote[week]?.sessions,
    ..._customSessionsIn(week),
  ];

  /// 第 [week] 周生效的自建课程，转成网格能画的排课。
  List<CourseSession> _customSessionsIn(int week) => <CourseSession>[
    for (final CustomCourse course in _customCourses)
      if (course.isActiveInWeek(week)) course.toSession(),
  ];

  /// 教务系统为第 [week] 周返回的周次（用于发现两边周次对不上的情况）。
  int? serverWeekOf(int week) => _remote[week]?.week;

  /// 教务系统主页面给出的「当前第几周」（按周一到周日）。
  int? get serverCurrentWeek => _weekInfo?.week;

  /// 主页面读到的总周数。
  int? get serverTotalWeeks => _weekInfo?.totalWeeks;

  /// 读取主页面周次失败时的原因（非致命，本地推算仍可用）。
  String? get weekInfoError => _weekInfoError;

  /// 学生基本信息（和当前周次来自同一个主页面响应，不额外发请求）。
  JwStudentInfo? get student => _student;

  /// 登录页要回填的学号 / 账号（本机保存的；没存过就是空串）。
  String get savedAccount => _savedAccountNumber;

  /// 登录页要回填的密码（用户勾过「记住密码」才有；否则空串）。
  String get savedPassword => _savedPassword;

  /// 本机有没有存过账户信息（决定「我的信息」页要不要给「退出登录」入口）。
  bool get hasSavedAccount =>
      _savedAccountNumber.trim().isNotEmpty || _client.hasCookie;

  /// 现在显示的学生信息是不是「本机保存的副本」（还没跟教务系统核对上）。
  ///
  /// 会话可能已经失效，所以界面得说清这份信息是从哪来的。
  bool get studentFromStore => _studentFromStore;

  /// 选课中心轮次；null 表示还没读过。
  List<JwSelectionRound>? get selectionRounds => _selectionRounds;

  /// 是否正在读取选课中心。
  bool get selectionLoading => _selectionLoading;

  /// 读取选课中心失败的原因。
  String? get selectionError => _selectionError;

  /// 教室空余查询结果；null 表示还没查过。
  JwClassroomBoard? get classroomBoard => _classroomBoard;

  /// 教室空余查询的查询条件（周次 / 星期 / 校区 / 教学楼）。
  JwClassroomQuery get classroomQuery => _classroomQuery;

  /// 是否正在查询教室空余情况。
  bool get classroomLoading => _classroomLoading;

  /// 教室空余查询失败的原因。
  String? get classroomError => _classroomError;

  /// 登录验证码图片（JPEG）；null 表示还没取到或已作废。
  Uint8List? get captchaImage => _captchaImage;

  /// 是否正在取验证码或提交登录。
  bool get loginLoading => _loginLoading;

  /// 上一次登录失败的原因（成功后会清空）。
  String? get loginError => _loginError;

  /// 取一张新的登录验证码（进入登录页 / 换一张 / 上次失败后自动重来都走这里）。
  ///
  /// 验证码是**一次性的**：服务端校验完就作废，所以每次提交前都必须有一张刚取的。
  /// 它**不负责清 [_loginError]** —— 由调用方决定：[startLogin] 先清掉（用户主动重来），
  /// 而登录失败后自动换图那条路要**留着**失败原因继续给用户看。
  Future<void> _fetchCaptcha() async {
    if (_loginLoading) {
      return;
    }
    _loginLoading = true;
    _captchaImage = null;
    notifyListeners();

    try {
      final JwLoginSession session = await _client.beginLogin();
      _loginSession = session;
      _captchaImage = session.image;
    } on JwException catch (error) {
      _loginSession = null;
      // 已经有失败原因时**不要覆盖**：「密码错了」比「验证码没取到」更是用户要看的那条；
      // 验证码位会退化成「点此获取」，用户点一下就能重试。
      _loginError ??= error.message;
    } catch (error) {
      _loginSession = null;
      _loginError ??= '获取验证码失败：$error';
    } finally {
      _loginLoading = false;
      notifyListeners();
    }
  }

  /// 取一张新验证码，并清掉上一次的失败提示。
  Future<void> startLogin() async {
    _loginError = null;
    await _fetchCaptcha();
  }

  /// 提交账号、密码与验证码。
  ///
  /// 成功返回 true，并**替换掉本次会话**：内存里的课表属于上一个会话，全部作废后
  /// 按新账号重新拉一遍；同时把新会话与账号存到本机（下次打开就不用再登一次）。
  ///
  /// [rememberPassword] 为 true 时把密码也一并落盘（登录页免输一遍）；false 则
  /// **主动抹掉**之前存过的密码 —— 用户取消勾选的心意要立刻生效。
  ///
  /// **失败后会顺手换一张新验证码**（返回时已经取好），见下面的注释。
  Future<bool> submitLogin({
    required String account,
    required String password,
    required String captcha,
    bool rememberPassword = false,
  }) async {
    final JwLoginSession? session = _loginSession;
    if (session == null) {
      _loginError = '验证码已作废，请重新获取';
      notifyListeners();
      // 手上没有可用验证码（从没取到，或取的时候失败了），直接补一张。
      await _fetchCaptcha();
      return false;
    }
    if (_loginLoading) {
      return false;
    }
    _loginLoading = true;
    _loginError = null;
    notifyListeners();

    var ok = false;
    try {
      final JwMainPageInfo page = await _client.login(
        session,
        account: account,
        password: password,
        captcha: captcha,
      );
      _adoptMainPage(page);
      _dropRemoteData();
      // 会话已经换成新的了，存到本机：下次打开就不用再登一次。
      // 密码听用户当次的勾选：勾了才存，没勾就抹掉旧的。
      await _rememberAccount(
        account: account,
        student: page.student,
        password: rememberPassword ? password : '',
      );
      notifyListeners();
      await _fetch(_currentWeek, force: true);
      ok = true;
    } on JwException catch (error) {
      _loginError = error.message;
    } catch (error) {
      _loginError = '登录失败：$error';
    } finally {
      _loginLoading = false;
      // 不管成败，那张验证码都不能再用了。
      _loginSession = null;
      _captchaImage = null;
      notifyListeners();
    }
    if (!ok) {
      // **失败后自动换一张**：验证码是一次性的，服务端校验过那张图就作废了。不换的话
      // 用户改完密码再点「登录」，提交的还是那张死图，服务端只会再报一次「验证码错误」，
      // 很容易被误判成「密码怎么改都不对」。
      // 失败原因留在 [_loginError] 里继续显示（`_fetchCaptcha` 不会覆盖它）；
      // 这里 await 是故意的 —— 新图没到位之前按钮保持「请稍候…」，
      // 顺手挡住了「拿旧验证码再提交一次」这种注定失败的操作。
      await _fetchCaptcha();
    }
    return ok;
  }

  /// 上课提醒的设置（开关 + 提前多久）。
  ClassReminderSettings get reminderSettings => _reminderSettings;

  /// 已经排给系统的提醒，按时间从近到远；空表示这段时间没有要提醒的课。
  List<ClassReminder> get reminders => _reminders;

  /// 最近一条提醒；没有待提醒的课就是 null。
  ClassReminder? get nextReminder =>
      _reminders.isEmpty ? null : _reminders.first;

  /// 当前平台支不支持**系统级**定时通知（Web 上不支持）。
  bool get reminderSupported => _notifier.isSupported;

  /// 有没有通知权限。
  ///
  /// 为 false 时提醒**照样会排**，只是系统不弹 —— 界面得如实说明，并给一个去系统设置
  /// 放行的入口。
  bool get reminderPermissionGranted => _reminderPermission;

  /// 排期失败的原因（不影响课表，只是提醒没排上）。
  String? get reminderError => _reminderError;

  /// 冷启动时把提醒准备起来：查权限（必要时申请一次）+ 按已存设置排期。
  ///
  /// 为什么在冷启动就申请权限：课表 App 的提醒是核心功能，默认开着却要用户自己翻到设置页
  /// 打开一次才算数，等于默认没开。Android 13+ 的权限框只在「用户还没决定过」时真弹，
  /// 拒绝过之后系统自己记住，不会再每次打开都烦人。
  Future<void> _bootstrapReminders() async {
    if (!_notifier.isSupported) {
      notifyListeners();
      return;
    }
    try {
      bool granted = await _notifier.permissionGranted();
      if (!granted && _reminderSettings.enabled) {
        granted = await _notifier.requestPermission();
      }
      _reminderPermission = granted;
    } catch (error) {
      _reminderError = '申请通知权限失败：$error';
    }
    notifyListeners();
    await _syncReminders();
  }

  /// 重新查一遍通知权限状态（**不弹窗**）。
  ///
  /// 用户可能刚从系统设置里放行或关掉通知，回到 App 得能反映出来。
  Future<void> refreshReminderPermission() async {
    if (!_notifier.isSupported) {
      return;
    }
    try {
      _reminderPermission = await _notifier.permissionGranted();
    } catch (error) {
      debugPrint('读取通知权限状态失败：$error');
    }
    notifyListeners();
  }

  /// 用户手动打开提醒开关时调用：申请权限，拿到就立刻排期。
  Future<bool> requestReminderPermission() async {
    if (!_notifier.isSupported) {
      return false;
    }
    bool granted = false;
    try {
      granted = await _notifier.requestPermission();
    } catch (error) {
      _reminderError = '申请通知权限失败：$error';
    }
    _reminderPermission = granted;
    notifyListeners();
    if (granted) {
      await _syncReminders();
    }
    return granted;
  }

  /// 跳去系统的通知设置页（用户手动放行时用）。
  Future<bool> openReminderSystemSettings() =>
      _notifier.openNotificationSettings();

  /// 当前保活设置。
  KeepAliveSettings get keepAliveSettings => _keepAliveSettings;

  /// 当前平台有没有系统级「保活」概念（Web 上没有，界面要如实说明）。
  bool get keepAliveSupported => _keepAlivePlatform.isSupported;

  /// 当前是否已在电池优化白名单里；null = 还没查到。
  bool? get ignoringBatteryOptimizations => _ignoringBattery;

  /// 启动时查一遍电池优化白名单状态（只查，不弹任何框）。
  Future<void> _bootstrapKeepAlive() async {
    if (!_keepAlivePlatform.isSupported) {
      return;
    }
    await refreshBatteryOptimizationStatus();
  }

  /// 重新查一遍电池优化白名单状态。
  ///
  /// 用户可能刚从系统设置里放行或收回，回到 App 得能反映出来。
  Future<void> refreshBatteryOptimizationStatus() async {
    if (!_keepAlivePlatform.isSupported) {
      return;
    }
    _ignoringBattery = await _keepAlivePlatform.isIgnoringBatteryOptimizations();
    notifyListeners();
  }

  /// 改保活设置（目前只有开机自启意愿），改动立刻落盘。
  Future<void> updateKeepAliveSettings(KeepAliveSettings next) async {
    if (next == _keepAliveSettings) {
      return;
    }
    _keepAliveSettings = next;
    notifyListeners();
    await _keepAliveStore.write(next);
  }

  /// 打开「申请忽略电池优化」的系统确认框，返回用户是否已放行。
  ///
  /// 部分机型不让直接弹框，会退化成打开列表页 —— 那种情况返回 false，
  /// 由界面引导用户去列表里手动放行；无论走哪条路，回来后状态都会刷新。
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_keepAlivePlatform.isSupported) {
      return false;
    }
    final bool granted = await _keepAlivePlatform
        .requestIgnoreBatteryOptimizations();
    await refreshBatteryOptimizationStatus();
    return granted;
  }

  /// 打开电池优化列表页（用户手动放行用）。
  Future<bool> openBatteryOptimizationSettings() =>
      _keepAlivePlatform.openBatteryOptimizationSettings();

  /// 尝试打开「自启动管理」页；国产 ROM 逐个试已知入口，失败退回应用详情页。
  Future<bool> openAutoStartSettings() =>
      _keepAlivePlatform.openAutoStartSettings();

  /// 打开系统的应用详情页（万能兜底）。
  Future<bool> openAppDetailsSettings() =>
      _keepAlivePlatform.openAppDetailsSettings();

  /// 强制重排一次。
  ///
  /// 给「排期失败」的提示卡片当动作按钮用：清掉签名让它**真的**再下发一遍，
  /// 而不是因为「内容和上次一样」而被跳过。
  Future<void> resyncReminders() async {
    _reminderSignature = null;
    await _syncReminders();
  }

  /// 把「接下来要上的课」推给桌面小组件。
  ///
  /// 覆盖接下来 3 天（含今天），学期外或没课就是空列表 —— 原生会显示
  /// 「没有课了可以放心玩了！」。实现内部吞掉一切错误，失败维持旧显示。
  void _pushWidgetUpdate() {
    if (!_widgetUpdater.isSupported) {
      return;
    }
    final List<NextClassEntry> entries = buildNextClassEntries(
      term: term,
      sessionsOf: sessionsOfWeek,
      now: DateTime.now(),
    );
    unawaited(() async {
      try {
        await _widgetUpdater.update(entries);
      } catch (error) {
        // 小组件维持旧显示就行，别让异常冒出去。
        debugPrint('更新桌面小组件失败：$error');
      }
    }());
  }

  /// 改上课提醒设置。
  ///
  /// 关掉时**立刻清掉已排的提醒** —— 不能等下次重排，否则用户关了开关还会被提醒。
  /// 开着时按新的提前量重排。设置本身落盘，下次打开还记得。
  Future<void> updateReminderSettings(ClassReminderSettings next) async {
    if (next == _reminderSettings) {
      return;
    }
    _reminderSettings = next;
    _reminderError = null;
    notifyListeners();
    await _reminderStore.write(next);

    if (!next.enabled) {
      _reminders = const <ClassReminder>[];
      _reminderSignature = null;
      notifyListeners();
      await _notifier.cancelAll();
      return;
    }
    await _syncReminders();
  }

  /// 按当前手里的课表重排提醒。重复调用是安全的。
  ///
  /// 排期内容没变就**不碰系统闹钟**（见 [_reminderSignature]）：课表每拉回一周都会触发
  /// 一次重排，一次重排要「先清空再逐条排」几十次平台调用，来回切周时白白折腾。
  Future<void> _syncReminders() async {
    if (!_notifier.isSupported || !_reminderSettings.enabled) {
      return;
    }
    if (_reminderSyncing) {
      _reminderDirty = true; // 这轮跑完再补一轮，别把请求丢了
      return;
    }
    _reminderSyncing = true;
    try {
      do {
        _reminderDirty = false;
        await _applyReminders();
      } while (_reminderDirty);
    } finally {
      _reminderSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _applyReminders() async {
    // 手里有多少周就排多少周：课表不落盘，冷启动只有「当前周 + 相邻周」（见 _prefetchNeighbours）。
    final Map<int, List<CourseSession>> byWeek = <int, List<CourseSession>>{};
    for (final MapEntry<int, JwTimetable> entry in _remote.entries) {
      byWeek[entry.key] = <CourseSession>[...entry.value.sessions];
    }
    // 自建课程不挂在某一周上，它自带「第 X-Y 周」区间，所以按覆盖到的每周摊开。
    // 这样即使一门教务课都没拉到（没登录 / 断网），自己加的课也照样有提醒；
    // 摊到学期外的周由 planner 自己裁掉（它按 [reminderHorizon] 过滤）。
    for (final CustomCourse course in _customCourses) {
      for (int week = course.startWeek; week <= course.endWeek; week++) {
        byWeek.putIfAbsent(week, () => <CourseSession>[]).add(course.toSession());
      }
    }
    final List<ClassReminder> planned = planClassReminders(
      term: term,
      sessionsByWeek: byWeek,
      settings: _reminderSettings,
      now: DateTime.now(),
    );

    final String signature = _signatureOf(planned);
    _reminders = planned;
    if (signature == _reminderSignature) {
      return; // 和上一轮完全一样，没必要再折腾一遍系统闹钟
    }

    try {
      await _notifier.sync(planned);
      _reminderSignature = signature;
      _reminderError = null;
    } catch (error) {
      _reminderError = '安排上课提醒失败：$error';
    }
  }

  /// 排期签名：把「提醒在什么时刻、要说什么」压成一串，用来判断有没有真的变化。
  ///
  /// 带上标题和正文是因为**同一格可能换了课**（教务系统改课名/换教室），
  /// 那种情况下时刻没变，但通知内容得跟着更新。
  static String _signatureOf(List<ClassReminder> reminders) => <String>[
    for (final ClassReminder item in reminders)
      '${item.id}@${item.at.millisecondsSinceEpoch}:${item.title}|${item.body}',
  ].join('\n');

  /// 换账号后「教务侧」的数据全部作废（课表、选课轮次、教室占用、上课提醒都可能不一样了）。
  ///
  /// **自建课程不在此列**：那是用户自己敲进去的数据，换个账号登录不该把它清掉。
  void _dropRemoteData() {
    _remote.clear();
    _notices.clear();
    _errors.clear();
    _loadingWeeks.clear();
    _pendingWeeks.clear();
    _selectionRounds = null;
    _selectionError = null;
    _classroomBoard = null;
    _classroomError = null;
    // 提醒跟着课表走：课表作废了，已排的提醒也不能再用。新会话的课表拉回来之后，
    // [_fetch] 会按新内容重排一遍。
    _reminders = const <ClassReminder>[];
    _reminderSignature = null;
    // 小组件同步降级：教务课没了，只剩自建课（或干脆显示「没有课了」）。
    _pushWidgetUpdate();
  }

  /// 把当前会话与账户信息写到本机。
  ///
  /// 两处调用：**登录成功**（换了一份新会话）与**读到主页面**（会话可能被服务端轮换、
  /// 学生信息可能变）。值没变时不重复写盘。
  ///
  /// 存储出错只记日志：写不进去的后果只是「下次要重新登录」，不该把它算成登录失败
  /// （[submitLogin] 会 await 这里）。传 [student] 是为了明确「这次读到的是什么」——
  /// 登录换账号后即使一个字段都没解析到，也要把上一位同学的名字覆盖掉。
  ///
  /// [password] 只在用户勾选「记住密码」时非空；空串表示「不存 / 抹掉」。
  Future<void> _rememberAccount({
    String? account,
    JwStudentInfo? student,
    String? password,
  }) async {
    final String cookie = _client.cookie.trim();
    if (cookie.isEmpty) {
      return; // 没有会话就没什么可记的
    }
    final String nextPassword = password ?? _savedPassword;
    final JwStoredAccount next = JwStoredAccount(
      cookie: cookie,
      account: account ?? _savedAccountNumber,
      password: nextPassword,
      student: student ?? _student,
      savedAt: DateTime.now(),
    );
    if (next.sameContentAs(_savedAccount)) {
      return;
    }
    _savedAccount = next;
    _savedAccountNumber = next.account;
    _savedPassword = next.password;
    try {
      await _store.write(next);
    } catch (error) {
      debugPrint('保存账户信息失败：$error');
    }
  }

  /// 退出登录：清掉本机保存的账户信息，并把课表退回「未登录」状态。
  ///
  /// 只动本机 —— 会话在教务系统那一侧，这里没有可靠的登出接口可调，所以不假装通知了
  /// 服务端（让它自己超时）。清完立刻重取一次课表：没有会话时教务系统会把请求打回
  /// 登录页，正好得到与「未登录冷启动」一模一样的提示。
  Future<void> signOut() async {
    try {
      await _store.clear();
    } catch (error) {
      debugPrint('清除账户信息失败：$error');
    }
    _savedAccount = null;
    _savedAccountNumber = '';
    _savedPassword = '';
    _student = null;
    _studentFromStore = false;
    _weekInfo = null;
    _weekInfoError = null;
    _dropRemoteData();
    // `--dart-define` 注入的会话来自构建参数、不属于用户，保留；其它情况彻底清空。
    _client.cookie = jwCookie;
    notifyListeners();
    await _fetch(_currentWeek, force: true);
  }

  /// 读取学生选课中心的轮次列表（只读，不提交任何选课）。
  Future<void> loadSelectionRounds({bool force = false}) async {
    if (_selectionLoading) {
      return;
    }
    if (_selectionRounds != null && !force) {
      return; // 本次会话已经读过
    }

    _selectionLoading = true;
    _selectionError = null;
    notifyListeners();

    try {
      _selectionRounds = await _client.fetchSelectionRounds();
    } on JwException catch (error) {
      _selectionError = error.message;
    } catch (error) {
      _selectionError = '读取选课中心失败：$error';
    } finally {
      _selectionLoading = false;
      notifyListeners();
    }
  }

  /// 进入「空教室」页时调用：本次会话还没查过才联网。
  Future<void> ensureClassroomBoard() => loadClassroomBoard();

  /// 查询教室空余情况（只读，不预约任何教室）。
  ///
  /// 结果**不落盘**：教室占用每周都在变，留一份旧数据比没有更危险。
  Future<void> loadClassroomBoard({bool force = false}) async {
    if (_classroomLoading) {
      return;
    }
    if (_classroomBoard != null && !force) {
      return; // 本次会话已经查过，直接显示
    }

    _classroomLoading = true;
    _classroomError = null;
    notifyListeners();

    try {
      _classroomBoard = await _client.fetchClassroomBoard(
        campusId: _classroomQuery.campusId,
        buildingId: _classroomQuery.buildingId,
        week: _classroomQuery.week,
        weekday: _classroomQuery.weekday,
      );
    } on JwException catch (error) {
      _classroomError = error.message;
    } catch (error) {
      _classroomError = '查询教室空余情况失败：$error';
    } finally {
      _classroomLoading = false;
      notifyListeners();
    }
  }

  /// 改查询条件。
  ///
  /// 只有 **周次 / 星期 / 校区 / 教学楼** 变了才重新联网（见 [JwClassroomQuery]）；
  /// 条件没变就什么都不做。切换时会先清掉旧结果，免得上一栋教学楼的教室和新条件混在一起。
  Future<void> updateClassroomQuery(JwClassroomQuery next) async {
    final bool changed = !next.sameRequestAs(_classroomQuery);
    _classroomQuery = next;
    if (!changed) {
      notifyListeners();
      return;
    }
    _classroomBoard = null;
    _classroomError = null;
    notifyListeners();
    await loadClassroomBoard(force: true);
  }

  /// 从教务系统主页面读取「当前第几周 / 总周数 / 学生信息」，并据此校准学期起止。
  ///
  /// 主页面给的是**周一到周日**口径的当前周；本应用按设计稿是**周日到周六**，
  /// 两者对周一到周六是同一个周次编号，所以用主页面反推「第 1 周周日」：
  /// `开学日期 = 本周周一 - (教务系统周次 - 1) * 7 - 1 天`。
  /// 这样即使本地兜底的开学日期过期（换学期），也能自动纠正。
  ///
  /// 读通了说明会话是有效的，顺手把会话与学生信息更新到本机（见 [_rememberAccount]）。
  Future<void> syncTermWithServer() async {
    try {
      final JwMainPageInfo page = await _client.fetchMainPage();
      final bool moved = _adoptMainPage(page);
      notifyListeners();

      // 读到主页面说明会话能用；会话可能被服务端轮换过，学生信息也可能变。
      await _rememberAccount(student: page.student);

      // 校准后这一周对应的日期变了（说明之前学期设置是错的），需要重新取一次。
      if (moved) {
        _pendingWeeks.remove(_currentWeek);
        _prepare(_currentWeek, immediate: true);
      }
    } on JwException catch (error) {
      _weekInfoError = error.message;
      notifyListeners();
    } catch (error) {
      _weekInfoError = '读取教务系统周次失败：$error';
      notifyListeners();
    }
  }

  /// 采用主页面信息：学生信息 + 按教务系统周次反推学期起止。
  ///
  /// 返回**当前这一周对应的日期是否因此变了** —— 变了说明之前本地学期设置是错的，
  /// 已有的课表数据对不上号，调用方要重取（[syncTermWithServer] 与登录流程都靠这个信号）。
  bool _adoptMainPage(JwMainPageInfo page) {
    final JwWeekInfo info = page.week;
    _weekInfo = info;
    _student = page.student;
    // 读到权威值了，本机那份快照就不用再挂「可能过期」的说明。
    _studentFromStore = false;
    _weekInfoError = null;

    final DateTime beforeStart = term.startOfWeek(_currentWeek);
    final bool wasCurrentWeek = isCurrentWeek;
    final DateTime monday = JwTimetableClient.mondayOf(DateTime.now());
    _settings = _settings.copyWith(
      term: term.copyWith(
        startDate: monday.subtract(Duration(days: (info.week - 1) * 7 + 1)),
        totalWeeks: info.totalWeeks,
      ),
    );
    _currentWeek = wasCurrentWeek ? todayWeek : _clampWeek(_currentWeek);
    return term.startOfWeek(_currentWeek) != beforeStart;
  }

  /// 这一周能不能画出网格：教务数据到了，或者手里有这一周的自建课程。
  ///
  /// 后半个条件不能少 —— 用户完全可以一门教务课都没拉到（没登录 / 断网 / 教务系统挂了），
  /// 只靠自己加的课把课表填起来，那种情况下网格必须照画。
  bool get isReady =>
      _remote.containsKey(_currentWeek) ||
      _customSessionsIn(_currentWeek).isNotEmpty;

  /// [weekday] 这一天在当前周要显示的排课，按开始节次排序。
  List<CourseSession> sessionsOf(int weekday) =>
      sessions.where((CourseSession s) => s.weekday == weekday).toList()..sort(
        (CourseSession a, CourseSession b) =>
            a.startPeriod.compareTo(b.startPeriod),
      );

  /// 第 [week] 周的上课节次占用的节数。
  int weeklyPeriodCount(int week) =>
      sessionsOfWeek(week)
          .where((CourseSession s) => s.isActiveInWeek(week))
          .fold(0, (int sum, CourseSession s) => sum + s.periodCount);

  /// 切换到第 [week] 周：内存里有就直接渲染，没有才联网。
  void goToWeek(int week) {
    final int next = _clampWeek(week);
    if (next == _currentWeek) {
      return;
    }
    _currentWeek = next;
    notifyListeners();
    _prepare(next);
  }

  /// 上一周。
  void previousWeek() => goToWeek(_currentWeek - 1);

  /// 下一周。
  void nextWeek() => goToWeek(_currentWeek + 1);

  /// 回到本周。
  void backToCurrentWeek() => goToWeek(todayWeek);

  /// 更新设置。
  void updateSettings(AppSettings settings) {
    _settings = settings;
    _currentWeek = _clampWeek(_currentWeek);
    notifyListeners();
    // 开学日期变了意味着每节课的**日期**都变了，已排的提醒得跟着挪；总周数变了则可能
    // 让某些周落回学期外。轻量调用，签名没变就不会真的碰系统闹钟。
    unawaited(_syncReminders());
    // 学期设置变了（含开学日期平移），小组件的日期映射也要跟着重算。
    _pushWidgetUpdate();
  }

  /// 开学日期整体平移 [days] 天。
  void shiftTermStart(int days) => updateSettings(
    _settings.copyWith(
      term: term.copyWith(startDate: term.startDate.add(Duration(days: days))),
    ),
  );

  /// 新建一门自建课程；名字是空的就什么都不做（返回 null）。
  ///
  /// 越界的星期 / 节次 / 周次会被钳制，起止给反了会自动摆正 —— 界面已经挡过一道，
  /// 这里是第二道：坏数据一旦落盘，之后每次冷启动都要陪着它。
  Future<CustomCourse?> addCustomCourse({
    required String name,
    required int weekday,
    required int startPeriod,
    required int endPeriod,
    required int startWeek,
    required int endWeek,
    String location = '',
    String teacher = '',
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final List<int> periods = _orderedRange(
      startPeriod,
      endPeriod,
      CustomCourse.minPeriod,
      CustomCourse.maxPeriod,
    );
    final List<int> weeks = _orderedRange(
      startWeek,
      endWeek,
      CustomCourse.minWeek,
      CustomCourse.maxWeek,
    );

    final CustomCourse course = CustomCourse(
      id: _nextCustomId(),
      name: trimmed,
      weekday: _clampInt(weekday, DateTime.monday, DateTime.sunday),
      startPeriod: periods[0],
      endPeriod: periods[1],
      startWeek: weeks[0],
      endWeek: weeks[1],
      location: location.trim(),
      teacher: teacher.trim(),
    );

    _customCourses = <CustomCourse>[..._customCourses, course];
    notifyListeners();
    await _persistCustomCourses();
    return course;
  }

  /// 改一门自建课程。id 对不上（已经被删了）就什么都不做。
  Future<void> updateCustomCourse(CustomCourse next) async {
    final int index = _customCourses.indexWhere(
      (CustomCourse course) => course.id == next.id,
    );
    if (index < 0 || _customCourses[index] == next) {
      return;
    }
    final List<CustomCourse> updated = List<CustomCourse>.of(_customCourses);
    updated[index] = next;
    _customCourses = updated;
    notifyListeners();
    await _persistCustomCourses();
  }

  /// 删掉一门自建课程。
  Future<void> removeCustomCourse(String id) async {
    final List<CustomCourse> remaining = <CustomCourse>[
      for (final CustomCourse course in _customCourses)
        if (course.id != id) course,
    ];
    if (remaining.length == _customCourses.length) {
      return; // 没有这门课，不必惊动界面和磁盘
    }
    _customCourses = remaining;
    notifyListeners();
    await _persistCustomCourses();
  }

  /// 自建课程改完之后的收尾：写回本机 + 重排上课提醒。
  ///
  /// 两件事绑在一起：用户自己加的课也是课，上课前同样该被提醒；而写盘失败不该拦住
  /// 排期（这次的会话里课表已经变了），所以 `CustomCourseStore.write` 自己吞异常。
  Future<void> _persistCustomCourses() async {
    await _customCourseStore.write(_customCourses);
    await _syncReminders();
    _pushWidgetUpdate();
  }

  /// 生成一个新的自建课程 id：时间戳的 36 进制；万一撞上（同一微秒建了两门）就往后挪。
  String _nextCustomId() {
    var stamp = DateTime.now().microsecondsSinceEpoch;
    var id = 'c${stamp.toRadixString(36)}';
    while (_customCourses.any((CustomCourse course) => course.id == id)) {
      stamp += 1;
      id = 'c${stamp.toRadixString(36)}';
    }
    return id;
  }

  /// 把两个端点钳制到 `[min, max]` 并保证「小的在前」，返回 `[起, 止]`。
  static List<int> _orderedRange(int from, int to, int min, int max) {
    int start = _clampInt(from, min, max);
    int end = _clampInt(to, min, max);
    if (start > end) {
      final int swap = start;
      start = end;
      end = swap;
    }
    return <int>[start, end];
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) {
      return min;
    }
    return value > max ? max : value;
  }

  /// 强制重新拉取当前周。
  Future<void> refresh() async {
    _debounce?.cancel();
    _pendingWeeks.remove(_currentWeek);
    await _fetch(_currentWeek, force: true);
  }

  /// 是否已经销毁。
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _prefetchDebounce?.cancel();
    super.dispose();
  }

  /// [notifyListeners] 的防撞版本。
  ///
  /// 联网请求和上课提醒排期都是异步的，可能在页面已经销毁之后才回来。直接在已 dispose
  /// 的对象上通知会抛「A ScheduleController was used after being disposed」，
  /// 把一次「结果回来得太晚」升级成崩溃。晚到的结果丢掉就好。
  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  /// 取数据：内存里已有直接用，否则（防抖后）请求教务系统。
  void _prepare(int week, {bool immediate = false}) {
    if (_remote.containsKey(week)) {
      // 本次会话已经拿到过这一周，直接用；顺手把相邻周也热起来。
      if (week == _currentWeek) {
        _schedulePrefetch(week);
      }
      return;
    }
    _scheduleFetch(week, immediate: immediate);
  }

  /// 滑停之后再预取相邻周：滑动过程中不会顺手发请求。
  void _schedulePrefetch(int week) {
    _prefetchDebounce?.cancel();
    _prefetchDebounce = Timer(prefetchDelay, () {
      if (week != _currentWeek) {
        return; // 用户已经滑走了
      }
      unawaited(_prefetchNeighbours(week));
    });
  }

  void _scheduleFetch(int week, {bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      unawaited(_fetch(week));
      return;
    }
    // 防抖：滑动过程中只为最终停留的周发一次请求。
    _pendingWeeks.add(week);
    notifyListeners();
    _debounce = Timer(swipeDebounce, () {
      _pendingWeeks.remove(week);
      unawaited(_fetch(week));
    });
  }

  Future<void> _fetch(int week, {bool force = false}) async {
    if (_loadingWeeks.contains(week)) {
      return; // 同一周不并发重复请求
    }
    if (!force && _remote.containsKey(week)) {
      return; // 本次会话已经拿到过
    }

    _loadingWeeks.add(week);
    _pendingWeeks.remove(week);
    _errors.remove(week);
    _notices.remove(week);
    notifyListeners();

    try {
      final JwTimetable timetable = await _client.fetchWeekByZc(week);
      // 教务系统是按周次筛的，返回的课这一周一定上；但它给的周次区间可能是
      // 「4-18 周」这种（甚至带单双周），本地按「至少包含这一周」兜一下，
      // 免得解析出的区间把课判成「本周不上」而变灰。
      _remote[week] = JwTimetable(
        week: timetable.week,
        sessions: <CourseSession>[
          for (final CourseSession session in timetable.sessions)
            session.copyWith(
              startWeek: session.startWeek < week ? session.startWeek : week,
              endWeek: session.endWeek > week ? session.endWeek : week,
            ),
        ],
      );
    } catch (error) {
      final String message = error is JwException
          ? error.message
          : '获取课表失败：$error';
      if (_remote.containsKey(week)) {
        // 有旧数据时降级成提示，不把已有课表清空。
        _notices[week] = '刷新失败，显示上次数据 · $message';
      } else {
        _errors[week] = message;
      }
    } finally {
      _loadingWeeks.remove(week);
      notifyListeners();
      if (!_errors.containsKey(week) && week == _currentWeek) {
        _schedulePrefetch(week);
      }
      // 每拿到一周课表就重排一次提醒：新的一周可能有课要提醒，旧的那一周也可能已经
      // 过去了。签名没变时这里不会真的碰系统闹钟（见 [_syncReminders]），
      // 所以即使请求失败、手里的课表没动，也只是空跑一趟。
      unawaited(_syncReminders());
      _pushWidgetUpdate();
    }
  }

  /// 预取相邻周，让左右滑动「秒开」。
  Future<void> _prefetchNeighbours(int week) async {
    for (final int neighbour in <int>[week - 1, week + 1]) {
      if (neighbour < 1 || neighbour > term.totalWeeks) {
        continue;
      }
      if (_remote.containsKey(neighbour) || _loadingWeeks.contains(neighbour)) {
        continue;
      }
      if (_loadingWeeks.length >= 2) {
        return; // 限制并发，别为了预取把带宽占满
      }
      unawaited(_fetch(neighbour));
    }
  }

  int _clampWeek(int week) {
    if (week < 1) {
      return 1;
    }
    final int last = term.totalWeeks;
    return week > last ? last : week;
  }
}

/// 把 [ScheduleController] 提供给整棵组件树。
class ScheduleScope extends InheritedNotifier<ScheduleController> {
  const ScheduleScope({
    required ScheduleController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// 读取最近的 [ScheduleController]，并在其变化时重建调用方。
  static ScheduleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ScheduleScope>();
    assert(scope != null, '找不到 ScheduleScope，请在根部包一层 ScheduleScope。');
    return scope!.notifier!;
  }
}

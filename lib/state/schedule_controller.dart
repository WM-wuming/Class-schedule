import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/class_notifier.dart';
import '../data/captcha_recognizer.dart';
import '../data/custom_course_store.dart';
import '../data/jw_account_store.dart';
import '../data/jw_client.dart';
import '../data/jw_credentials.dart';
import '../data/jw_exception.dart';
import '../data/jw_http.dart';
import '../data/jw_login.dart';
import '../data/keep_alive_platform.dart';
import '../data/keep_alive_store.dart';
import '../data/reminder_ring_platform.dart';
import '../data/reminder_store.dart';
import '../data/timetable_cache.dart';
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
/// * **教务系统**抓回来的排课：用课表接口逐周拉取后**整学期合并成 JSON 快照落盘**
///   （见 [TimetableCacheStore]）。冷启动先把快照水合进内存（[_remote]），界面切周
///   全走本地；快照缺哪周、或用户手动刷新时才重新联网（见 [_fetchAllWeeks]）。
///   换账号时整份作废（见 [_dropRemoteData]）。
/// * **用户自己添加的课程**（[CustomCourse]）：属于用户数据，**一直留在本机**
///   （见 [CustomCourseStore]），刷新课表、换账号、退出登录都不动它。
///
/// 另外持久化的还有账户信息（登录会话、学号、学生信息快照 —— 见 [JwStoredAccount]）
/// 与上课提醒设置，它们都由 `main()` 启动时读好后通过 `restored*` 参数传进来。
/// 两来源在 [sessionsOfWeek] 里合并，界面只看到一套 [CourseSession]。
///
/// 加载策略：
/// 1. 内存里有该周（快照水合或本会话拉过）→ 直接渲染，不发请求；
/// 2. 否则防抖后请求教务系统，成功后**顺便预取相邻周**，并落盘进快照。
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
    ReminderRingPlatform? ringPlatform,
    KeepAliveSettings? restoredKeepAlive,
    WidgetUpdater? widgetUpdater,
    TimetableCacheStore? timetableCacheStore,
    Map<int, List<CourseSession>>? restoredTimetableCache,
    CaptchaRecognizer? captchaRecognizer,
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
       _customCourseStore = customCourseStore ?? const PrefsCustomCourseStore(),
       _customCourses = List<CustomCourse>.of(
         restoredCustomCourses ?? const <CustomCourse>[],
       ),
       _keepAliveStore = keepAliveStore ?? const PrefsKeepAliveStore(),
       _keepAlivePlatform = keepAlivePlatform ?? createKeepAlivePlatform(),
       _ringPlatform = ringPlatform ?? createReminderRingPlatform(),
       _keepAliveSettings = restoredKeepAlive ?? const KeepAliveSettings(),
       _widgetUpdater = widgetUpdater ?? createWidgetUpdater(),
       _captchaRecognizer = captchaRecognizer ?? createCaptchaRecognizer(),
       _timetableCacheStore =
           timetableCacheStore ?? const PrefsTimetableCacheStore() {
    // 本机存过的账号先认下来：学生信息马上能显示，登录页也能回填学号
    // （密码只有用户勾过「记住密码」才有，同样只用来回填）。
    _savedAccountNumber = restoredAccount?.account ?? '';
    _savedPassword = restoredAccount?.password ?? '';
    _student = restoredAccount?.student;
    _studentFromStore = _student != null;

    // 本地的课表快照（整学期 JSON）先水合进内存：冷启动不用等联网，
    // 切任何一周都是本地数据。哪些周有、哪些周缺，决定了后面要不要补拉。
    if (restoredTimetableCache != null) {
      for (final MapEntry<int, List<CourseSession>> entry
          in restoredTimetableCache.entries) {
        final int week = entry.key;
        if (week >= 1 && week <= _settings.term.totalWeeks) {
          _remote[week] = JwTimetable(
            week: week,
            sessions: List<CourseSession>.of(entry.value),
          );
        }
      }
    }

    _currentWeek = todayWeek;
    // 「空教室」默认查本周、今天（星期几直接用系统值，不受「当前显示第几周」影响）。
    _classroomQuery = JwClassroomQuery(
      week: _currentWeek,
      weekday: DateTime.now().weekday,
    );
    // 1) 先按教务系统主页面校准学期起止（权威周次），2) 同时拉当前周课表
    //    （有快照时本周已在内存里，这一步不会发请求）。
    unawaited(syncTermWithServer());
    _prepare(_currentWeek, immediate: true);
    // 2.5) 手上有会话、快照又没铺满整学期时，后台用课表接口把总课表拉全：
    //     每拉到一周就合并进内存并落盘成 JSON（见 [_fetchAllWeeks]）。
    if (_client.cookie.trim().isNotEmpty) {
      unawaited(_fetchAllWeeks());
    }
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

  /// 已持有的每周课表，键是**本地周次**。
  ///
  /// 数据从两处来：冷启动时由本地的课表 JSON 快照水合进来（`restoredTimetableCache`，
  /// 见 [TimetableCacheStore]），本会话内由课表接口拉回（每次拉到都同步写回快照）。
  /// 换账号时整份作废并清掉快照。
  final Map<int, JwTimetable> _remote = <int, JwTimetable>{};

  /// 旧课表接口（`main_index_loadkb.jsp`）的每周缓存：只存排课列表，
  /// 用来给课程详情弹窗补学分、课程属性这些新接口没有的字段。同样不落盘。
  final Map<int, List<CourseSession>> _loadkbPool =
      <int, List<CourseSession>>{};

  /// 正在通过旧接口拉取的周次。
  final Set<int> _loadkbLoading = <int>{};

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

  /// 提醒「响铃」要碰系统的口子（勿扰豁免的查询与授权入口）。
  final ReminderRingPlatform _ringPlatform;

  /// 有没有拿到勿扰豁免授权；null = 没查到或平台不支持（界面按未知处理，不提示）。
  bool? _dndAccess;

  /// 保活设置（目前只有开机自启意愿）。
  KeepAliveSettings _keepAliveSettings;

  /// 当前是否已在电池优化白名单里；null = 还没查到（启动后异步查一次）。
  bool? _ignoringBattery;

  /// 「下一节课」桌面小组件的投递口（Android 才有真实现，其余平台空操作）。
  final WidgetUpdater _widgetUpdater;

  /// 课表快照（整学期 JSON）的本地存储。
  ///
  /// 与 [_remote] 的关系：[_remote] 是内存里的每周数据（界面直接用），
  /// 快照是它落盘后的样子 —— 冷启动由 `restoredTimetableCache` 还原进 [_remote]，
  /// 每次从课表接口拿到新数据后又整份写回（见 [_saveTimetableCache]）。
  /// 换账号 / 退出登录时跟其它教务侧数据一起清掉（见 [_dropRemoteData]）。
  final TimetableCacheStore _timetableCacheStore;

  /// 是否正在按周补拉整学期课表（见 [_fetchAllWeeks]）。
  bool _allFetching = false;

  /// 验证码识别口（ML Kit 本地 OCR；Web/桌面是永远返回 null 的桩）。
  final CaptchaRecognizer _captchaRecognizer;

  /// 当前验证码的识别结果；null = 还没识别出来（或平台不支持/识别失败）。
  String? _captchaGuess;

  /// 当前这张验证码的自动识别是否已经失败（识别口没给出结果）。
  /// 登录页据此提示「请手动输入」，而不是让用户干等。
  bool _captchaOcrFailed = false;

  /// 每张验证码配一个「识别完成」信号：[autoLoginWithCaptcha] 等它出结果，
  /// 避免「识别还没跑完就去提交」的竞态。
  Completer<String?>? _captchaGuessDone;

  /// 是否正在跑自动登录（识别 → 提交 → 验证码错误重试 的闭环）。
  bool _autoLoginRunning = false;

  /// 自动登录最多尝试几次（每次都换新验证码重新识别）。
  static const int _autoLoginMaxAttempts = 3;

  /// 本次进程是否已经试过「会话失效后静默自动重登」。
  ///
  /// 只试一次：失败就安静停手交给用户手动登录，避免会话真挂了时
  /// 每次校准周次都撞一次墙、白耗流量还可能触发教务系统的风控。
  bool _autoReloginAttempted = false;

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

  /// 用旧课表接口（`main_index_loadkb.jsp`）给 [session] 补附加信息。
  ///
  /// 新课表接口比旧接口**多了老师、少了学分与课程属性**，所以详情弹窗打开时
  /// 拿旧接口按日期再查一次，把缺的字段补上。约定：
  /// * 只对教务课生效（自建课是用户手打的，没有「教务侧附加信息」可补）；
  /// * 拉取失败 / 匹配不到都返回 null —— 副数据源失败**不影响课表**，
  ///   详情弹窗只是少了几个信息行；
  /// * 每周只拉一次（[_loadkbPool] 缓存），同周再点其它课不再发请求。
  Future<CourseSession?> loadEnrichedSession(
    CourseSession session,
    int week,
  ) async {
    if (session.isCustom) {
      return null;
    }
    // 已经有全部附加信息了，没必要再走一次旧接口。
    if (session.course.credits != null && session.course.category != null) {
      return null;
    }

    List<CourseSession>? pool = _loadkbPool[week];
    if (pool == null && !_loadkbLoading.contains(week)) {
      _loadkbLoading.add(week);
      try {
        // 旧接口按日期取课（教务按周一到周日分周）。本应用第 N 周从周日开始，
        // 它的星期一（startOfWeek + 1 天）落在教务第 N 周里，与新接口 zc=N 同一口径。
        final DateTime monday = term
            .startOfWeek(week)
            .add(const Duration(days: 1));
        pool = (await _client.fetchWeekByLoadkb(monday)).sessions;
        _loadkbPool[week] = pool;
      } catch (error) {
        return null; // 副数据源，失败就当没有
      } finally {
        _loadkbLoading.remove(week);
      }
    }
    if (pool == null) {
      return null; // 同周已经在拉了：这次先不补，下次打开详情再试
    }
    return _matchEnriched(pool, session);
  }

  /// 从旧接口的排课里找出 [session] 对应的那条并补齐缺失字段。
  ///
  /// 旧接口格子里没有老师，所以匹配只认**课名 + 星期几 + 节次有交集**；
  /// 补的也只是新接口缺的字段，已有的一律保留（本课的教室/周次信息更准）。
  CourseSession? _matchEnriched(
    List<CourseSession> pool,
    CourseSession session,
  ) {
    for (final CourseSession candidate in pool) {
      if (candidate.weekday != session.weekday ||
          candidate.course.name.trim() != session.course.name.trim() ||
          candidate.startPeriod > session.endPeriod ||
          candidate.endPeriod < session.startPeriod) {
        continue;
      }
      return CourseSession(
        course: Course(
          name: session.course.name,
          location: session.course.location,
          teacher: session.course.teacher.isNotEmpty
              ? session.course.teacher
              : candidate.course.teacher,
          credits: session.course.credits ?? candidate.course.credits,
          category: session.course.category ?? candidate.course.category,
        ),
        weekday: session.weekday,
        startPeriod: session.startPeriod,
        endPeriod: session.endPeriod,
        startWeek: session.startWeek,
        endWeek: session.endWeek,
        customId: session.customId,
      );
    }
    return null;
  }

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
    // 旧图作废，旧识别结果也一起作废；新图的识别在后台补跑。
    _captchaGuess = null;
    _captchaOcrFailed = false;
    final Completer<String?> guessDone = Completer<String?>();
    _captchaGuessDone = guessDone;
    notifyListeners();

    try {
      final JwLoginSession session = await _client.beginLogin();
      _loginSession = session;
      _captchaImage = session.image;
      // 图到手就后台识别：识别结果通过 [_captchaGuess] 暴露给登录页自动填入，
      // 完成信号落在 [guessDone] 上（自动登录等它，避免「没识别完就提交」）。
      unawaited(_recognizeCaptcha(session.image).then(guessDone.complete));
    } on JwException catch (error) {
      _loginSession = null;
      // 已经有失败原因时**不要覆盖**：「密码错了」比「验证码没取到」更是用户要看的那条；
      // 验证码位会退化成「点此获取」，用户点一下就能重试。
      _loginError ??= error.message;
      guessDone.complete(null);
    } catch (error) {
      _loginSession = null;
      _loginError ??= '获取验证码失败：$error';
      guessDone.complete(null);
    } finally {
      _loginLoading = false;
      notifyListeners();
    }
  }

  /// 识别当前验证码图，把结果写进 [_captchaGuess] 并通知界面自动填入。
  ///
  /// 图在识别期间被换掉（用户点了「换一张」）时丢弃结果 —— 旧字符填到新图上
  /// 注定是错的。识别器**不抛异常**（见 [CaptchaRecognizer]），但这里仍兜一层。
  Future<String?> _recognizeCaptcha(Uint8List image) async {
    String? guess;
    try {
      guess = await _captchaRecognizer.recognize(image);
    } catch (_) {
      guess = null;
    }
    if (!identical(image, _captchaImage)) {
      return null;
    }
    if (guess != null && guess.isNotEmpty) {
      _captchaGuess = guess;
      _captchaOcrFailed = false;
      notifyListeners();
    } else {
      // 这张图识别不出来：登录页会提示手动输入，别让用户干等。
      _captchaOcrFailed = true;
      // 不通知的话，提示要等下一次任意 rebuild 才出现（比如用户点了别处），
      // 看起来像「没反应」。
      notifyListeners();
    }
    return guess;
  }

  /// 当前验证码的识别结果（登录页自动填入验证码输入框用）。
  String? get captchaGuess => _captchaGuess;

  /// 当前这张验证码的自动识别是否已失败（该提示用户手动输入了）。
  bool get captchaOcrFailed => _captchaOcrFailed;

  /// 当前这张验证码识别失败的原因（识别口给出的诊断信息）。
  ///
  /// 登录页拼进提示里展示，用户照着念就能反馈定位 —— 不再是干巴巴的
  /// 「识别失败」四个字。
  String? get captchaOcrError => _captchaRecognizer.lastError;

  /// 等当前验证码的识别结果：已有就直接给，没有就等识别完成信号（最多 12s）。
  ///
  /// 登录页手动提交时也用它兜底 —— 用户点登录的瞬间识别可能还在跑，
  /// 等一下就能用上结果，不用白白提交一次空验证码。
  Future<String?> awaitCaptchaGuess() async {
    if (_captchaGuess != null) {
      return _captchaGuess;
    }
    if (_captchaOcrFailed) {
      // 这张图的识别已经跑完且失败了：没有可等的了，别让用户陪着耗 12 秒。
      return null;
    }
    final Completer<String?>? done = _captchaGuessDone;
    if (done == null) {
      return null;
    }
    try {
      return await done.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // 等满了还没结果：这张图按识别失败处理 —— 免得调用方（登录页）
      // 既交不了又拿不到任何「为什么」，下一次也能直接快速失败不再陪等。
      _captchaOcrFailed = true;
      notifyListeners();
      return _captchaGuess;
    }
  }

  /// 自动登录：识别验证码 → 提交表单；服务端报「验证码错误」时自动换图重试。
  ///
  /// 本校验证码是干净的白底字符，本地 OCR 基本稳对；偶有读错，服务端只报
  /// 验证码错（[submitLogin] 失败后已经自动换好新图并重新发起识别），
  /// 所以同一套账号密码最多重试 [_autoLoginMaxAttempts] 次。其它失败
  /// （账号/密码错、网络挂）不重试 —— 重试也不会变好，留着错误信息给用户看。
  ///
  /// 识别不出（平台不支持 / 模型没就绪）直接返回 false，用户手动输入。
  Future<bool> autoLoginWithCaptcha({
    required String account,
    required String password,
    bool rememberPassword = false,
  }) async {
    if (_autoLoginRunning || account.isEmpty || password.isEmpty) {
      return false;
    }
    _autoLoginRunning = true;
    try {
      for (var attempt = 0; attempt < _autoLoginMaxAttempts; attempt++) {
        final String? guess = await awaitCaptchaGuess();
        if (guess == null || guess.isEmpty) {
          return false;
        }
        _captchaGuess = guess;
        notifyListeners();
        final bool ok = await submitLogin(
          account: account,
          password: password,
          captcha: guess,
          rememberPassword: rememberPassword,
        );
        if (ok) {
          return true;
        }
        final String? error = _loginError;
        if (error == null || !error.contains('验证码')) {
          return false;
        }
      }
      return false;
    } finally {
      _autoLoginRunning = false;
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
      // 先把当前周拉下来（登录后立刻有课表看），其余周后台补全并落盘成 JSON。
      await _fetch(_currentWeek, force: true);
      unawaited(_fetchAllWeeks(force: true));
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
    // 勿扰豁免只查状态不弹任何界面；查不到（老版本原生代码等）就保持 null。
    await refreshRingStatus();
    notifyListeners();
    await _syncReminders();
    // 冷启动也把排期窗口往前铺满：只靠「当前周 + 相邻周」预取，窗口末端
    // （第 8 天往后的日子）可能落在还没拉的周上，那些课就没有提醒。
    await ensureReminderHorizon();
  }

  /// 把提醒排期窗口（[reminderHorizon]，14 天）覆盖到、但手里还没有的周课表
  /// **自动往下查询**回来。
  ///
  /// 每条提醒触发之后，窗口末端就往未来挪了一点，可能伸进还没拉过的周——
  /// 下次 App 冷启动或回到前台时（见 [onAppResumed]）调用这里，把缺的周补上；
  /// 每拉到一周，[_fetch] 的收尾会自动重排提醒，新覆盖到的课就排进系统闹钟。
  ///
  /// 幂等：已在 [_remote] / 正在拉取的周直接跳过；没登录时拉取失败会安静记错，
  /// 不会重试循环。串行拉取（一次一周），避免占用预取的并发额度。
  Future<void> ensureReminderHorizon() async {
    if (!_notifier.isSupported || !_reminderSettings.enabled) {
      return;
    }
    final DateTime now = DateTime.now();
    final int first = term.weekOf(now);
    final int last = term.weekOf(now.add(reminderHorizon));
    for (int week = first; week <= last; week++) {
      if (week < 1 || week > term.totalWeeks) {
        continue;
      }
      if (_remote.containsKey(week) || _loadingWeeks.contains(week)) {
        continue;
      }
      await _fetch(week);
    }
  }

  /// App 回到前台时的提醒巡检。
  ///
  /// Android 在通知弹出时不会唤醒应用，所以「提醒触发后自动往下排」落在
  /// 用户下次打开 App 的这个瞬间：把已经触发的提醒从待办里清掉（重排），
  /// 再把排期窗口往前延伸（[ensureReminderHorizon]）。
  Future<void> onAppResumed() async {
    if (!_notifier.isSupported) {
      return;
    }
    await refreshReminderPermission();
    // 用户可能刚去系统里授权/收回了「勿扰打扰」，回来时把响铃状态也刷一遍。
    await refreshRingStatus();
    await _syncReminders();
    await ensureReminderHorizon();
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

  /// 当前平台有没有「勿扰豁免」这套概念（Android 有）。
  bool get ringSupported => _ringPlatform.isSupported;

  /// 有没有拿到勿扰豁免授权；null = 还没查到 / 平台不支持 / 通道异常。
  bool? get dndAccess => _dndAccess;

  /// 重新查一遍勿扰豁免授权状态（**不弹任何界面**）。
  ///
  /// 用户可能刚在系统设置里放行或收回，回到 App 得能反映出来。
  Future<void> refreshRingStatus() async {
    if (!_ringPlatform.isSupported) {
      return;
    }
    _dndAccess = await _ringPlatform.dndAccessGranted();
    notifyListeners();
  }

  /// 跳去系统的「勿扰打扰」授权页（提醒响铃的关键权限）。
  ///
  /// 返回是否跳成功；授权结果等用户回来后由 [refreshRingStatus]（onAppResumed
  /// 触发）刷新。没拿到授权时勿扰/静音下提醒不会响铃，界面会用提示卡引导。
  Future<bool> openRingSettings() => _ringPlatform.openDndAccessSettings();

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
    _ignoringBattery = await _keepAlivePlatform
        .isIgnoringBatteryOptimizations();
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

  /// 打开系统的「省电模式」设置页（低电量自动省电的机型会拦白名单里的闹钟）。
  Future<bool> openBatterySaverSettings() =>
      _keepAlivePlatform.openBatterySaverSettings();

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
    await ensureReminderHorizon();
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
        byWeek
            .putIfAbsent(week, () => <CourseSession>[])
            .add(course.toSession());
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
    _loadkbPool.clear();
    _notices.clear();
    _errors.clear();
    _loadingWeeks.clear();
    _pendingWeeks.clear();
    // 课表快照是「教务侧」的数据（整学期 JSON），换账号 / 退出登录一并清掉；
    // 新账号登录成功后 [_fetchAllWeeks] 会整份重建。
    unawaited(_timetableCacheStore.clear());
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
      // 冷启动恢复的 Cookie 可能已被服务端作废（App 被杀后无人续会话）。
      // 存过密码就静默重登一次，成功后下面清掉错误条，用户全程无感。
      unawaited(_autoReloginIfExpired(error.message));
    } catch (error) {
      _weekInfoError = '读取教务系统周次失败：$error';
      notifyListeners();
    }
  }

  /// 会话失效时用本机存过的账号密码静默重登一次。
  ///
  /// 只在满足全部条件时触发：失效原因确实是「要登录」（[reason] 含「会话已失效」
  /// 或「请先登录」，网络故障不在此列）、用户勾过「记住密码」（[_savedPassword]
  /// 非空 —— 没存过密码我们无从代填）、本次进程还没试过。失败就安静停手，
  /// 交给用户手动登录。
  ///
  /// 冷启动时验证码还没取过，而自动登录依赖「已取图 + 后台识别」的闭环，
  /// 所以先静默取一张图（取到即自动识别）。之后 [submitLogin] 的正常收尾会
  /// 自动接管：采用新主页、清掉旧会话的内存课表、按新会话重拉当前周与整学期、
  /// 落盘新 Cookie —— 这里只需把上面挂出的失效提示撤掉，别让它挂在课表页上。
  Future<void> _autoReloginIfExpired(String reason) async {
    if (_autoReloginAttempted ||
        _savedAccountNumber.isEmpty ||
        _savedPassword.isEmpty ||
        !(reason.contains('会话已失效') || reason.contains('请先登录'))) {
      return;
    }
    _autoReloginAttempted = true;
    await _fetchCaptcha();
    final bool ok = await autoLoginWithCaptcha(
      account: _savedAccountNumber,
      password: _savedPassword,
      rememberPassword: true,
    );
    if (ok && _weekInfoError != null) {
      _weekInfoError = null;
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

  /// 强制重新拉取：把整学期总课表重拉一遍并重建本地 JSON 快照。
  ///
  /// 界面先看到的是当前周的变化（fetch-all 按周次顺序推进，每完成一周就刷新）；
  /// 期间并发来的 refresh 请求会被 [_fetchAllWeeks] 挡掉，只跑这一轮。
  Future<void> refresh() async {
    _debounce?.cancel();
    _pendingWeeks.clear();
    await _fetchAllWeeks(force: true);
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
      // 课表接口拿到的数据整份并进本地 JSON 快照：下次冷启动不用再问教务系统。
      unawaited(_saveTimetableCache());
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

  /// 用课表接口把**整学期总课表**拉全：从第 1 周到第 [AppSettings.term] 的总周数
  /// 逐周请求（接口按 `zc=周次` 返回单周），每拉到一周就合并进内存并落盘成
  /// 本地 JSON 快照。之后界面切周、上课提醒、桌面小组件全走本地数据。
  ///
  /// 触发时机：
  /// * 冷启动 —— 有会话且快照没铺满整学期时补拉缺失的周（[force] = false）；
  /// * 登录成功 —— 新账号的课表整份重建（[force] = true）；
  /// * 手动刷新 —— 整学期重新拉一遍（[force] = true）。
  ///
  /// 串行逐周请求（复用同一条 keep-alive 连接），每完成一周就 notify 一次，
  /// 界面能看着课表一格一格长出来。单周失败只记那一周的错，不影响其余周。
  Future<void> _fetchAllWeeks({bool force = false}) async {
    if (_allFetching) {
      return; // 同一轮总拉取不并发重复
    }
    final int total = term.totalWeeks;
    final List<int> targets = <int>[
      for (var week = 1; week <= total; week++)
        if (force || !_remote.containsKey(week)) week,
    ];
    if (targets.isEmpty) {
      return; // 快照已经铺满整学期，不用联网
    }
    _allFetching = true;
    // 当前要看的那周排最前：界面反馈最快（轮到它时 [_fetch] 自己会接管加载状态）。
    if (targets.remove(_currentWeek)) {
      targets.insert(0, _currentWeek);
    }
    notifyListeners();
    try {
      for (final int week in targets) {
        if (_disposed) {
          return;
        }
        await _fetch(week, force: force);
      }
    } finally {
      _allFetching = false;
      notifyListeners();
    }
  }

  /// 把 [_remote] 的整份课表写进本地 JSON 快照。
  ///
  /// 每次从课表接口拿到新数据都会调这里；写入期间再来的请求只标脏，
  /// 等这轮写完再补一轮，保证最后一版快照一定是最新内容。
  Future<void> _saveTimetableCache() async {
    if (_cacheSaving) {
      _cacheSavePending = true;
      return;
    }
    _cacheSaving = true;
    try {
      await _timetableCacheStore.write(<int, List<CourseSession>>{
        for (final MapEntry<int, JwTimetable> entry in _remote.entries)
          entry.key: entry.value.sessions,
      });
    } finally {
      _cacheSaving = false;
      if (_cacheSavePending && !_disposed) {
        _cacheSavePending = false;
        await _saveTimetableCache();
      }
    }
  }

  /// 快照写入互斥（见 [_saveTimetableCache]）。
  bool _cacheSaving = false;
  bool _cacheSavePending = false;

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

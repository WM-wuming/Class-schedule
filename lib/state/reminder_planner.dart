import '../models/course.dart';
import '../models/period.dart';
import '../models/reminder.dart';
import '../models/week.dart';

/// 提醒最多往后排多久。
///
/// 课表**不落盘**，App 每次冷启动手里只有「当前周 + 相邻周」（见 `ScheduleController`
/// 的预取策略），所以排期也只能看这些周。超出这个窗口的课，等用户下次打开 App 时再补上。
/// 把它写成一个明确的窗口而不是「有多少排多少」，是为了让「排了多少条」这件事可解释。
const Duration reminderHorizon = Duration(days: 14);

/// 把课表里**还没上**的每一节课，换算成一条它对应的提醒。
///
/// 纯函数：课表、学期设置、当前时间都由调用方传进来，不读磁盘也不碰平台，
/// 所以时间相关的边界（提前时刻已过、课已经开始、超出窗口）都能直接测。
///
/// 会**跳过**这几类：
/// * 本周不上这门课（[CourseSession.isActiveInWeek] 为假）；
/// * 已经上过的课（[ClassReminder.startsAt] 不在 [now] 之后）—— 不补发历史提醒；
/// * 提醒时刻已经过去的课 —— 例如用户在上课前 3 分钟才打开 App，而提前量是 10 分钟。
///   这种课**故意不提醒**：每次冷启动都补弹一条「该上课了」比不提醒更烦；
/// * 排到 [horizon] 之外的课。
///
/// 返回结果按提醒时刻从近到远排序。
List<ClassReminder> planClassReminders({
  required Term term,
  required Map<int, List<CourseSession>> sessionsByWeek,
  required ClassReminderSettings settings,
  required DateTime now,
  List<Period> periods = Period.defaults,
  Duration horizon = reminderHorizon,
}) {
  if (!settings.enabled) {
    return const <ClassReminder>[];
  }

  final DateTime limit = now.add(horizon);
  final List<ClassReminder> planned = <ClassReminder>[];
  final Set<int> usedIds = <int>{};

  final List<int> weeks = sessionsByWeek.keys.toList()..sort();
  for (final int week in weeks) {
    if (week < 1 || week > term.totalWeeks) {
      continue; // 学期外的周次不排（学期设置被改小过时会出现）
    }
    final List<CourseSession>? sessions = sessionsByWeek[week];
    if (sessions == null) {
      continue;
    }
    final DateTime weekStart = term.startOfWeek(week);

    for (final CourseSession session in sessions) {
      if (!session.isActiveInWeek(week)) {
        continue;
      }
      final Period? first = _periodOf(periods, session.startPeriod);
      if (first == null) {
        continue; // 节次表里没有这一节，算不出时间，只能跳过
      }
      final Period last = _periodOf(periods, session.endPeriod) ?? first;

      final DateTime startsAt = _moment(weekStart, session.weekday, first.start);
      if (!startsAt.isAfter(now)) {
        continue; // 已经开课或已经下课，不再提醒
      }
      final DateTime at = startsAt.subtract(settings.lead);
      if (!at.isAfter(now)) {
        continue; // 该提醒的时刻已经过去了，不补发
      }
      if (at.isAfter(limit)) {
        continue; // 超出排期窗口
      }

      final int id = _reminderId(week, session.weekday, session.startPeriod);
      if (!usedIds.add(id)) {
        continue; // 教务系统数据重了，同一格只提醒一次
      }

      planned.add(
        ClassReminder(
          id: id,
          week: week,
          weekday: session.weekday,
          startPeriod: session.startPeriod,
          endPeriod: session.endPeriod,
          courseName: session.course.name,
          location: session.course.location,
          at: at,
          startsAt: startsAt,
          endsAt: _moment(weekStart, session.weekday, last.end),
          leadMinutes: settings.leadMinutes,
        ),
      );
    }
  }

  planned.sort(
    (ClassReminder a, ClassReminder b) => a.at.compareTo(b.at),
  );
  return planned;
}

/// 系统通知 id：**同一节课每次算出来都一样**。
///
/// `周次 * 1000 + 星期 * 100 + 起始节次` —— 一周 7 天、一天最多几十节，
/// 三者的位段互不重叠，所以「同一周同一天同一节」之外不会撞号。
int _reminderId(int week, int weekday, int startPeriod) =>
    week * 1000 + weekday * 100 + startPeriod;

/// 第 [week] 周里星期 [weekday] 的 `HH:mm` 对应的时刻。
///
/// 学期以**周日**为第 1 周的第 1 天（见 [Term.startOfWeek]），而 `DateTime.weekday`
/// 里周日是 7，所以从周日零点往回数的天数偏移是 `weekday % 7`。
DateTime _moment(DateTime weekStart, int weekday, String hhmm) {
  final int days = weekday % 7;
  final List<String> parts = hhmm.split(':');
  final int hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(
    weekStart.year,
    weekStart.month,
    weekStart.day + days,
    hour,
    minute,
  );
}

/// 从节次表里找第 [index] 节；找不到返回 null。
Period? _periodOf(List<Period> periods, int index) {
  for (final Period period in periods) {
    if (period.index == index) {
      return period;
    }
  }
  return null;
}

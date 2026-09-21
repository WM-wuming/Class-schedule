import 'package:flutter/foundation.dart';

/// 上课提醒的设置：**总开关** + **提前多久提醒**。
///
/// 这是用户唯一能调的两个东西，落盘在 `reminder_store.dart` 里，冷启动时读回来。
@immutable
class ClassReminderSettings {
  const ClassReminderSettings({
    this.enabled = defaultEnabled,
    this.leadMinutes = defaultLeadMinutes,
  });

  /// 默认开着：课表 App 不提醒上课就没意义了。
  static const bool defaultEnabled = true;

  /// 默认提前 10 分钟。
  ///
  /// 一节课 45 分钟，10 分钟够从宿舍走到教室；又不至于上一节课还没下课就开始响
  /// （第 1-2 节之间只隔 5 分钟，提前量再大就会在上一节课中途提醒）。
  static const int defaultLeadMinutes = 10;

  /// 界面上直接给的几个提前量（分钟）。
  static const List<int> leadOptions = <int>[5, 10, 15, 20, 30, 45, 60];

  /// 允许的提前量范围。本地存档被改坏时按这个范围夹一下，别让它变得荒唐。
  static const int minLeadMinutes = 1;
  static const int maxLeadMinutes = 180;

  /// 是否开启上课提醒。
  final bool enabled;

  /// 上课前多少分钟提醒。
  final int leadMinutes;

  /// 提前量对应的时长。
  Duration get lead => Duration(minutes: leadMinutes);

  /// 「提前 10 分钟」/「提前 1 小时」。
  String get leadLabel {
    if (leadMinutes >= 60 && leadMinutes % 60 == 0) {
      return '提前 ${leadMinutes ~/ 60} 小时';
    }
    return '提前 $leadMinutes 分钟';
  }

  ClassReminderSettings copyWith({bool? enabled, int? leadMinutes}) =>
      ClassReminderSettings(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'lead': leadMinutes,
  };

  /// 解析本地存的内容。
  ///
  /// 宽容到底：字段类型不对就用默认值，提前量超出范围就夹回范围内。
  /// 本地内容可能是上一版 App 写的，读不懂就用默认值，比抛异常把 App 顶掉好。
  static ClassReminderSettings fromJson(Map<String, dynamic> json) {
    final Object? rawLead = json['lead'];
    final Object? rawEnabled = json['enabled'];
    return ClassReminderSettings(
      enabled: rawEnabled is bool ? rawEnabled : defaultEnabled,
      leadMinutes: rawLead is int
          ? rawLead.clamp(minLeadMinutes, maxLeadMinutes)
          : defaultLeadMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassReminderSettings &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode => Object.hash(enabled, leadMinutes);
}

/// 一条**待发**的上课提醒。
///
/// 由 [planClassReminders] 从课表算出来，交给 `ClassReminderNotifier` 交给系统。
/// 它是个纯数据对象：不碰平台、不碰时间源（`now` 是传进来的），所以能直接断言。
@immutable
class ClassReminder {
  const ClassReminder({
    required this.id,
    required this.week,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.courseName,
    required this.location,
    required this.at,
    required this.startsAt,
    required this.endsAt,
    required this.leadMinutes,
  });

  /// 系统通知的 id。
  ///
  /// 由「周次 + 星期 + 起始节次」算出来（见 [planClassReminders]），所以**同一节课
  /// 每次算出来的 id 都一样** —— 重排时可以精确覆盖，不会攒出一堆重复提醒。
  final int id;

  /// 第几周。
  final int week;

  /// 星期几，1 = 周一 …… 7 = 周日。
  final int weekday;

  /// 起始节次（含）。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 课程名。
  final String courseName;

  /// 上课地点。
  final String location;

  /// 提醒发出的时刻（= [startsAt] 往前推 [leadMinutes] 分钟）。
  final DateTime at;

  /// 上课时刻。
  final DateTime startsAt;

  /// 下课时刻。
  final DateTime endsAt;

  /// 这条提醒的提前量（分钟），用来写通知标题。
  final int leadMinutes;

  /// 通知标题：`还有 10 分钟上课`。
  String get title => '还有 $leadMinutes 分钟上课';

  /// 通知正文：`高等数学 · J1-102 · 08:20-09:05`。
  String get body => <String>[
    courseName,
    if (location.isNotEmpty) location,
    timeLabel,
  ].join(' · ');

  /// 上课时段：`08:20-09:05`。
  String get timeLabel => '${_hhmm(startsAt)}-${_hhmm(endsAt)}';

  /// 星期几的中文写法：`一`。
  String get weekdayLabel =>
      const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

  /// 界面上的时间描述：`周三 9/23 08:20`。
  String get whenLabel =>
      '周$weekdayLabel ${startsAt.month}/${startsAt.day} ${_hhmm(startsAt)}';

  /// 节次描述：`第 1-2 节` / `第 3 节`。
  String get periodsLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod-$endPeriod 节';

  static String _hhmm(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ClassReminder &&
      other.id == id &&
      other.week == week &&
      other.weekday == weekday &&
      other.startPeriod == startPeriod &&
      other.endPeriod == endPeriod &&
      other.courseName == courseName &&
      other.location == location &&
      other.at == at &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode => Object.hash(
    id,
    week,
    weekday,
    startPeriod,
    endPeriod,
    courseName,
    location,
    at,
    startsAt,
    endsAt,
    leadMinutes,
  );
}

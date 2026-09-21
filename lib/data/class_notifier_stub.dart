import '../models/reminder.dart';
import 'class_notifier.dart';

/// 兜底实现：没有 `dart:io` 的平台（Web）。
///
/// Web 上做不了「App 没开着也能在课前弹通知」这件事 —— 那要 Service Worker + 推送，
/// 而课表数据在浏览器里本来就取不到（要走同源代理），所以这里干脆什么都不做，
/// 由 [isSupported] 为 false 让界面如实说明。
ClassReminderNotifier createClassReminderNotifier() =>
    const _UnsupportedReminderNotifier();

class _UnsupportedReminderNotifier implements ClassReminderNotifier {
  const _UnsupportedReminderNotifier();

  @override
  bool get isSupported => false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> permissionGranted() async => false;

  @override
  Future<bool> openNotificationSettings() async => false;

  @override
  Future<void> sync(List<ClassReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}

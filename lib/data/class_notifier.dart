import '../models/reminder.dart';
import 'class_notifier_stub.dart'
    if (dart.library.io) 'class_notifier_io.dart' as impl;

/// 把 [ClassReminder] 交给操作系统的口子。
///
/// 抽成接口是为了两件事：
/// * **测试**能塞一个假的进来（见 `test/fakes.dart` 的 `FakeReminderNotifier`），
///   不然 widget 测试会去碰平台通道；
/// * **平台差异**收在一个地方 —— Android/iOS/macOS 走 `flutter_local_notifications`，
///   没有 `dart:io` 的平台（Web）退化成不支持。
///
/// 实现的一个硬性契约：**任何方法都不抛异常**（最差是 `debugPrint` 一句然后什么都不做）。
/// 提醒发不出去不该把课表页搞崩，也不该算成加载失败。
abstract interface class ClassReminderNotifier {
  /// 当前平台支不支持**系统级**定时通知。
  ///
  /// 为 false 时界面不能只说「已开启」，得说清「这个平台不支持」。
  bool get isSupported;

  /// 初始化（只做一次，重复调用无副作用）。
  Future<void> init();

  /// 申请通知权限，返回是否拿到。
  Future<bool> requestPermission();

  /// 当前有没有通知权限（**不会弹窗**，只是查状态）。
  Future<bool> permissionGranted();

  /// 跳去系统的通知设置页（用户手动放行时用），返回是否跳成功。
  Future<bool> openNotificationSettings();

  /// 用 [reminders] **覆盖**已排的提醒（先清空再排）。
  ///
  /// 覆盖式而不是增量式：课表随时可能被教务系统改（换教室、停课），
  /// 增量排期会留下一堆对不上的旧提醒。
  Future<void> sync(List<ClassReminder> reminders);

  /// 清掉所有已排的提醒（关掉开关时）。
  Future<void> cancelAll();
}

/// 按当前平台建一个通知投递口。
ClassReminderNotifier createClassReminderNotifier() =>
    impl.createClassReminderNotifier();

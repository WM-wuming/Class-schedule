import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import 'class_notifier.dart';

/// 真发系统通知的实现（Android / iOS / macOS）。
///
/// 时间换算上有一个容易踩的点：`zonedSchedule` 要的是 [tz.TZDateTime]，而 `timezone`
/// 包的 `tz.local` 只有在调用过 `setLocalLocation()` 之后才有值（否则是
/// `LateInitializationError`）。这里**不做时区换算**，改用 [tz.UTC] 并靠
/// `TZDateTime.from` 的「保持绝对时刻」语义 —— 传进去的是设备本地时间的 [DateTime]，
/// 换算出来是同一个瞬间，只是用 UTC 表达。传到底层时带的是 `timeZoneName: Etc/UTC`
/// 加 UTC 挂钟时间，Android 侧 `ZonedDateTime.of(...).toInstant()` 拿到的就是正确的
/// 时间点。这样既不用引 `flutter_timezone`，也不怕设备改时区。
ClassReminderNotifier createClassReminderNotifier() =>
    FlutterClassReminderNotifier();

/// Android 8+ 的通知渠道。渠道一旦创建，**重要级别就改不了了**，所以这里定好就不再变。
const String reminderChannelId = 'class_reminder';
const String reminderChannelName = '上课提醒';
const String reminderChannelDescription = '每节课上课前提醒一次';

class FlutterClassReminderNotifier implements ClassReminderNotifier {
  FlutterClassReminderNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// 初始化只做一次。
  bool _initialized = false;

  /// 只有这三个平台配了初始化参数，其它平台（Web / Linux / Windows）不假装支持。
  @override
  bool get isSupported => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  @override
  Future<void> init() async {
    if (_initialized || !isSupported) {
      return;
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // 权限一律在用户打开开关时显式申请（见 [requestPermission]），
          // 初始化阶段不弹窗：App 一启动就弹权限框很唐突。
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      _initialized = true;
    } catch (error) {
      debugPrint('初始化本地通知失败：$error');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) {
      return false;
    }
    await init();
    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final bool granted =
            await android.requestNotificationsPermission() ?? false;
        if (granted) {
          // 精确闹钟（Android 12+）是「能不能准点响」的关键，但它不是必须的：
          // 用户在系统设置里不放行也不该把提醒整个关掉 —— sync() 会自动退化成
          // 不精确排期（可能晚几分钟），而不是不发。
          await android.requestExactAlarmsPermission();
        }
        return granted;
      }

      final IOSFlutterLocalNotificationsPlugin? ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }

      final MacOSFlutterLocalNotificationsPlugin? macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (macos != null) {
        return await macos.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (error) {
      debugPrint('申请通知权限失败：$error');
    }
    return false;
  }

  @override
  Future<bool> permissionGranted() async {
    if (!isSupported) {
      return false;
    }
    await init();
    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }

      // iOS / macOS 没有「问一句」的接口，只能读当前的授权结果。
      final NotificationsEnabledOptions? darwin =
          await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions() ??
              await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions();
      return darwin?.isEnabled ?? false;
    } catch (error) {
      debugPrint('读取通知权限状态失败：$error');
      return false;
    }
  }

  @override
  Future<bool> openNotificationSettings() async {
    if (!isSupported) {
      return false;
    }
    await init();
    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.openAppNotificationSettings() ?? false;
      }
    } catch (error) {
      debugPrint('打开通知设置失败：$error');
    }
    // iOS / macOS 没有对应的跳转接口，界面上的按钮会退化成一句提示。
    return false;
  }

  @override
  Future<void> sync(List<ClassReminder> reminders) async {
    if (!isSupported) {
      return;
    }
    await init();
    if (!_initialized) {
      return;
    }
    try {
      // 覆盖式：先清掉上一轮排的，避免教务系统改了课表之后留下对不上的旧提醒。
      await _plugin.cancelAllPendingNotifications();
    } catch (error) {
      debugPrint('清除旧的上课提醒失败：$error');
    }

    final AndroidScheduleMode mode = await _scheduleMode();
    final NotificationDetails details = _details();
    for (final ClassReminder reminder in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
          notificationDetails: details,
          androidScheduleMode: mode,
          // 点开通知就把用户送回课表页（不额外做路由，payload 只留个记号）。
          payload: 'week=${reminder.week}',
        );
      } catch (error) {
        // 一条排不上不该把其余的全丢掉。
        debugPrint('排上课提醒失败（${reminder.courseName}）：$error');
      }
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!isSupported) {
      return;
    }
    await init();
    try {
      await _plugin.cancelAllPendingNotifications();
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('清除上课提醒失败：$error');
    }
  }

  /// 能精确排期就精确，不能就退化成「大概这个点」。
  Future<AndroidScheduleMode> _scheduleMode() async {
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      // 非 Android 平台这个参数不生效，给个默认值即可。
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    try {
      final bool? exact = await android.canScheduleExactNotifications();
      return exact ?? false
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (error) {
      debugPrint('查询精确闹钟权限失败：$error');
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  NotificationDetails _details() => const NotificationDetails(
    android: AndroidNotificationDetails(
      reminderChannelId,
      reminderChannelName,
      channelDescription: reminderChannelDescription,
      // 上课提醒要能「弹到脸上」，不然错过一节课就没意义了。
      importance: Importance.high,
      priority: Priority.high,
      // 同一节课的提醒只留一条，不静默累积。
      onlyAlertOnce: true,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
}

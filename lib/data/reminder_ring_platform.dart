import 'reminder_ring_platform_stub.dart'
    if (dart.library.io) 'reminder_ring_platform_io.dart' as impl;

/// 上课提醒「响铃」要碰系统的地方：**勿扰豁免**（通知策略访问权限）。
///
/// 手机开着勿扰（或某些机型的静音模式）时，普通通知一律被压成无声 ——
/// 提醒排得再准也不响。系统里唯一能让 App 通知穿透勿扰的口子是
/// 「勿扰打扰」（通知策略访问）授权；拿到它之后，把提醒渠道归类为
/// 「闹钟」类别，勿扰的默认例外规则就会放行它的铃声。
///
/// 与 [KeepAlivePlatform] 同理：抽成接口是为了测试塞假的、平台差异收在一处；
/// 契约是**任何方法都不抛异常**，查不到状态返回 null。
abstract interface class ReminderRingPlatform {
  /// 当前平台有没有「勿扰豁免」这套概念（Android 有，Web / 桌面没有）。
  bool get isSupported;

  /// 现在有没有拿到勿扰访问授权；null = 查不到（通道异常等），界面按「未知」处理。
  Future<bool?> dndAccessGranted();

  /// 跳去系统的「勿扰打扰」授权页（设置 → 声音 → 勿扰 → 例外应用）。
  /// 返回是否跳成功；用户授权与否要看回来后的 [dndAccessGranted]。
  Future<bool> openDndAccessSettings();
}

/// 按当前平台建一个响铃口。
ReminderRingPlatform createReminderRingPlatform() =>
    impl.createReminderRingPlatform();

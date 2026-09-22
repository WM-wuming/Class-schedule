import 'keep_alive_platform_stub.dart'
    if (dart.library.io) 'keep_alive_platform_io.dart' as impl;

/// 「保活」要碰系统的地方，全收在这一个接口后面。
///
/// 抽成接口与 [ClassReminderNotifier] 同理：测试塞假的，平台差异收在一处。
/// 契约同样是**任何方法都不抛异常**，最差返回 false。
abstract interface class KeepAlivePlatform {
  /// 当前平台有没有系统级「保活」概念（Android 有，Web 没有）。
  bool get isSupported;

  /// 现在是否已在电池优化白名单里（`isIgnoringBatteryOptimizations`）。
  Future<bool> isIgnoringBatteryOptimizations();

  /// 弹系统的「允许忽略电池优化」确认框，返回用户是否放行。
  ///
  /// 部分机型不允许直接弹框，会退化成打开电池优化列表页 —— 那种情况返回 false，
  /// 由界面提示用户到列表里手动放行。
  Future<bool> requestIgnoreBatteryOptimizations();

  /// 打开电池优化列表页（用户手动找本应用放行用）。
  Future<bool> openBatteryOptimizationSettings();

  /// 打开系统的「省电模式」设置页。
  ///
  /// 低电量自动开启省电模式的机型（低端机尤其常见）会连白名单里的闹钟一起拦，
  /// 所以指引里要有这一步：让用户关掉省电模式或允许本应用后台运行。
  Future<bool> openBatterySaverSettings();

  /// 尝试打开「自启动管理」页。
  ///
  /// 国产 ROM（小米/华为/OPPO/vivo 等）的自启动管理没有标准入口，
  /// 这里按机型逐个尝试已知组件名，全都失败就退回**应用详情页**
  /// （用户从那里点「电池」/「自启动」也能到达）。返回是否跳成功。
  Future<bool> openAutoStartSettings();

  /// 打开系统的应用详情页（万能兜底）。
  Future<bool> openAppDetailsSettings();

  /// 用系统浏览器打开 [url]（GitHub 项目页等外部链接）。
  /// 打不开（没浏览器 / 平台不支持）返回 false。
  Future<bool> openUrl(String url);
}

/// 按当前平台建一个保活口。
KeepAlivePlatform createKeepAlivePlatform() => impl.createKeepAlivePlatform();

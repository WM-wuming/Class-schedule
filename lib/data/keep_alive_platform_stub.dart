import 'keep_alive_platform.dart';

/// 兜底实现：没有 `dart:io` 的平台（Web）。
///
/// 浏览器里没有「后台 / 自启动 / 电池优化」这些概念，全部不支持，
/// 由 [isSupported] 为 false 让设置页如实说明。
KeepAlivePlatform createKeepAlivePlatform() => const _UnsupportedKeepAlivePlatform();

class _UnsupportedKeepAlivePlatform implements KeepAlivePlatform {
  const _UnsupportedKeepAlivePlatform();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => false;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => false;

  @override
  Future<bool> openBatteryOptimizationSettings() async => false;

  @override
  Future<bool> openAutoStartSettings() async => false;

  @override
  Future<bool> openAppDetailsSettings() async => false;

  @override
  Future<bool> openUrl(String url) async => false;
}

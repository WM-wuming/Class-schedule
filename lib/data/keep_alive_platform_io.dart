import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'keep_alive_platform.dart';

/// `dart:io` 平台（主要是 Android）的真实现。
///
/// 全部能力走 MethodChannel `keep_alive`，原生侧见 `MainActivity.kt`。
/// 通道方法不存在（老版本原生代码、其它桌面平台）时 MethodChannel 会抛
/// `MissingPluginException`，这里一律接住退回 false —— 保活指引打不开
/// 不该影响课表本身。
KeepAlivePlatform createKeepAlivePlatform() => MethodChannelKeepAlivePlatform();

class MethodChannelKeepAlivePlatform implements KeepAlivePlatform {
  static const MethodChannel _channel = MethodChannel('keep_alive');

  /// 只有 Android 有「自启动管理 / 电池优化白名单」这套东西。
  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } catch (error) {
      debugPrint('保活通道 $method 失败：$error');
      return null;
    }
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _invoke<bool>('isIgnoringBatteryOptimizations') ?? false;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _invoke<bool>('requestIgnoreBatteryOptimizations') ?? false;

  @override
  Future<bool> openBatteryOptimizationSettings() async =>
      await _invoke<bool>('openBatteryOptimizationSettings') ?? false;

  @override
  Future<bool> openAutoStartSettings() async =>
      await _invoke<bool>('openAutoStartSettings') ?? false;

  @override
  Future<bool> openAppDetailsSettings() async =>
      await _invoke<bool>('openAppDetailsSettings') ?? false;
}

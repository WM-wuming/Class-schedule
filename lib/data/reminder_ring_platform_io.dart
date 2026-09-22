import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reminder_ring_platform.dart';

/// `dart:io` 平台（主要是 Android）的真实现，走 MethodChannel `reminder_ring`。
///
/// 通道方法不存在（老版本原生代码、桌面平台）时 MethodChannel 会抛
/// `MissingPluginException`，这里接住返回 null —— 「查不到」按未知处理，
/// 界面对未知状态不显示任何提示，而不是误报「没授权」。
ReminderRingPlatform createReminderRingPlatform() =>
    MethodChannelReminderRingPlatform();

class MethodChannelReminderRingPlatform implements ReminderRingPlatform {
  static const MethodChannel _channel = MethodChannel('reminder_ring');

  /// 只有 Android 有「勿扰打扰」授权这套东西。
  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool?> dndAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isDndAccessGranted');
    } catch (error) {
      debugPrint('查询勿扰豁免状态失败：$error');
      return null;
    }
  }

  @override
  Future<bool> openDndAccessSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openDndAccessSettings') ?? false;
    } catch (error) {
      debugPrint('打开勿扰授权页失败：$error');
      return false;
    }
  }
}

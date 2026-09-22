import 'reminder_ring_platform.dart';

/// 没有 `dart:io` 的平台（Web）没有「勿扰豁免」概念，一律按不支持处理。
ReminderRingPlatform createReminderRingPlatform() =>
    const _UnsupportedReminderRingPlatform();

class _UnsupportedReminderRingPlatform implements ReminderRingPlatform {
  const _UnsupportedReminderRingPlatform();

  @override
  bool get isSupported => false;

  @override
  Future<bool?> dndAccessGranted() async => null;

  @override
  Future<bool> openDndAccessSettings() async => false;
}

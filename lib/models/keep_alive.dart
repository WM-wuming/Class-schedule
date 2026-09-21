import 'package:flutter/foundation.dart';

/// 「保活」相关的用户设置。
///
/// 现在只有一项：开机自启。它记录的是**用户在 App 里表达过的意愿**——
/// 真正的开关在系统里（国产 ROM 的自启动管理没有公开 API），App 里这个
/// 开关负责记住「用户想要自启」，并在打开时把用户带到对应的系统页面上。
@immutable
class KeepAliveSettings {
  const KeepAliveSettings({this.autoStart = false});

  /// 默认值：不开机自启。
  factory KeepAliveSettings.initial() => const KeepAliveSettings();

  /// 用户希望开机自启（重启后自动恢复上课提醒的闹钟）。
  final bool autoStart;

  KeepAliveSettings copyWith({bool? autoStart}) =>
      KeepAliveSettings(autoStart: autoStart ?? this.autoStart);

  Map<String, dynamic> toJson() => <String, dynamic>{'autoStart': autoStart};

  /// 坏数据一律退回默认值，不让存档把 App 搞挂。
  static KeepAliveSettings fromJson(Map<String, dynamic> json) =>
      KeepAliveSettings(autoStart: json['autoStart'] == true);

  @override
  bool operator ==(Object other) =>
      other is KeepAliveSettings && other.autoStart == autoStart;

  @override
  int get hashCode => autoStart.hashCode;
}

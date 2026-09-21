import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/next_class.dart';
import 'widget_updater.dart';

/// Android 实现：把条目 JSON 交给原生（MainActivity → NextClassWidgetProvider）。
class MethodChannelWidgetUpdater implements WidgetUpdater {
  static const MethodChannel _channel = MethodChannel('next_class_widget');

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> update(List<NextClassEntry> entries) async {
    if (!isSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<bool>('updateSchedule', <String, Object>{
        'json': jsonEncode(
          <Map<String, Object>>[
            for (final NextClassEntry e in entries) e.toJson(),
          ],
        ),
      });
    } on PlatformException {
      // 原生侧出问题就维持旧显示。
    } on MissingPluginException {
      // 引擎还没注册通道（极少见），同样维持旧显示。
    }
  }
}

WidgetUpdater createPlatformWidgetUpdater() => MethodChannelWidgetUpdater();

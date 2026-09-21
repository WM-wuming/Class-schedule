import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/keep_alive.dart';

/// 保活设置的本地存储。
///
/// 契约和 [ReminderStore] 一样：**任何方法都不抛异常**——读失败返回 null
/// （调用方用默认值），写失败静默（大不了下次重设）。
abstract interface class KeepAliveStore {
  /// 读上次保存的设置；没存过或读不出来时返回 null。
  Future<KeepAliveSettings?> read();

  /// 覆盖保存。
  Future<void> write(KeepAliveSettings settings);
}

/// 默认实现：各平台的 `SharedPreferences`。
class PrefsKeepAliveStore implements KeepAliveStore {
  const PrefsKeepAliveStore();

  /// 存储键。带版本后缀：将来字段结构变了可以直接换键，不会读到旧结构。
  static const String storageKey = 'keep_alive_v1';

  @override
  Future<KeepAliveSettings?> read() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return KeepAliveSettings.fromJson(decoded);
    } catch (error) {
      debugPrint('读取保活设置失败：$error');
      return null;
    }
  }

  @override
  Future<void> write(KeepAliveSettings settings) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(settings.toJson()));
    } catch (error) {
      debugPrint('保存保活设置失败：$error');
    }
  }
}

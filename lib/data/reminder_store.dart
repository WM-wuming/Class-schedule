import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// 上课提醒设置的本地存储。
///
/// 契约和 [JwAccountStore] 一样：**任何方法都不抛异常**。存不上只是「下次打开要重设」，
/// 不该因此把 App 顶掉 —— 读失败返回 null、写失败静默。
abstract interface class ReminderStore {
  /// 读上次保存的设置；没存过或读不出来时返回 null（调用方用默认值）。
  Future<ClassReminderSettings?> read();

  /// 覆盖保存。
  Future<void> write(ClassReminderSettings settings);
}

/// 默认实现：各平台的 `SharedPreferences`。
class PrefsReminderStore implements ReminderStore {
  const PrefsReminderStore();

  /// 存储键。带版本后缀：将来字段结构变了可以直接换键，不会读到旧结构。
  static const String storageKey = 'class_reminder_v1';

  @override
  Future<ClassReminderSettings?> read() async {
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
      return ClassReminderSettings.fromJson(decoded);
    } catch (error) {
      debugPrint('读取上课提醒设置失败：$error');
      return null;
    }
  }

  @override
  Future<void> write(ClassReminderSettings settings) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(settings.toJson()));
    } catch (error) {
      debugPrint('保存上课提醒设置失败：$error');
    }
  }
}

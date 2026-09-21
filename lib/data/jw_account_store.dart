import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jw_client.dart';

/// 本机保存的账户信息。
///
/// 只存跟「登录这件事」有关的：登录换来的**会话 Cookie**、登录用的**学号**，以及一份
/// **学生信息快照**（冷启动时先拿它把「我的信息」页填上，联网读到权威值后再覆盖）。
///
/// 两个明确的边界：
/// * **密码只有用户明确勾选「记住密码」才存**（见 [password]）——教务系统的验证码是
///   一次性的，存了密码也没法自动重登，它只用来在登录页免输一遍；不勾就不落盘。
/// * **不存课表**。课表每次都实时从教务系统拉，这里只解决「不用反复登录」。
///
/// 注意 [password] 与会话 Cookie 同样敏感，落在同一处应用私有空间（Android 的
/// SharedPreferences 等），同机其它 App 读不到，卸载即清。
@immutable
class JwStoredAccount {
  const JwStoredAccount({
    required this.cookie,
    this.account = '',
    this.password = '',
    this.student,
    this.savedAt,
  });

  /// 登录会话 Cookie（`name=value; name2=value2` 形式）。
  final String cookie;

  /// 登录用的学号 / 账号。只为登录页回填，不参与任何请求。
  final String account;

  /// 用户勾选「记住密码」时保存的登录密码；空串 = 没存（默认）。
  ///
  /// 只为登录页免输一遍，**绝不**参与自动重登 —— 教务系统有一次性验证码，
  /// 拿着密码也登不进去。不勾选时这里永远是空串。
  final String password;

  /// 学生信息快照。
  final JwStudentInfo? student;

  /// 最后一次写入的时间。
  final DateTime? savedAt;

  /// 什么都没存到（这种内容不该写进本地）。
  bool get isEmpty => cookie.trim().isEmpty && account.trim().isEmpty;

  /// 会话 / 学号 / 学生信息是否与 [other] 完全一致（**不比 [savedAt]**）。
  ///
  /// 用来避免每次读主页面都往磁盘写一遍同样的内容。
  bool sameContentAs(JwStoredAccount? other) {
    if (other == null) {
      return false;
    }
    if (cookie != other.cookie ||
        account != other.account ||
        password != other.password) {
      return false;
    }
    final JwStudentInfo? mine = student;
    final JwStudentInfo? theirs = other.student;
    if (mine == null || theirs == null) {
      return mine == theirs;
    }
    return mine.name == theirs.name &&
        mine.studentId == theirs.studentId &&
        mine.department == theirs.department &&
        mine.major == theirs.major &&
        mine.className == theirs.className;
  }

  Map<String, Object?> toJson() {
    final JwStudentInfo? info = student;
    return <String, Object?>{
      'cookie': cookie,
      'account': account,
      // 不勾「记住密码」就是空串；空串也写进去，明确表达「没存密码」。
      'password': password,
      'savedAt': (savedAt ?? DateTime.now()).millisecondsSinceEpoch,
      if (info != null)
        'student': <String, Object?>{
          'name': info.name,
          'studentId': info.studentId,
          if (info.department != null) 'department': info.department,
          if (info.major != null) 'major': info.major,
          if (info.className != null) 'className': info.className,
        },
    };
  }

  /// 解析本地存的内容；结构不认识或内容为空时返回 null（当作**没存过**）。
  ///
  /// 刻意做得很宽容：本地文件可能是上一版 App 写的、也可能被用户手工改过，
  /// 读不懂就当没存过、让用户重新登录一次，比抛异常把 App 顶掉好。
  static JwStoredAccount? fromJson(Map<String, dynamic> json) {
    final DateTime? savedAt = switch (json['savedAt']) {
      final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
      _ => null,
    };
    final JwStoredAccount parsed = JwStoredAccount(
      cookie: _string(json['cookie']),
      account: _string(json['account']),
      password: _string(json['password']),
      student: _studentFrom(json['student']),
      savedAt: savedAt,
    );
    return parsed.isEmpty ? null : parsed;
  }

  static JwStudentInfo? _studentFrom(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final JwStudentInfo info = JwStudentInfo(
      name: _string(raw['name']),
      studentId: _string(raw['studentId']),
      department: _nullableString(raw['department']),
      major: _nullableString(raw['major']),
      className: _nullableString(raw['className']),
    );
    return info.isEmpty ? null : info;
  }

  static String _string(Object? value) => value is String ? value : '';

  static String? _nullableString(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 账户信息的本地存储。
///
/// 契约：**任何方法都不抛异常**。存不上只是「下次要重新登录」，不该因此把 App 顶掉 ——
/// 所以读失败返回 null、写失败静默、清失败也只是留着旧值。
abstract interface class JwAccountStore {
  /// 读上次保存的账户信息；没存过或读不出来时返回 null。
  Future<JwStoredAccount?> read();

  /// 覆盖保存（内容为空时实现可以选择不写）。
  Future<void> write(JwStoredAccount account);

  /// 清除（退出登录）。
  Future<void> clear();
}

/// 默认实现：各平台的 `SharedPreferences`。
///
/// Android 落在应用私有的 `SharedPreferences` 里，iOS/macOS 落 `NSUserDefaults`，
/// Web 落 `localStorage`，桌面落各自的应用配置目录。都在**应用私有空间**内，
/// 同机其它 App 读不到，卸载 App 会一并清掉。
class PrefsAccountStore implements JwAccountStore {
  const PrefsAccountStore();

  /// 存储键。带版本后缀：将来字段结构变了可以直接换键，不会读到旧结构。
  static const String storageKey = 'jw_account_v1';

  @override
  Future<JwStoredAccount?> read() async {
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
      return JwStoredAccount.fromJson(decoded);
    } catch (error) {
      debugPrint('读取本机账户信息失败：$error');
      return null;
    }
  }

  @override
  Future<void> write(JwStoredAccount account) async {
    if (account.isEmpty) {
      return; // 空内容等于没存过，别在本地留个空壳
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(account.toJson()));
    } catch (error) {
      debugPrint('保存账户信息失败：$error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (error) {
      debugPrint('清除账户信息失败：$error');
    }
  }
}

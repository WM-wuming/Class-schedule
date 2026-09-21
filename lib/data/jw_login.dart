import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'jw_exception.dart';
import 'jw_http.dart';

/// 提交一次登录表单后的原始结果。
///
/// 这里**不判断成败**：教务系统可能返回登录页（明确报错），也可能返回跳转后的页面。
/// 真正可靠的判据是「拿着新会话去读主页面能不能读通」，所以最终判断由
/// `JwTimetableClient.login()` 做。
@immutable
class JwLoginAttempt {
  const JwLoginAttempt({required this.cookie, this.errorMessage});

  /// 响应里下发的会话 Cookie（`name=value` 串），没有则为空。
  final String cookie;

  /// 登录页里写明的失败原因；null 表示教务系统没有报错。
  ///
  /// 已经翻译成用户能看懂的话（见 [JwLoginPage.errorOf]）。
  final String? errorMessage;

  /// 教务系统是否明确报了错。
  bool get reported => errorMessage != null;
}

/// 一次登录过程。
///
/// 正方教务系统的验证码是**一次性**的：提交失败后那张图就作废了，必须重新取一张。
/// 所以这个对象用完即弃 —— 失败后重新调 `beginLogin()`，不要复用它。
class JwLoginSession {
  JwLoginSession._(
    this._transport,
    this._loginUrl,
    this._userAgent, {
    required this.cookie,
    required this.image,
  });

  /// 开始登录：先要一张验证码，并带上调用方当前的会话。
  ///
  /// 带 Cookie 是必须的 —— 验证码校验绑在会话上，请求验证码时服务端同时下发了
  /// 临时 `JSESSIONID`，提交时得原样带回去。
  static Future<JwLoginSession> begin({
    required JwDetailedTransport transport,
    required Uri captchaUrl,
    required Uri loginUrl,
    required String userAgent,
    required String cookie,
  }) async {
    final JwHttpResponse response = await transport(
      'GET',
      captchaUrl,
      '',
      <String, String>{
        if (cookie.trim().isNotEmpty) 'X-JW-Cookie': cookie.trim(),
        // 绕开缓存，否则可能拿到同一张验证码（登录页的 JS 也是这么做的）
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'User-Agent': userAgent,
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    if (!response.isImage || response.bytes.isEmpty) {
      throw JwException(
        '验证码接口没有返回图片（HTTP ${response.statusCode}'
        '${response.contentType == null ? '' : ' · ${response.contentType}'}），'
        '教务系统可能已改版',
      );
    }

    return JwLoginSession._(transport, loginUrl, userAgent,
      // 请求验证码时服务端会下发临时会话，和调用方原有的会话合并（新的覆盖旧的）。
      cookie: JwCookieJar.merge(cookie, response.cookie),
      image: response.bytes,
    );
  }

  /// 验证码图片（JPEG），直接丢给 `Image.memory` 即可。
  final Uint8List image;

  /// 登录前的会话（含请求验证码时拿到的临时会话）。
  final String cookie;

  final JwDetailedTransport _transport;
  final Uri _loginUrl;
  final String _userAgent;

  /// 提交账号、密码与验证码。
  Future<JwLoginAttempt> submit({
    required String account,
    required String password,
    required String captcha,
  }) async {
    final JwHttpResponse response = await _transport(
      'POST',
      _loginUrl,
      JwLoginForm.body(account: account, password: password, captcha: captcha),
      <String, String>{
        if (cookie.trim().isNotEmpty) 'X-JW-Cookie': cookie.trim(),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': _userAgent,
        'Referer': _loginUrl.toString(),
        'Origin': _originOf(_loginUrl),
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );

    return JwLoginAttempt(
      cookie: JwCookieJar.merge(cookie, response.cookie),
      errorMessage: JwLoginPage.errorOf(response.text),
    );
  }

  static String _originOf(Uri url) => Uri(
    scheme: url.scheme,
    host: url.host,
    port: url.hasPort ? url.port : null,
  ).toString();
}

/// 合并 Cookie：后出现的同名 Cookie 覆盖先前的。
abstract final class JwCookieJar {
  /// 把 [incoming] 合并进 [existing]，两边都是 `name=value; name2=value2` 形式的串。
  ///
  /// 实现在 [mergeCookies]：传输层跟随跳转时也要用同一套规则合并每一跳的 `Set-Cookie`。
  static String merge(String existing, String incoming) =>
      mergeCookies(existing, incoming);
}

/// 登录表单：字段与编码方式照抄登录页的 `submitForm1()`。
abstract final class JwLoginForm {
  /// `base64(账号) + "%%%" + base64(密码)`，对应页面里的 `encodeInp`。
  static String encoded(String account, String password) =>
      '${_base64(account)}%%%${_base64(password)}';

  /// 提交用的表单正文。
  ///
  /// 两个细节照抄页面 JS：
  /// * `userPassword` 是**空**的 —— 页面在提交前把密码框清空，真正的密码只在 `encoded` 里；
  /// * `encoded` 含 `+` `/` `=`，必须 URL 编码，否则 `+` 会被服务端当成空格。
  static String body({
    required String account,
    required String password,
    required String captcha,
  }) {
    final Map<String, String> fields = <String, String>{
      'userAccount': account,
      'userPassword': '',
      'RANDOMCODE': captcha,
      'encoded': encoded(account, password),
    };
    return fields.entries
        .map(
          (MapEntry<String, String> e) =>
              '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  static String _base64(String value) => base64.encode(utf8.encode(value));
}

/// 解析登录响应：判断这次提交是否被拒，并取出教务系统写的原因。
abstract final class JwLoginPage {
  /// 教务系统没写原因（或写的还是默认的「请先登录系统」）时的兜底提示。
  static const String fallbackMessage = '登录失败：账号、密码或验证码不正确';

  /// 失败信息所在的 `<li id="showMsg">…</li>`。
  static final RegExp _showMsgPattern = RegExp(
    'id\\s*=\\s*["\']showMsg["\'][^>]*>(.*?)(?:</li>|</div>)',
    dotAll: true,
    caseSensitive: false,
  );

  /// 登录页的账号输入框 —— 响应里出现它就说明「没登进去」。
  static final RegExp _formPattern = RegExp(
    'name\\s*=\\s*["\']userAccount["\']',
    caseSensitive: false,
  );

  /// 登录页 `#showMsg` 的默认文案（什么都没发生时的占位）。
  static const String _placeholder = '请先登录系统';

  static final RegExp _tagPattern = RegExp(r'<[^>]*>');

  /// 解析失败原因；返回 null 表示这次响应**不像登录页**，可以当作成功。
  static String? errorOf(String html) {
    final RegExpMatch? match = _showMsgPattern.firstMatch(html);
    if (match == null && !_formPattern.hasMatch(html)) {
      return null;
    }
    final String message = _plain(match?.group(1) ?? '');
    return message.isEmpty || message == _placeholder
        ? fallbackMessage
        : message;
  }

  static String _plain(String html) => html
      .replaceAll(_tagPattern, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

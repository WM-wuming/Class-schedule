import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'jw_exception.dart';
import 'jw_http.dart';

/// 浏览器端用 `fetch` 发请求。
///
/// 浏览器有两条硬限制，所以 Web 端必须配合同源反向代理（`tool/jw_proxy.dart`）使用：
/// 1. JS **不能设置 `Cookie` 请求头**（被浏览器列为禁止头），也无法读取跨域响应 —— 所以会话
///    放在自定义头 `X-JW-Cookie` 里，由代理翻译成真正的 `Cookie` 转发给教务系统；
/// 2. 应用通过同源路径 `/jw/...` 访问代理，浏览器认为是同源请求，**完全不涉及 CORS**。
Future<String> sendRequest(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) async {
  final web.Headers requestHeaders = web.Headers();
  // 注意：external 互操作成员不能直接 tear-off，必须用闭包包一层
  headers.forEach((String name, String value) {
    requestHeaders.set(name, value);
  });

  try {
    final web.Response response = await web.window
        .fetch(
          url.toString().toJS,
          web.RequestInit(
            method: method,
            headers: requestHeaders,
            body: body.isEmpty ? null : body.toJS,
          ),
        )
        .toDart;

    final String text = (await response.text().toDart).toDart;
    if (response.status != 200) {
      throw JwException(
        '教务系统返回 HTTP ${response.status}'
        '${text.trim().isEmpty ? '' : '：${_snippet(text)}'}',
      );
    }
    return text;
  } on JwException {
    rethrow;
  } catch (error) {
    throw JwException(
      '浏览器请求失败：$error\n'
      '若为跨域错误，请用同源代理启动：dart run tool/jw_proxy.dart',
    );
  }
}

/// 浏览器端**无法**完成登录，这里直接给出可读的说明。
///
/// 两个硬限制叠在一起让浏览器登录不成立：
/// 1. JS 读不到响应头，`Set-Cookie` 里的新会话拿不到（跨域响应更是整个不可读）；
/// 2. 就算浏览器自己把 Cookie 存下来，教务系统下发的是 `Path=/gzasc_jsxsd`，
///    而 App 访问的是网关的 `/jw/...`，浏览器不会把这份 Cookie 带上。
///
/// 所以 Web 端的会话只能由网关持有，用 `dart run tool/jw_proxy.dart --cookie=...` 启动。
Future<JwHttpResponse> sendDetailed(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) => Future<JwHttpResponse>.error(
  const JwException(
    'Web 端不支持在 App 内登录教务系统：浏览器读不到教务系统下发的会话。\n'
    '请让网关持有会话：dart run tool/jw_proxy.dart --cookie="JSESSIONID=..."',
  ),
);

String _snippet(String text) =>
    text.length <= 120 ? text : '${text.substring(0, 120)}…';

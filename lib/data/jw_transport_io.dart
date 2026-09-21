import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'jw_exception.dart';
import 'jw_http.dart';

/// 复用一个 [HttpClient]。
///
/// 之前每次请求都新建 client 并在结束时 `close(force: true)`，等于每次都要重新做
/// TCP + TLS 握手；对国内教务系统这一项就要几百毫秒。改成进程级复用后，第二个请求起
/// 直接走已建立的连接（实测数据见 README 的性能一节）。
HttpClient? _sharedClient;

HttpClient get _client => _sharedClient ??= HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..idleTimeout = const Duration(minutes: 5)
  ..maxConnectionsPerHost = 6
  ..autoUncompress = true;

/// 关闭共享连接（下次请求会自动重建）。测试里用来模拟「冷启动」。
void closeSharedClient() {
  _sharedClient?.close(force: true);
  _sharedClient = null;
}

/// 把请求头里的 `X-JW-Cookie` 翻译成真正的 `Cookie`。
///
/// 浏览器不允许 JS 设置 `Cookie` 头，所以两端统一用 `X-JW-Cookie` 传会话，
/// 由各平台传输层在最后一刻翻译（见 `jw_transport_*.dart`）。
Map<String, String> _translateHeaders(Map<String, String> headers) {
  final Map<String, String> effective = <String, String>{
    for (final MapEntry<String, String> entry in headers.entries)
      if (entry.key.toLowerCase() != 'x-jw-cookie') entry.key: entry.value,
  };
  final String? session = headers['X-JW-Cookie'];
  if (session != null && session.trim().isNotEmpty) {
    effective['Cookie'] = session.trim();
  }
  return effective;
}

/// 把网络层的异常统一翻译成可读的 [JwException]。
Future<T> _guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on JwException {
    rethrow;
  } on SocketException catch (error) {
    throw JwException('无法连接教务系统：${error.message}');
  } on HandshakeException {
    throw const JwException('与教务系统的 HTTPS 握手失败，可能需要代理或校园网');
  } on TimeoutException {
    throw const JwException('连接教务系统超时，请检查网络后重试');
  } on HttpException catch (error) {
    throw JwException('网络错误：${error.message}');
  }
}

/// 发一次请求并读回完整响应。调用方负责判断状态码。
///
/// [followRedirects] 默认交给 `HttpClient` 自己处理；登录流程会关掉它自己跟
/// （原因见 [sendDetailed]）。
Future<(HttpClientResponse, Uint8List)> _exchange(
  String method,
  Uri url,
  String body,
  Map<String, String> headers, {
  bool followRedirects = true,
}) async {
  final HttpClientRequest request = method == 'GET'
      ? await _client.getUrl(url)
      : await _client.postUrl(url);
  request.followRedirects = followRedirects;
  _translateHeaders(headers).forEach(request.headers.set);
  if (body.isNotEmpty) {
    request.add(utf8.encode(body));
  }

  final HttpClientResponse response = await request.close().timeout(
    const Duration(seconds: 20),
  );
  final Uint8List bytes = Uint8List.fromList(
    await response.fold<List<int>>(
      <int>[],
      (List<int> acc, List<int> chunk) => acc..addAll(chunk),
    ),
  );
  return (response, bytes);
}

/// 用 `dart:io` 发送请求（GET / POST），返回按响应字符集解码后的文本。
///
/// 适用于 Android / iOS / Windows / macOS / Linux。
Future<String> sendRequest(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) => _guard(() async {
  final (HttpClientResponse response, Uint8List bytes) = await _exchange(
    method,
    url,
    body,
    headers,
  );
  if (response.statusCode != HttpStatus.ok) {
    // POST 的 302 不会被 dart:io 自动跟随（只跟随 GET 的），所以这里能收到它 ——
    // 课表接口跳转基本都意味着会话过期了，直接说清楚比甩个状态码有用。
    throw JwException(
      response.statusCode == HttpStatus.found
          ? '教务系统要求跳转（HTTP 302），会话可能已失效，请重新登录'
          : '教务系统返回 HTTP ${response.statusCode}',
    );
  }

  final String? charset = response.headers.contentType?.charset;
  final Encoding encoding =
      (charset == null ? null : Encoding.getByName(charset)) ?? utf8;
  return encoding.decode(bytes);
});

/// 自己跟随跳转时允许的最大跳数（和 `HttpClient` 的默认值一致）。
const int _maxRedirects = 5;

/// 是否是需要跟随的跳转状态码。
bool _isRedirect(int statusCode) =>
    statusCode == HttpStatus.movedPermanently ||
    statusCode == HttpStatus.found ||
    statusCode == HttpStatus.seeOther ||
    statusCode == HttpStatus.temporaryRedirect ||
    statusCode == HttpStatus.permanentRedirect;

/// 同 [sendRequest]，但额外返回原始字节与响应里的 `Set-Cookie`。
///
/// 登录流程要用：验证码是 JPEG（不能按文本解码），登录成功的新会话只在
/// `Set-Cookie` 里。普通请求不需要它，继续用 [sendRequest]。
///
/// **跳转由这里手动跟，不用 `HttpClient` 的自动跟随**：
/// * `dart:io` 的 `HttpClient` 只对 `GET`/`HEAD` 跟随 30x，`POST` 只认 303
///   （SDK 里 `_HttpClientResponse.isRedirect` 的判定），而教务系统登录成功后是
///   POST → **302** 跳到主页面，自动跟随时等于把 302 原样交回来、被当成失败；
/// * 就算它肯跟，`Set-Cookie` 也只在**那一跳的响应头**里，跟完之后拿到的响应体是最后一跳的，
///   新会话照样会丢。
///
/// 所以这里逐跳读 `Set-Cookie` 与 `Location`：Cookie 累积下来（同名新的覆盖旧的），
/// 30x 之后按浏览器语义改成 GET 再请求（只有 307/308 保留原方法和正文）。
Future<JwHttpResponse> sendDetailed(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) => _guard(() async {
  Uri target = url;
  String currentMethod = method;
  String currentBody = body;
  Map<String, String> currentHeaders = headers;

  /// 后续跳转要带上的完整会话（调用方原有的 + 各跳下发的）。
  String jar = headers['X-JW-Cookie']?.trim() ?? '';

  /// 本次响应里服务端新下发的 Cookie（返回给上层的就是它）。
  String received = '';

  for (int hop = 0; hop <= _maxRedirects; hop++) {
    final (HttpClientResponse response, Uint8List bytes) = await _exchange(
      currentMethod,
      target,
      currentBody,
      currentHeaders,
      followRedirects: false,
    );

    // dart:io 把多条 Set-Cookie 放在同一个头的多个值里。
    final String hopCookie = normalizeSetCookie(
      response.headers['set-cookie'] ?? const <String>[],
    );
    jar = mergeCookies(jar, hopCookie);
    received = mergeCookies(received, hopCookie);

    final String? location = response.headers.value(
      HttpHeaders.locationHeader,
    );
    if (!_isRedirect(response.statusCode) || location == null) {
      if (response.statusCode >= HttpStatus.badRequest) {
        throw JwException('教务系统返回 HTTP ${response.statusCode}');
      }
      return JwHttpResponse(
        statusCode: response.statusCode,
        bytes: bytes,
        cookie: received,
        contentType: response.headers.contentType?.mimeType,
        charset: response.headers.contentType?.charset,
      );
    }

    // 只有 307/308 要求原样重发；其余（含登录用的 302）按浏览器的做法降级成 GET。
    final bool keepMethod =
        response.statusCode == HttpStatus.temporaryRedirect ||
        response.statusCode == HttpStatus.permanentRedirect;
    if (!keepMethod) {
      currentMethod = 'GET';
      currentBody = '';
    }

    final Uri next = target.resolve(location);
    // 跨站跳转不带会话（与浏览器的第三方 Cookie 策略一致）。
    final bool sameSite = next.host == url.host && next.scheme == url.scheme;
    currentHeaders = <String, String>{
      for (final MapEntry<String, String> entry in headers.entries)
        if (entry.key.toLowerCase() != 'x-jw-cookie')
          if (keepMethod || entry.key.toLowerCase() != 'content-type')
            entry.key: entry.value,
      if (sameSite && jar.isNotEmpty) 'X-JW-Cookie': jar,
    };
    target = next;
  }

  throw const JwException('教务系统跳转次数过多，请稍后重试');
});

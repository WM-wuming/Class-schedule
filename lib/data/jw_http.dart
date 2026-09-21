import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一次带**响应头/原始字节**的 HTTP 响应。
///
/// 只有登录流程需要它：
/// * 验证码接口返回的是 JPEG，按字符串解码会毁掉像素；
/// * 登录成功后要读响应里的 `Set-Cookie` 才能拿到新会话。
///
/// 普通课表请求继续用 [JwTransport]（只关心响应正文）。
@immutable
class JwHttpResponse {
  const JwHttpResponse({
    required this.statusCode,
    required this.bytes,
    this.cookie = '',
    this.contentType,
    this.charset,
  });

  /// HTTP 状态码。
  final int statusCode;

  /// 原始响应体。
  final Uint8List bytes;

  /// 响应里所有 `Set-Cookie` 归一后的结果，形如 `a=1; b=2`。
  ///
  /// **只保留 `name=value`**：`Path` / `Expires` / `Domain` / `HttpOnly` / `Secure`
  /// 这些属性由传输层丢掉，值为空的 Cookie（服务端在删 Cookie）也一并丢弃 ——
  /// 这样上层可以直接把它拼进 `Cookie` 请求头，不用再解析一遍属性。
  final String cookie;

  /// 响应体的 MIME 类型，例如 `image/jpeg`。
  final String? contentType;

  /// 响应体声明的字符集，未声明时为 null。
  final String? charset;

  /// 按响应声明的字符集解码后的正文（教务系统页面都是 UTF-8）。
  String get text =>
      (charset == null ? null : Encoding.getByName(charset))?.decode(bytes) ??
      utf8.decode(bytes, allowMalformed: true);

  /// 是否为图片响应（登录验证码）。
  bool get isImage => contentType != null && contentType!.startsWith('image/');
}

/// 发送一次请求并返回完整响应（含原始字节与 `Set-Cookie`）。
typedef JwDetailedTransport =
    Future<JwHttpResponse> Function(
      String method,
      Uri url,
      String body,
      Map<String, String> headers,
    );

/// 把两份 `name=value; …` 形式的 Cookie 串合并成一份；同名以 [incoming] 为准。
///
/// 用于把服务端新下发的 Cookie（例如登录成功换到的新 `JSESSIONID`）盖到旧会话上。
/// 值为空的项会被丢掉（等同于服务端的删除指令）。
String mergeCookies(String existing, String incoming) {
  final Map<String, String> jar = <String, String>{};
  for (final String source in <String>[existing, incoming]) {
    for (final String part in source.split(';')) {
      final int index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final String name = part.substring(0, index).trim();
      final String value = part.substring(index + 1).trim();
      if (name.isEmpty || value.isEmpty) {
        continue;
      }
      jar[name] = value;
    }
  }
  return jar.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');
}

/// 把 `Set-Cookie` 的若干行归一成 `name=value; name2=value2`。
///
/// 传进来的每行可以是完整的 `Set-Cookie` 值（带属性），也可以已经是 `name=value`。
/// 属性与「值为空」的删除指令都会被丢掉。
String normalizeSetCookie(Iterable<String> lines) {
  final Map<String, String> jar = <String, String>{};
  for (final String line in lines) {
    final String pair = line.split(';').first.trim();
    final int index = pair.indexOf('=');
    if (index <= 0) {
      continue;
    }
    final String name = pair.substring(0, index).trim();
    final String value = pair.substring(index + 1).trim();
    if (name.isEmpty || value.isEmpty) {
      continue; // 空值是服务端的删除指令，等同于「这个 Cookie 没了」
    }
    jar[name] = value;
  }
  return jar.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');
}

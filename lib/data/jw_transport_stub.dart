import 'jw_exception.dart';
import 'jw_http.dart';

/// 兜底实现：既没有 `dart:io` 也没有 JS 运行时的平台。
Future<String> sendRequest(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) => Future<String>.error(
  const JwException('当前平台不支持访问教务系统，请在 Android / iOS / 桌面端或 Web（配合代理）运行'),
);

/// 兜底实现：同 [sendRequest]，登录流程在这个平台上同样不可用。
Future<JwHttpResponse> sendDetailed(
  String method,
  Uri url,
  String body,
  Map<String, String> headers,
) => Future<JwHttpResponse>.error(
  const JwException('当前平台不支持登录教务系统'),
);

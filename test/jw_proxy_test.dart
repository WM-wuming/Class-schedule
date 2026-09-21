import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/jw_proxy.dart';
import 'fakes.dart';

/// 网关（同源反向代理）的集成测试：上游用本地假的教务系统。
void main() {
  late HttpServer upstream;
  late HttpServer gateway;
  late Directory webRoot;
  final List<String> upstreamCookies = <String>[];
  final List<String> upstreamMethods = <String>[];
  final List<String> upstreamTargets = <String>[];
  var upstreamHits = 0;

  setUp(() async {
    upstreamCookies.clear();
    upstreamMethods.clear();
    upstreamTargets.clear();
    upstreamHits = 0;

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((HttpRequest request) async {
      upstreamHits++;
      upstreamCookies.add(request.headers.value('cookie') ?? '');
      upstreamMethods.add(request.method);
      upstreamTargets.add(request.uri.toString());
      final String body = await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..write('$body\n$fixtureHtml');
      await request.response.close();
    });

    webRoot = await Directory.systemTemp.createTemp('jw_web');
    File('${webRoot.path}${Platform.pathSeparator}index.html')
        .writeAsStringSync('<html>APP</html>');
    File('${webRoot.path}${Platform.pathSeparator}main.dart.js')
        .writeAsStringSync('console.log(1)');

    gateway = await startGateway(
      port: 0,
      root: webRoot.path,
      upstream: 'http://127.0.0.1:${upstream.port}/gzasc_jsxsd',
      cacheSeconds: 60,
      log: (String _) {},
    );
  });

  tearDown(() async {
    await gateway.close(force: true);
    await upstream.close(force: true);
    try {
      webRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(int, String, HttpHeaders)> send(
    String method,
    String path, {
    Map<String, String> headers = const <String, String>{},
    String body = '',
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${gateway.port}$path'),
      );
      headers.forEach(request.headers.set);
      if (body.isNotEmpty) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(body);
      }
      final HttpClientResponse response = await request.close();
      final String text = await utf8.decoder.bind(response).join();
      return (response.statusCode, text, response.headers);
    } finally {
      client.close(force: true);
    }
  }

  test('把 X-JW-Cookie 翻译成 Cookie 转发给教务系统', () async {
    final (int status, String text, _) = await send(
      'POST',
      '/jw/xskb/xskb_list.do',
      headers: <String, String>{'X-JW-Cookie': 'JSESSIONID=from-app'},
      body: 'jx0404id=&cj0701id=&zc=4&demo=&sfFD=1',
    );

    expect(status, 200);
    expect(text, contains('kbtable'));
    expect(text, contains('zc=4'));
    expect(upstreamHits, 1);
    expect(upstreamCookies.single, 'JSESSIONID=from-app');
  });

  test('GET 请求按原方法转发（主页面读周次走 GET）', () async {
    final (int status, String text, _) = await send(
      'GET',
      '/jw/framework/xsMain_new_13657.jsp?t1=1',
      headers: <String, String>{'X-JW-Cookie': 'JSESSIONID=get-path'},
    );

    expect(status, 200);
    expect(upstreamMethods.last, 'GET');
    expect(upstreamTargets.last, contains('t1=1'));
    expect(upstreamCookies.last, 'JSESSIONID=get-path');
    expect(text, contains('kbtable')); // 假上游固定返回夹具，够验证转发行为
  });

  test('相同请求命中代理缓存：上游只收到一次', () async {
    Future<(int, String, HttpHeaders)> hit() => send(
      'POST',
      '/jw/xskb/xskb_list.do',
      headers: <String, String>{'X-JW-Cookie': 'JSESSIONID=cached'},
      body: 'jx0404id=&cj0701id=&zc=4&demo=&sfFD=1',
    );

    final (int first, String _, HttpHeaders _) = await hit();
    final (int second, String secondText, HttpHeaders _) = await hit();

    expect(first, 200);
    expect(second, 200);
    expect(secondText, contains('kbtable'));
    expect(upstreamHits, 1, reason: '第二次应命中网关缓存');
  });

  test('不同周次不会被缓存串味', () async {
    await send(
      'POST',
      '/jw/xskb/xskb_list.do',
      headers: <String, String>{'X-JW-Cookie': 'JSESSIONID=abc'},
      body: 'jx0404id=&cj0701id=&zc=4&demo=&sfFD=1',
    );
    await send(
      'POST',
      '/jw/xskb/xskb_list.do',
      headers: <String, String>{'X-JW-Cookie': 'JSESSIONID=abc'},
      body: 'jx0404id=&cj0701id=&zc=5&demo=&sfFD=1',
    );
    expect(upstreamHits, 2);
  });

  test('App 不带会话时，网关可以用 --cookie 补上（包体里不放 Cookie 的部署方式）', () async {
    final HttpServer ownGateway = await startGateway(
      port: 0,
      root: webRoot.path,
      upstream: 'http://127.0.0.1:${upstream.port}/gzasc_jsxsd',
      cookie: 'JSESSIONID=held-by-gateway',
      cacheSeconds: 0,
      log: (String _) {},
    );

    try {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${ownGateway.port}/jw/framework/main_index_loadkb.jsp',
        ),
      );
      request.write('jx0404id=&cj0701id=&zc=4&demo=&sfFD=1');
      final HttpClientResponse response = await request.close();
      final String text = await utf8.decoder.bind(response).join();
      client.close(force: true);

      expect(response.statusCode, 200);
      expect(text, contains('kbtable'));
      expect(upstreamCookies.last, 'JSESSIONID=held-by-gateway');
    } finally {
      await ownGateway.close(force: true);
    }
  });

  test('缺少会话时返回 400 与可读提示', () async {
    final (int status, String text, _) = await send(
      'POST',
      '/jw/xskb/xskb_list.do',
      body: 'jx0404id=&cj0701id=&zc=4&demo=&sfFD=1',
    );

    expect(status, 400);
    expect(text, contains('缺少会话 Cookie'));
    expect(upstreamHits, 0);
  });

  test('托管 Web 产物并支持前端路由回退', () async {
    final (int indexStatus, String indexText, HttpHeaders indexHeaders) =
        await send('GET', '/');
    expect(indexStatus, 200);
    expect(indexText, contains('APP'));

    final (int jsStatus, String jsText, HttpHeaders jsHeaders) = await send(
      'GET',
      '/main.dart.js',
    );
    expect(jsStatus, 200);
    expect(jsText, contains('console.log'));
    expect(jsHeaders.contentType?.mimeType, 'text/javascript');

    // 没有扩展名的路径回退到 index.html（SPA 路由）
    final (int routeStatus, String routeText, _) = await send(
      'GET',
      '/settings',
    );
    expect(routeStatus, 200);
    expect(routeText, contains('APP'));

    // 缺失资源返回 404
    final (int missingStatus, _, _) = await send('GET', '/nope.png');
    expect(missingStatus, 404);

    expect(indexHeaders.value('access-control-allow-origin'), '*');
  });

  test('OPTIONS 预检带 CORS 头（flutter run 跨域开发场景）', () async {
    final (int status, _, HttpHeaders headers) = await send(
      'OPTIONS',
      '/jw/xskb/xskb_list.do',
    );

    expect(status, 204);
    expect(headers.value('access-control-allow-origin'), '*');
    expect(
      headers.value('access-control-allow-headers'),
      contains('X-JW-Cookie'),
    );
  });
}

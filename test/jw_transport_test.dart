import 'dart:convert';
import 'dart:io';

import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/data/jw_http.dart';
import 'package:class_schedule/data/jw_transport_io.dart' as transport;
import 'package:flutter_test/flutter_test.dart';

/// io 传输层的真实 HTTP 行为（不依赖外网，用本地 HttpServer 当上游）。
void main() {
  test('X-JW-Cookie 翻译成 Cookie，且不把内部头透传给服务器', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    String? seenCookie;
    String? seenInternal;
    server.listen((HttpRequest request) async {
      seenCookie = request.headers.value('cookie');
      seenInternal = request.headers.value('x-jw-cookie');
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..write('<table id="tab1">课程</table>');
      await request.response.close();
    });

    try {
      final String result = await transport.sendRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/kb'),
        'rq=2026-09-21',
        <String, String>{
          'X-JW-Cookie': 'JSESSIONID=abc',
          'User-Agent': 'test-agent',
        },
      );

      expect(result, contains('tab1'));
      expect(result, contains('课程')); // UTF-8 解码正常
      expect(seenCookie, 'JSESSIONID=abc');
      expect(seenInternal, isNull);
    } finally {
      await server.close(force: true);
    }
  });

  test('GET 请求也能用（主页面读周次）', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    String? seenMethod;
    String? seenQuery;
    server.listen((HttpRequest request) async {
      seenMethod = request.method;
      seenQuery = request.uri.query;
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..write('<div id="li_showWeek"><span>第3周</span>/20周</div>');
      await request.response.close();
    });

    try {
      final String result = await transport.sendRequest(
        'GET',
        Uri.parse('http://127.0.0.1:${server.port}/main.jsp?t1=1'),
        '',
        <String, String>{'X-JW-Cookie': 'a'},
      );

      expect(seenMethod, 'GET');
      expect(seenQuery, 't1=1');
      expect(result, contains('第3周'));
    } finally {
      await server.close(force: true);
    }
  });

  test('复用连接：连续两次请求走同一条 TCP 连接', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<int> clientPorts = <int>[];
    server.listen((HttpRequest request) async {
      clientPorts.add(request.connectionInfo!.remotePort);
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.html
        ..write('ok');
      await request.response.close();
    });

    try {
      final Uri url = Uri.parse('http://127.0.0.1:${server.port}/kb');
      await transport.sendRequest('POST', url, 'rq=2026-09-21', <String, String>{
        'X-JW-Cookie': 'a',
      });
      // 等连接归还到连接池（真实场景两次请求间隔以秒计）
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await transport.sendRequest('POST', url, 'rq=2026-09-28', <String, String>{
        'X-JW-Cookie': 'a',
      });

      expect(clientPorts, hasLength(2));
      expect(
        clientPorts.first,
        clientPorts.last,
        reason: '共享 HttpClient 后第二次请求应复用连接（换周不再重新握手）',
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('登录：POST 的 302 会自己跟到主页面，并收下 302 上的新会话', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<String> methods = <String>[];
    final List<String?> cookies = <String?>[];
    final List<String?> contentTypes = <String?>[];
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      methods.add(request.method);
      cookies.add(request.headers.value('cookie'));
      contentTypes.add(request.headers.value('content-type'));
      if (request.uri.path == '/xk/LoginToXk') {
        // 教务系统登录成功后的样子：302 + 新会话写在**这一跳**上
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/framework/xsMain.jsp')
          ..headers.set(
            HttpHeaders.setCookieHeader,
            'JSESSIONID=NEW; Path=/gzasc_jsxsd; HttpOnly',
          );
      } else {
        request.response
          ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
          ..write('<div id="li_showWeek"><span>第3周</span>/20周</div>');
      }
      await request.response.close();
    });

    try {
      final JwHttpResponse result = await transport.sendDetailed(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/xk/LoginToXk'),
        'userAccount=u&encoded=x',
        <String, String>{
          'X-JW-Cookie': 'JSESSIONID=OLD',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
      );

      expect(result.statusCode, 200);
      expect(result.text, contains('第3周'));
      expect(result.cookie, 'JSESSIONID=NEW');
      expect(methods, <String>['POST', 'GET'], reason: '302 之后按浏览器语义改成 GET');
      expect(cookies.last, 'JSESSIONID=NEW', reason: '旧会话要被新下发的覆盖');
      expect(contentTypes.last, isNull, reason: '降级成 GET 后不该再带表单类型');
    } finally {
      await server.close(force: true);
    }
  });

  test('登录：302 只在 Set-Cookie 里给新会话，也必须被收下', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      if (request.uri.path == '/xk/LoginToXk') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/framework/xsMain.jsp')
          // 两条独立的 Set-Cookie（dart:io 会放在同一个头的多个值里）
          ..headers.add(
            HttpHeaders.setCookieHeader,
            'JSESSIONID=NEW; Path=/; HttpOnly',
          )
          ..headers.add(
            HttpHeaders.setCookieHeader,
            'HWWAFSESID=waf1; Path=/',
          );
      } else {
        request.response
          ..headers.contentType = ContentType.html
          ..write('ok');
      }
      await request.response.close();
    });

    try {
      final JwHttpResponse result = await transport.sendDetailed(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/xk/LoginToXk'),
        'userAccount=u',
        <String, String>{'X-JW-Cookie': 'JSESSIONID=OLD; HWWAFSESID=waf0'},
      );

      expect(result.cookie, contains('JSESSIONID=NEW'));
      expect(result.cookie, contains('HWWAFSESID=waf1'), reason: '多条 Set-Cookie 都要收');
      expect(result.cookie, isNot(contains('OLD')));
    } finally {
      await server.close(force: true);
    }
  });

  test('登录：跳转成环时抛出可读异常而不是死循环', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/loop');
      await request.response.close();
    });

    try {
      await expectLater(
        transport.sendDetailed(
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}/loop'),
          'a=b',
          <String, String>{'X-JW-Cookie': 'a'},
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('跳转次数'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('非 200 转成可读异常', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.listen((HttpRequest request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });

    try {
      await expectLater(
        transport.sendRequest(
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}/kb'),
          'rq=2026-09-21',
          <String, String>{'X-JW-Cookie': 'a'},
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });
}

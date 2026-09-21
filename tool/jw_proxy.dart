// 课表 App 的本地网关：托管 Web 构建产物 + 反向代理教务系统。
//
// 为什么需要它：
//   浏览器禁止 JS 设置 `Cookie` 请求头，也不允许读取跨域响应，所以 Web 端无法直连教务系统。
//   这个代理把两件事合成一个同源服务：
//     · 静态托管 build/web（App 本身）
//     · 把 /jw/** 转发到教务系统，并把自定义头 X-JW-Cookie 翻译成真正的 Cookie
//   浏览器只跟 127.0.0.1 打交道 → 完全不涉及 CORS。
//
// 用法：
//   flutter build web --release
//   dart run tool/jw_proxy.dart                 # 打开提示的地址即可
//   dart run tool/jw_proxy.dart --port 9000 --cache-seconds 0 --open
//
// 只依赖 dart:io，不需要 Flutter SDK 就能跑，也可以放到服务器上做反代。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _defaultUpstream = 'https://jw.educationgroup.cn/gzasc_jsxsd';
const String _proxyPrefix = '/jw';
const String _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('参数错误：${error.message}\n');
    stdout.writeln(_usage);
    exitCode = 64;
    return;
  }

  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final HttpServer server;
  try {
    server = await startGateway(
      host: options.host,
      port: options.port,
      root: options.root,
      upstream: options.upstream,
      cookie: options.cookie,
      cacheSeconds: options.cacheSeconds,
    );
  } on SocketException catch (error) {
    stderr.writeln('无法监听 ${options.host}:${options.port} —— ${error.message}');
    exitCode = 70;
    return;
  }

  final String url = 'http://${options.host}:${server.port}/';
  final bool hasWeb =
      File('${options.root}${Platform.pathSeparator}index.html').existsSync();

  stdout
    ..writeln('课表网关已启动')
    ..writeln('  打开：      $url')
    ..writeln(
      '  静态目录：  ${Directory(options.root).absolute.path}'
      '${hasWeb ? '' : '（缺少 index.html，先跑 flutter build web --release）'}',
    )
    ..writeln('  代理前缀：  $_proxyPrefix/** → ${options.upstream}')
    ..writeln('  响应缓存：  ${options.cacheSeconds > 0 ? '${options.cacheSeconds}s' : '关闭'}')
    ..writeln(
      '  会话来源：  ${options.cookie == null ? '请求头 X-JW-Cookie（App 内置）' : '--cookie 参数'}',
    )
    ..writeln('  Ctrl+C 退出');

  if (options.open) {
    unawaited(_openBrowser(url));
  }
}

/// 启动网关并返回已绑定的 [HttpServer]（测试直接用它，端口传 0 取随机端口）。
Future<HttpServer> startGateway({
  String host = '127.0.0.1',
  int port = 8765,
  String root = 'build/web',
  String upstream = _defaultUpstream,
  String? cookie,
  int cacheSeconds = 60,
  void Function(String message)? log,
}) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(minutes: 5)
    ..maxConnectionsPerHost = 6
    ..autoUncompress = true;

  final _ResponseCache cache = _ResponseCache(
    ttl: Duration(seconds: cacheSeconds),
  );
  final String normalizedUpstream = upstream.endsWith('/')
      ? upstream.substring(0, upstream.length - 1)
      : upstream;
  final void Function(String) logger = log ?? stdout.writeln;

  final HttpServer server = await HttpServer.bind(host, port);
  server.listen((HttpRequest request) {
    unawaited(
      _handle(
        request,
        root: root,
        upstream: normalizedUpstream,
        cookie: cookie,
        client: client,
        cache: cache,
        log: logger,
      ),
    );
  });
  return server;
}

Future<void> _handle(
  HttpRequest request, {
  required String root,
  required String upstream,
  required String? cookie,
  required HttpClient client,
  required _ResponseCache cache,
  required void Function(String) log,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  var note = '';
  try {
    _cors(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final String path = request.uri.path;
    if (path == _proxyPrefix || path.startsWith('$_proxyPrefix/')) {
      note = await _proxy(
        request,
        upstream: upstream,
        cookie: cookie,
        client: client,
        cache: cache,
      );
    } else if (request.method == 'GET' || request.method == 'HEAD') {
      await _serveStatic(request, root);
    } else {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    }
  } catch (error) {
    note = 'error';
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response
        ..headers.contentType = ContentType.text
        ..write('网关内部错误：$error');
    } catch (_) {
      // 响应头可能已经发出去了，忽略二次写入失败
    }
    try {
      await request.response.close();
    } catch (_) {}
  } finally {
    log(
      '${DateTime.now().toIso8601String().substring(11, 19)} '
      '${request.method.padRight(4)} ${request.uri} → ${request.response.statusCode} '
      '${stopwatch.elapsedMilliseconds}ms'
      '${note.isEmpty ? '' : ' [$note]'}',
    );
  }
}

/// 把 /jw/** 转发给教务系统，返回日志备注。
Future<String> _proxy(
  HttpRequest request, {
  required String upstream,
  required String? cookie,
  required HttpClient client,
  required _ResponseCache cache,
}) async {
  final String body = await utf8.decoder.bind(request).join();
  final String tail = request.uri.path.substring(_proxyPrefix.length);
  final String query = request.uri.hasQuery ? '?${request.uri.query}' : '';
  final Uri target = Uri.parse('$upstream$tail$query');

  // 会话来源优先级：请求头 X-JW-Cookie → 请求头 Cookie → 启动参数 --cookie。
  // 空字符串按「没传」处理，这样 App 可以用 --dart-define=JW_COOKIE= 构建、
  // 把会话完全交给网关持有（包体里不含 Cookie，更安全）。
  final String fromHeader = (request.headers.value('x-jw-cookie') ?? '').trim();
  final String fromCookieHeader =
      (request.headers.value(HttpHeaders.cookieHeader) ?? '').trim();
  final String session = fromHeader.isNotEmpty
      ? fromHeader
      : (fromCookieHeader.isNotEmpty ? fromCookieHeader : (cookie ?? '').trim());
  if (session.isEmpty) {
    request.response.statusCode = HttpStatus.badRequest;
    request.response
      ..headers.contentType = ContentType.text
      ..write(
        '缺少会话 Cookie：请在 App 的 lib/data/jw_credentials.dart 里填写，'
        '或用 --cookie 启动本代理。',
      );
    await request.response.close();
    return 'no-cookie';
  }

  final String cacheKey = '$target|$body';
  final _CacheEntry? hit = cache.get(cacheKey);
  if (hit != null) {
    request.response.statusCode = hit.statusCode;
    request.response.headers.contentType = hit.contentType;
    request.response.add(hit.bytes);
    await request.response.close();
    return 'cache';
  }

  final HttpClientRequest upstreamRequest = request.method == 'GET'
      ? await client.getUrl(target)
      : await client.postUrl(target);
  upstreamRequest.headers
    ..set(HttpHeaders.cookieHeader, session)
    ..set(HttpHeaders.userAgentHeader, _userAgent)
    ..set(HttpHeaders.refererHeader, '$upstream/framework/main_index.jsp')
    ..set('X-Requested-With', 'XMLHttpRequest')
    ..set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );
  if (request.method != 'GET') {
    upstreamRequest.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded; charset=UTF-8',
    );
  }
  if (body.isNotEmpty) {
    upstreamRequest.add(utf8.encode(body));
  }

  final HttpClientResponse response = await upstreamRequest.close().timeout(
    const Duration(seconds: 25),
  );
  final List<int> bytes = await response.fold<List<int>>(
    <int>[],
    (List<int> acc, List<int> chunk) => acc..addAll(chunk),
  );
  final ContentType contentType = response.headers.contentType ?? ContentType.html;

  cache.put(cacheKey, bytes, response.statusCode, contentType);

  request.response.statusCode = response.statusCode;
  request.response.headers.contentType = contentType;
  request.response.add(bytes);
  await request.response.close();
  return '';
}

/// 托管 build/web 静态文件。
Future<void> _serveStatic(HttpRequest request, String root) async {
  final Directory rootDir = Directory(root);
  String relative = Uri.decodeComponent(request.uri.path);
  if (relative.isEmpty || relative == '/') {
    relative = '/index.html';
  }

  File file = File(
    '${rootDir.path}${relative.replaceAll('/', Platform.pathSeparator)}',
  );

  if (!file.existsSync()) {
    final File index = File('${rootDir.path}${Platform.pathSeparator}index.html');
    // 前端路由回退：没有扩展名的路径交给 index.html
    if (index.existsSync() && !relative.split('/').last.contains('.')) {
      file = index;
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        index.existsSync()
            ? '<h1>404</h1><p>${request.uri.path} 不存在</p>'
            : _buildHintPage(rootDir),
      );
      await request.response.close();
      return;
    }
  }

  request.response.headers.contentType = _mimeOf(file.path);
  if (request.method != 'HEAD') {
    request.response.add(await file.readAsBytes());
  }
  await request.response.close();
}

void _cors(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, X-JW-Cookie')
    ..set('Access-Control-Max-Age', '600');
}

Future<void> _openBrowser(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('cmd', <String>['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', <String>[url]);
    } else {
      await Process.start('xdg-open', <String>[url]);
    }
  } catch (_) {}
}

ContentType _mimeOf(String path) {
  final String ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'html' => ContentType.html,
    'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
    'json' || 'map' => ContentType.json,
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'wasm' => ContentType('application', 'wasm'),
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'gif' => ContentType('image', 'gif'),
    'svg' => ContentType('image', 'svg+xml'),
    'ico' => ContentType('image', 'x-icon'),
    'ttf' => ContentType('font', 'ttf'),
    'otf' => ContentType('font', 'otf'),
    'woff' => ContentType('font', 'woff'),
    'woff2' => ContentType('font', 'woff2'),
    'bin' || 'symbols' => ContentType('application', 'octet-stream'),
    _ => ContentType.binary,
  };
}

String _buildHintPage(Directory root) => '''
<!doctype html><meta charset="utf-8">
<title>先构建 Web 产物</title>
<body style="font:14px/1.7 system-ui;max-width:640px;margin:60px auto;padding:0 20px">
<h2>还没找到 Web 构建产物</h2>
<p>目录：<code>${root.absolute.path}</code></p>
<p>先在项目根目录执行：</p>
<pre style="background:#f5f5f5;padding:12px;border-radius:8px">flutter build web --release</pre>
<p>然后刷新本页。<br>
（教务系统反代部分已经可用：<code>$_proxyPrefix/framework/main_index_loadkb.jsp</code>）</p>
</body>''';

class _CacheEntry {
  const _CacheEntry({
    required this.bytes,
    required this.statusCode,
    required this.contentType,
    required this.storedAt,
  });

  final List<int> bytes;
  final int statusCode;
  final ContentType contentType;
  final DateTime storedAt;
}

/// 极简内存缓存：同一周的课表在 TTL 内重复请求直接命中。
class _ResponseCache {
  _ResponseCache({required this.ttl});

  final Duration ttl;
  final Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};

  _CacheEntry? get(String key) {
    if (ttl == Duration.zero) {
      return null;
    }
    final _CacheEntry? entry = _entries[key];
    if (entry == null) {
      return null;
    }
    if (DateTime.now().difference(entry.storedAt) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  void put(String key, List<int> bytes, int statusCode, ContentType contentType) {
    if (ttl == Duration.zero || statusCode != HttpStatus.ok) {
      return;
    }
    _entries[key] = _CacheEntry(
      bytes: bytes,
      statusCode: statusCode,
      contentType: contentType,
      storedAt: DateTime.now(),
    );
    if (_entries.length > 64) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class _Options {
  const _Options({
    required this.host,
    required this.port,
    required this.root,
    required this.upstream,
    required this.cookie,
    required this.cacheSeconds,
    required this.open,
    required this.help,
  });

  final String host;
  final int port;
  final String root;
  final String upstream;
  final String? cookie;
  final int cacheSeconds;
  final bool open;
  final bool help;

  static _Options parse(List<String> args) {
    var host = '127.0.0.1';
    var port = 8765;
    var root = 'build${Platform.pathSeparator}web';
    var upstream = Platform.environment['JW_UPSTREAM'] ?? _defaultUpstream;
    String? cookie = Platform.environment['JW_COOKIE'];
    var cacheSeconds = 60;
    var open = false;
    var help = false;

    for (var index = 0; index < args.length; index++) {
      final String arg = args[index];
      String? valueOf(String name) {
        if (arg == '--$name') {
          if (index + 1 >= args.length) {
            throw FormatException('--$name 缺少取值');
          }
          return args[++index];
        }
        if (arg.startsWith('--$name=')) {
          return arg.substring(name.length + 3);
        }
        return null;
      }

      if (arg == '--help' || arg == '-h') {
        help = true;
        continue;
      }
      if (arg == '--open') {
        open = true;
        continue;
      }

      final String? hostValue = valueOf('host');
      if (hostValue != null) {
        host = hostValue;
        continue;
      }
      final String? portValue = valueOf('port');
      if (portValue != null) {
        port =
            int.tryParse(portValue) ??
            (throw FormatException('--port 不是数字：$portValue'));
        continue;
      }
      final String? rootValue = valueOf('root');
      if (rootValue != null) {
        root = rootValue;
        continue;
      }
      final String? upstreamValue = valueOf('upstream');
      if (upstreamValue != null) {
        upstream = upstreamValue.endsWith('/')
            ? upstreamValue.substring(0, upstreamValue.length - 1)
            : upstreamValue;
        continue;
      }
      final String? cookieValue = valueOf('cookie');
      if (cookieValue != null) {
        cookie = cookieValue;
        continue;
      }
      final String? cacheValue = valueOf('cache-seconds');
      if (cacheValue != null) {
        cacheSeconds =
            int.tryParse(cacheValue) ??
            (throw FormatException('--cache-seconds 不是数字：$cacheValue'));
        continue;
      }

      throw FormatException('未知参数：$arg');
    }

    return _Options(
      host: host,
      port: port,
      root: root,
      upstream: upstream,
      cookie: cookie,
      cacheSeconds: cacheSeconds,
      open: open,
      help: help,
    );
  }
}

const String _usage = '''
课表网关：托管 Flutter Web 产物 + 反向代理教务系统（解决浏览器跨域与 Cookie 限制）

用法：dart run tool/jw_proxy.dart [选项]

  --host <地址>            监听地址，默认 127.0.0.1
  --port <端口>            监听端口，默认 8765
  --root <目录>            静态目录，默认 build/web
  --upstream <地址>        教务系统根地址，默认 $_defaultUpstream
  --cookie <会话>          默认会话 Cookie（也可由 App 通过 X-JW-Cookie 传入，或用环境变量 JW_COOKIE）
  --cache-seconds <秒>     课表响应缓存时间，默认 60，0 表示关闭
  --open                   启动后自动打开浏览器
  -h, --help               显示帮助
''';

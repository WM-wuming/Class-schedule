import 'dart:async';

import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_exception.dart';
import 'package:class_schedule/data/jw_http.dart';
import 'package:class_schedule/data/jw_login.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const String _base = 'https://jw.example.com/gzasc_jsxsd';

void main() {
  group('登录表单', () {
    test('encoded 就是 base64(账号) + "%%%" + base64(密码)', () {
      // 选这两组是因为 base64 里同时出现 `=` 和 `+`（后者最容易被漏编码）
      expect(JwLoginForm.encoded('student', 'ab>'), 'c3R1ZGVudA==%%%YWI+');
    });

    test('userPassword 提交空值，密码只放在 encoded 里', () {
      final String body = JwLoginForm.body(
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );
      final List<String> fields = body.split('&');

      expect(fields, contains('userPassword='));
      expect(fields, contains('userAccount=student'));
      expect(fields, contains('RANDOMCODE=A1B2'));
    });

    test('encoded 里的 + = % 都被 URL 编码（原文的 + 会被服务端当成空格）', () {
      final String body = JwLoginForm.body(
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );
      final String field = body
          .split('&')
          .firstWhere((String part) => part.startsWith('encoded='));
      final String value = field.substring('encoded='.length);

      expect(body, isNot(contains('+')), reason: '原文里的 + 必须变成 %2B');
      expect(body, isNot(contains('%%%')), reason: '分隔符也要转义成 %25%25%25');
      expect(
        value,
        'c3R1ZGVudA%3D%3D%25%25%25YWI%2B',
        reason: '`=` → %3D，`%%%` → %25%25%25，`+` → %2B',
      );
      // decodeComponent 不会把 + 当成空格，所以拿它验证转义没被破坏
      expect(Uri.decodeComponent(value), 'c3R1ZGVudA==%%%YWI+');
      expect(Uri.decodeComponent(value), JwLoginForm.encoded('student', 'ab>'));
    });
  });

  group('登录失败页解析', () {
    test('从真实失败页里读出教务系统写的原因', () {
      expect(JwLoginPage.errorOf(fixtureLoginFailedHtml), '验证码错误!!');
    });

    test('登录页没写原因时用兜底提示', () {
      const String page =
          '<html><body><input name="userAccount">'
          '<li id="showMsg">&nbsp;请先登录系统</li></body></html>';
      expect(JwLoginPage.errorOf(page), JwLoginPage.fallbackMessage);
    });

    test('出现登录表单就说明没登进去（哪怕没有 showMsg）', () {
      const String page =
          '<html><body><input name="userAccount"></body></html>';
      expect(JwLoginPage.errorOf(page), JwLoginPage.fallbackMessage);
    });

    test('不像登录页的响应视为成功', () {
      expect(JwLoginPage.errorOf(fixtureLoginOkHtml), isNull);
      expect(JwLoginPage.errorOf(''), isNull);
    });
  });

  group('Cookie 处理', () {
    test('同名 Cookie 后出现的覆盖先前的', () {
      expect(JwCookieJar.merge('a=1; b=2', 'b=3; c=4'), 'a=1; b=3; c=4');
    });

    test('Set-Cookie 的属性被丢掉，空值（删除指令）不留下', () {
      expect(
        normalizeSetCookie(<String>[
          'HWWAFSESID=abc; path=/',
          'JSESSIONID=xyz; Path=/gzasc_jsxsd; HttpOnly',
          '8172249b=WyIxIl0; Domain=jw.example.com; Path=/; Secure',
          'gone=; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
        ]),
        'HWWAFSESID=abc; JSESSIONID=xyz; 8172249b=WyIxIl0',
      );
    });
  });

  group('登录会话与客户端', () {
    test('裸访问登录页拿初始会话，验证码与提交都绑在这个会话上', () async {
      final FakeLoginTransport login = FakeLoginTransport();
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'JSESSIONID=old',
        transport: jwOkTransport,
        detailedTransport: login.call,
      );

      final JwLoginSession session = await client.beginLogin();
      expect(login.warmupCalls, 1, reason: '先裸访问一次登录页');
      expect(
        login.lastWarmupCookie,
        isNull,
        reason: '裸访问不带任何 Cookie，服务端下发的才是初始会话',
      );
      expect(login.captchaCalls, 1);
      expect(session.image, fakeCaptchaImage);
      expect(session.cookie, contains('JSESSIONID=login-before'));
      expect(
        session.cookie,
        isNot(contains('JSESSIONID=old')),
        reason: '初始会话来自裸访问，调用方旧会话不参与登录',
      );

      await client.login(
        session,
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );

      expect(login.warmupCalls, 1, reason: '提交阶段不再有预热请求');
      expect(login.lastLoginBody, contains('RANDOMCODE=A1B2'));
      expect(login.lastLoginBody, contains('userAccount=student'));
      expect(login.lastLoginBody, contains('userPassword='));
      expect(
        login.lastLoginCookie,
        contains('JSESSIONID=login-before'),
        reason: '验证码校验绑在会话上，提交必须带回去',
      );
      expect(
        login.lastLoginCookie,
        contains('HWWAFSESID=waf123'),
        reason: '裸访问与取验证码阶段拿到的 Cookie 都在提交会话里',
      );
      expect(
        login.lastLoginCookie,
        isNot(contains('waf-warmup')),
        reason: '验证码响应的 WAF Cookie 覆盖了裸访问的初始值',
      );
    });

    test('裸访问失败时直接报错，不会继续取验证码或提交', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        warmupError: const JwException('裸访问登录页失败'),
      );
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'JSESSIONID=old',
        transport: jwOkTransport,
        detailedTransport: login.call,
      );

      await expectLater(client.beginLogin(), throwsA(isA<JwException>()));
      expect(login.warmupCalls, 1);
      expect(login.captchaCalls, 0, reason: '拿不到初始会话就不该取验证码');
      expect(login.loginCalls, 0);
    });

    test('登录成功后替换客户端会话，并顺带返回主页面信息', () async {
      final FakeLoginTransport login = FakeLoginTransport();
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'JSESSIONID=old',
        transport: jwOkTransport,
        detailedTransport: login.call,
      );

      final JwMainPageInfo info = await client.login(
        await client.beginLogin(),
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );

      expect(info.student.name, '张三');
      // 主页面给的是「今天的教务周次」，跟着运行日期走（见 fakes.dart）
      expect(info.week.week, schoolWeekToday);
      expect(client.cookie, contains('JSESSIONID=after-login'));
      expect(client.cookie, isNot(contains('old')));
    });

    test('验证码接口没返回图片时给出可读错误', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        captchaContentType: 'text/html',
      );
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'x',
        transport: jwOkTransport,
        detailedTransport: login.call,
      );

      await expectLater(
        client.beginLogin(),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('没有返回图片'),
          ),
        ),
      );
      expect(login.loginCalls, 0);
    });

    test('登录被拒时抛教务系统写的原因，并恢复原来的会话', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'JSESSIONID=old',
        // 没登进去 → 主页面还是登录页
        transport: jwExpiredTransport,
        detailedTransport: login.call,
      );

      await expectLater(
        client.login(
          await client.beginLogin(),
          account: 'student',
          password: 'ab>',
          captcha: 'zzzz',
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            '验证码错误!!',
          ),
        ),
      );
      expect(client.cookie, 'JSESSIONID=old');
    });

    test('没报错却读不通主页面：保留新会话，只说读不到学生信息', () async {
      final FakeLoginTransport login = FakeLoginTransport();
      final JwTimetableClient client = JwTimetableClient(
        baseUrl: _base,
        cookie: 'JSESSIONID=old',
        transport: jwExpiredTransport,
        detailedTransport: login.call,
      );

      await expectLater(
        client.login(
          await client.beginLogin(),
          account: 'student',
          password: 'ab>',
          captcha: 'A1B2',
        ),
        throwsA(
          isA<JwException>().having(
            (JwException e) => e.message,
            'message',
            contains('已提交登录'),
          ),
        ),
      );
      expect(
        client.cookie,
        contains('JSESSIONID=after-login'),
        reason: '登录既然没被拒，新会话就该留着 —— 下次读主页面还能用',
      );
    });
  });

  group('控制器里的登录', () {
    test('取到验证码后暴露图片，且没有错误', () async {
      final ScheduleController controller = ScheduleController(
        transport: RecordingTransport().call,
        detailedTransport: FakeLoginTransport().call,
        accountStore: FakeAccountStore(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.captchaImage, isNull);
      expect(controller.loginLoading, isFalse);

      await controller.startLogin();
      expect(controller.captchaImage, fakeCaptchaImage);
      expect(controller.loginError, isNull);
      controller.dispose();
    });

    test('登录成功后换成新账号的数据，并作废验证码', () async {
      var loggedIn = false;
      final FakeLoginTransport login = FakeLoginTransport();
      final ScheduleController controller = ScheduleController(
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          if (!u.path.contains('xsMain')) {
            return fixtureHtml;
          }
          // 登录前会话是过期的，登录后主页面才读得到
          return loggedIn
              ? fixtureWeekInfoHtml
              : '<html><head><title>用户登录</title></head></html>';
        },
        detailedTransport:
            (String m, Uri u, String b, Map<String, String> h) async {
              final JwHttpResponse response = await login.call(m, u, b, h);
              if (!u.path.contains('verifycode')) {
                loggedIn = true;
              }
              return response;
            },
        accountStore: FakeAccountStore(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.student, isNull, reason: '登录前读不到学生信息');

      await controller.startLogin();
      final bool ok = await controller.submitLogin(
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );

      expect(ok, isTrue);
      expect(controller.student?.name, '张三');
      expect(controller.student?.studentId, '202600000001');
      expect(controller.loginError, isNull);
      expect(controller.captchaImage, isNull, reason: '验证码是一次性的');
      expect(controller.sessionsOfWeek(controller.currentWeek), isNotEmpty);
      controller.dispose();
    });

    test('登录失败后给出原因，并自动换一张新验证码', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        detailedTransport: login.call,
        accountStore: FakeAccountStore(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await controller.startLogin();
      expect(controller.captchaImage, isNotNull);
      expect(login.captchaCalls, 1);

      final bool ok = await controller.submitLogin(
        account: 'student',
        password: 'ab>',
        captcha: 'zzzz',
      );

      expect(ok, isFalse);
      expect(controller.loginError, '验证码错误!!');
      expect(login.captchaCalls, 2, reason: '失败后自动再取一张');
      expect(
        controller.captchaImage,
        fakeCaptchaImage,
        reason: '返回时新图已经到位，用户改完密码就能直接重输',
      );
      expect(controller.loginLoading, isFalse, reason: '换完图按钮要能再点');
      controller.dispose();
    });

    test('自动换图失败时，保住「登录失败」的原因不被顶掉', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        detailedTransport:
            (String m, Uri u, String b, Map<String, String> h) async {
              // 第一张图要正常给（否则压根提交不了），之后的刷新一律失败。
              if (u.path.contains('verifycode') && login.captchaCalls >= 1) {
                throw const JwException('验证码接口挂了');
              }
              return login.call(m, u, b, h);
            },
        accountStore: FakeAccountStore(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await controller.startLogin();
      expect(controller.captchaImage, fakeCaptchaImage);

      final bool ok = await controller.submitLogin(
        account: 'student',
        password: 'ab>',
        captcha: 'zzzz',
      );

      expect(ok, isFalse);
      expect(
        controller.loginError,
        '验证码错误!!',
        reason: '「密码/验证码错了」比「换图失败」更该先被看到',
      );
      expect(
        controller.captchaImage,
        isNull,
        reason: '新图没取到，验证码位退化成「点此获取」，点一下就能重试',
      );
      controller.dispose();
    });

    test('没有验证码就提交时给出可读提示', () async {
      final ScheduleController controller = ScheduleController(
        transport: jwOkTransport,
        detailedTransport: FakeLoginTransport().call,
        accountStore: FakeAccountStore(),
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final bool ok = await controller.submitLogin(
        account: 'student',
        password: 'ab>',
        captcha: 'A1B2',
      );
      expect(ok, isFalse);
      expect(controller.loginError, contains('验证码'));
      controller.dispose();
    });
  });

  group('登录页的验证码自动刷新', () {
    testWidgets('识别拿不到结果时空验证码点登录：提示手动输入，不发请求', (WidgetTester tester) async {
      // 不注入识别器：测试环境下识别口永远返回 null（模拟真机识别失败）。
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      await tester.pumpWidget(
        jwApp(transport: jwExpiredTransport, loginTransport: login.call),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      // 只填账号密码，验证码留空 —— 按钮不能因此被禁用。
      final Finder fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'student');
      await tester.enterText(fields.at(1), 'ab>');
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(login.loginCalls, 0, reason: '识别拿不到结果就不交空表单（验证码是一次性的）');
      expect(find.textContaining('请照图手动输入'), findsOneWidget);
    });

    testWidgets('空验证码点登录会等识别结果，等到了就提交', (WidgetTester tester) async {
      // gate 不放行 = 识别还在跑：点登录时页面应该等它出结果。
      final Completer<void> gate = Completer<void>();
      final FakeCaptchaRecognizer recognizer = FakeCaptchaRecognizer(<String?>[
        'AB12',
      ], gate: gate);
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          loginTransport: login.call,
          captchaRecognizer: recognizer,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      final Finder fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'student');
      await tester.enterText(fields.at(1), 'ab>');
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(login.loginCalls, 1, reason: '等到了识别结果并拿去提交');
      expect(find.text('验证码错误!!'), findsOneWidget, reason: '假传输层按验证码错误裁决');
      expect(find.textContaining('请照图手动输入'), findsNothing);
    });

    testWidgets('提交失败后自动换一张，并说明验证码已更换', (WidgetTester tester) async {
      final FakeLoginTransport login = FakeLoginTransport(
        loginHtml: fixtureLoginFailedHtml,
      );
      await tester.pumpWidget(
        jwApp(transport: jwExpiredTransport, loginTransport: login.call),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      expect(login.captchaCalls, 1, reason: '进页面先要一张');

      final Finder fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'student');
      await tester.enterText(fields.at(1), 'ab>');
      await tester.enterText(fields.at(2), 'zzzz');
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      // 还停在登录页：失败原因 + 「图已经换过」的说明都在
      expect(find.text('验证码错误!!'), findsOneWidget);
      expect(find.text('验证码已自动更换，请重新输入'), findsOneWidget);
      expect(login.loginCalls, 1);
      expect(login.captchaCalls, 2, reason: '失败后自动再取一张');

      final EditableText captchaField = tester.widget<EditableText>(
        find.byType(EditableText).at(2),
      );
      expect(
        captchaField.controller.text,
        isEmpty,
        reason: '旧验证码作废了，输入框也要清掉，等用户照新图重输',
      );
    });

    testWidgets('取验证码失败时不显示「已自动更换」', (WidgetTester tester) async {
      // 一开始就取不到图 → 页面给的是取图失败的原因，验证码位是「点此获取」
      final FakeLoginTransport login = FakeLoginTransport(
        captchaError: const JwException('验证码接口挂了'),
      );
      await tester.pumpWidget(
        jwApp(transport: jwExpiredTransport, loginTransport: login.call),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      expect(find.text('验证码接口挂了'), findsOneWidget);
      expect(find.text('验证码已自动更换，请重新输入'), findsNothing);
      expect(find.text('点此获取'), findsOneWidget);
    });
  });

  group('我的信息页的登录入口', () {
    testWidgets('读不到学生信息时卡片里给出登录按钮', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp(transport: jwExpiredTransport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      expect(find.text('还没有读到学生信息'), findsOneWidget);
      expect(find.text('登录教务系统'), findsOneWidget);
      expect(find.text('重新读取'), findsOneWidget);
    });

    testWidgets('有学生信息时卡片底部也有登录按钮', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      expect(find.text('张三'), findsOneWidget);
      expect(find.text('登录教务系统'), findsOneWidget);
    });

    testWidgets('点登录进入登录页，提交后回到我的信息并显示新账号', (WidgetTester tester) async {
      var loggedIn = false;
      final FakeLoginTransport login = FakeLoginTransport();
      await tester.pumpWidget(
        jwApp(
          transport: (String m, Uri u, String b, Map<String, String> h) async {
            if (!u.path.contains('xsMain')) {
              return fixtureHtml;
            }
            return loggedIn
                ? fixtureWeekInfoHtml
                : '<html><head><title>用户登录</title></head></html>';
          },
          loginTransport:
              (String m, Uri u, String b, Map<String, String> h) async {
                final JwHttpResponse response = await login.call(m, u, b, h);
                if (!u.path.contains('verifycode')) {
                  loggedIn = true;
                }
                return response;
              },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      expect(find.text('还没有读到学生信息'), findsOneWidget);

      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      // 登录页：三行输入 + 验证码图片
      expect(find.text('学号 / 账号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('验证码'), findsOneWidget);
      expect(login.captchaCalls, 1);

      final Finder fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'student');
      await tester.enterText(fields.at(1), 'ab>');
      await tester.enterText(fields.at(2), 'A1B2');
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      // 回到「我的信息」，显示的是这次登录账号的信息
      expect(find.text('学号 / 账号'), findsNothing);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('202600000001'), findsOneWidget);
      expect(login.loginCalls, 1);
      expect(login.lastLoginBody, contains('userAccount=student'));
    });
  });
}

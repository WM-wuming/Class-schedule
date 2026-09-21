import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_http.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 等控制器把启动期的异步活儿（校准学期、拉课表等）跑完。
Future<void> settleBootstrap() async {
  await Future<void>.delayed(const Duration(milliseconds: 100));
}

/// 主页面传输层：登录成功前返回登录页，成功后返回主页面（与真实判据一致）。
JwTransport loggedInMainTransport(List<bool> loggedIn) =>
    (String m, Uri u, String b, Map<String, String> h) async {
      if (!u.path.contains('xsMain')) {
        return fixtureHtml;
      }
      return loggedIn.first
          ? fixtureWeekInfoHtml
          : '<html><head><title>用户登录</title></head></html>';
    };

/// 登录传输层包装：登录提交**成功**（响应不是失败页）后把 [loggedIn] 置真。
///
/// 真实流程里被拒绝的提交不会换来可用会话，主页面依然读不通 ——
/// 所以这里看响应里有没有 `showMsg`，而不是无脑按请求次数置位。
JwDetailedTransport togglingLoginTransport(
  FakeLoginTransport login,
  List<bool> loggedIn,
) => (
  String m,
  Uri u,
  String b,
  Map<String, String> h,
) async {
  final JwHttpResponse response = await login.call(m, u, b, h);
  // 只看登录提交（POST）；预热 GET 的合成页也会经过这里，不能把开关打开。
  if (m == 'POST' &&
      !u.path.contains('verifycode') &&
      !response.text.contains('showMsg')) {
    loggedIn.first = true;
  }
  return response;
};

void main() {
  group('自动登录（识别验证码 → 提交 → 验证码错误重试）', () {
    test('识别成功且验证码正确时直接登录成功', () async {
      final List<bool> loggedIn = <bool>[false];
      final FakeLoginTransport login = FakeLoginTransport();
      final ScheduleController controller = ScheduleController(
        transport: loggedInMainTransport(loggedIn),
        detailedTransport: togglingLoginTransport(login, loggedIn),
        accountStore: FakeAccountStore(),
        captchaRecognizer: FakeCaptchaRecognizer(<String>['ab12']),
        swipeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await settleBootstrap();

      await controller.startLogin();
      // 识别是 startLogin 返回后才跑完的后台活，等它一小会儿。
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.captchaGuess, 'ab12', reason: '取到图就后台识别');

      final bool ok = await controller.autoLoginWithCaptcha(
        account: 'student',
        password: 'ab>',
      );

      expect(ok, isTrue);
      expect(login.loginCalls, 1);
      expect(login.lastLoginBody, contains('RANDOMCODE=ab12'));
      expect(controller.student?.name, '张三');
    });

    test('验证码读错时自动换一张重试，第二次成功', () async {
      final List<bool> loggedIn = <bool>[false];
      final FakeLoginTransport login = FakeLoginTransport(
        firstLoginError: '验证码错误!!',
      );
      final ScheduleController controller = ScheduleController(
        transport: loggedInMainTransport(loggedIn),
        detailedTransport: togglingLoginTransport(login, loggedIn),
        accountStore: FakeAccountStore(),
        captchaRecognizer: FakeCaptchaRecognizer(<String>['1111', '2222']),
        swipeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await settleBootstrap();

      await controller.startLogin();
      final bool ok = await controller.autoLoginWithCaptcha(
        account: 'student',
        password: 'ab>',
      );

      expect(ok, isTrue, reason: '第一次验证码错、第二次对，应该重试到成功');
      expect(login.loginCalls, 2);
      expect(login.captchaCalls, 2, reason: '失败后自动换一张新图');
      expect(login.lastLoginBody, contains('RANDOMCODE=2222'));
      expect(controller.loginError, isNull);
    });

    test('账号或密码错误时不重试 —— 重试也不会变好', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        firstLoginError: '用户名或密码错误!!',
      );
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        detailedTransport: login.call,
        accountStore: FakeAccountStore(),
        captchaRecognizer: FakeCaptchaRecognizer(<String>['1111', '2222']),
        swipeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await settleBootstrap();

      await controller.startLogin();
      final bool ok = await controller.autoLoginWithCaptcha(
        account: 'student',
        password: 'wrong',
      );

      expect(ok, isFalse);
      expect(login.loginCalls, 1, reason: '密码错不该再自动提交');
      expect(controller.loginError, contains('用户名或密码'));
    });

    test('重试到上限（3 次）后放弃，错误信息留给用户看', () async {
      final FakeLoginTransport login = FakeLoginTransport(
        firstLoginError: '验证码错误!!',
        loginHtml: fixtureLoginFailedHtml,
      );
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        detailedTransport: login.call,
        accountStore: FakeAccountStore(),
        captchaRecognizer: FakeCaptchaRecognizer(
          <String>['1111', '2222', '3333'],
        ),
        swipeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await settleBootstrap();

      await controller.startLogin();
      final bool ok = await controller.autoLoginWithCaptcha(
        account: 'student',
        password: 'wrong',
      );

      expect(ok, isFalse);
      expect(login.loginCalls, 3, reason: '最多自动提交 3 次');
      expect(controller.loginError, '验证码错误!!');
    });

    test('识别不出验证码时不提交（web/桌面或模型不可用）', () async {
      final FakeLoginTransport login = FakeLoginTransport();
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        detailedTransport: login.call,
        accountStore: FakeAccountStore(),
        captchaRecognizer: FakeCaptchaRecognizer(<String?>[null]),
        swipeDebounce: Duration.zero,
      );
      addTearDown(controller.dispose);
      await settleBootstrap();

      await controller.startLogin();
      expect(controller.captchaGuess, isNull);

      final bool ok = await controller.autoLoginWithCaptcha(
        account: 'student',
        password: 'ab>',
      );

      expect(ok, isFalse);
      expect(login.loginCalls, 0, reason: '没有识别结果就不该提交');
    });
  });

  group('登录页的自动填入与自动提交', () {
    Future<void> openLogin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          loginTransport: FakeLoginTransport().call,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();
    }

    testWidgets('识别结果自动填进验证码框；账号密码齐了自动提交并返回', (
      WidgetTester tester,
    ) async {
      final List<bool> loggedIn = <bool>[false];
      final FakeLoginTransport login = FakeLoginTransport();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        jwApp(
          transport: loggedInMainTransport(loggedIn),
          loginTransport: togglingLoginTransport(login, loggedIn),
          captchaRecognizer: FakeCaptchaRecognizer(<String>['ab12']),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      // 识别结果自动填入验证码框；账号密码还没敲，不该自动提交。
      expect(find.text('ab12'), findsOneWidget);
      expect(login.loginCalls, 0);

      // 敲完账号密码 → 自动提交 → 成功后自动返回上一页。
      await tester.enterText(find.byType(EditableText).at(0), 'student');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).at(1), 'ab>');
      await tester.pumpAndSettle();

      expect(login.loginCalls, 1);
      expect(login.lastLoginBody, contains('RANDOMCODE=ab12'));
      expect(login.lastLoginBody, contains('userAccount=student'));
      // 登录成功 → pop 回「我的信息」，登录页的输入框不见了。
      expect(find.text('学号 / 账号'), findsNothing);
    });

    testWidgets('识别不出时验证码框留空，也不自动提交', (WidgetTester tester) async {
      final FakeLoginTransport login = FakeLoginTransport();
      await openLogin(tester);

      // 没有识别结果：敲完账号密码也不会自动提交。
      expect(find.text('学号 / 账号'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).at(0), 'student');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).at(1), 'ab>');
      await tester.pumpAndSettle();

      expect(login.loginCalls, 0, reason: '识别不出就不自动提交，交给用户手动');
    });
  });
}

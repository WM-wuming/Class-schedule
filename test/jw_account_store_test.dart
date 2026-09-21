import 'package:class_schedule/data/jw_account_store.dart';
import 'package:class_schedule/data/jw_client.dart';
import 'package:class_schedule/data/jw_http.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 一份「本机存过」的账户：会话 + 学号 + 学生信息快照。
  const JwStudentInfo storedStudent = JwStudentInfo(
    name: '张三',
    studentId: '202600000001',
    department: '信息学院',
    major: '软件工程',
    className: '26软件工程2班',
  );
  const JwStoredAccount storedAccount = JwStoredAccount(
    cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
    account: '202600000001',
    student: storedStudent,
  );

  group('本机账户信息的编解码', () {
    test('存下去再读回来，字段一个不少', () {
      final JwStoredAccount source = JwStoredAccount(
        cookie: 'JSESSIONID=a; HWWAFSESID=b',
        account: '202600000001',
        student: storedStudent,
        savedAt: DateTime(2026, 9, 21, 9, 30),
      );

      final JwStoredAccount? back = JwStoredAccount.fromJson(source.toJson());

      expect(back, isNotNull);
      expect(back!.cookie, source.cookie);
      expect(back.account, source.account);
      expect(back.savedAt, source.savedAt);
      expect(back.student?.name, '张三');
      expect(back.student?.studentId, '202600000001');
      expect(back.student?.department, '信息学院');
      expect(back.student?.major, '软件工程');
      expect(back.student?.className, '26软件工程2班');
    });

    test('只存了会话与学号也能读回来（学生信息快照可以没有）', () {
      final JwStoredAccount? back = JwStoredAccount.fromJson(
        const JwStoredAccount(
          cookie: 'JSESSIONID=a',
          account: '202600000001',
        ).toJson(),
      );

      expect(back?.cookie, 'JSESSIONID=a');
      expect(back?.student, isNull);
    });

    test('记住的密码能原样读回来；没存就是空串', () {
      final JwStoredAccount? remembered = JwStoredAccount.fromJson(
        const JwStoredAccount(
          cookie: 'JSESSIONID=a',
          account: '202600000001',
          password: 'ab>',
        ).toJson(),
      );
      expect(remembered?.password, 'ab>');

      // 旧版本 / 不勾选时存的内容里 password 是空串，读回来也是空串。
      final JwStoredAccount? plain = JwStoredAccount.fromJson(
        const JwStoredAccount(cookie: 'JSESSIONID=a').toJson(),
      );
      expect(plain?.password, isEmpty);

      // 结构里压根没有这个字段（上一版 App 写的）也不炸。
      final JwStoredAccount? legacy = JwStoredAccount.fromJson(
        <String, dynamic>{'cookie': 'a=1', 'account': 'x'},
      );
      expect(legacy?.password, isEmpty);
    });

    test('会话与学号都空的内容不算「存过」', () {
      expect(const JwStoredAccount(cookie: '', account: '').isEmpty, isTrue);
      expect(const JwStoredAccount(cookie: '  ', account: ' ').isEmpty, isTrue);
      expect(
        const JwStoredAccount(cookie: 'a=1').isEmpty,
        isFalse,
        reason: '有会话就算存过，学号可以没有',
      );
      expect(JwStoredAccount.fromJson(<String, dynamic>{}), isNull);
    });

    test('本地内容被改坏/是旧结构时不抛异常，当作没存过', () {
      // 字段类型全错
      expect(
        JwStoredAccount.fromJson(<String, dynamic>{
          'cookie': 123,
          'account': <String>[],
          'student': '张三',
        }),
        isNull,
      );
      // 学生信息在但一个有用字段都没有
      expect(
        JwStoredAccount.fromJson(<String, dynamic>{
          'cookie': 'a=1',
          'student': <String, dynamic>{'name': '', 'studentId': ''},
        })?.student,
        isNull,
      );
      // savedAt 类型不对：只丢时间，不影响会话
      final JwStoredAccount? back = JwStoredAccount.fromJson(<String, dynamic>{
        'cookie': 'a=1',
        'savedAt': '昨天',
      });
      expect(back?.cookie, 'a=1');
      expect(back?.savedAt, isNull);
    });

    test('内容一致时（只是保存时间不同）不算有变化', () {
      expect(
        storedAccount.sameContentAs(
          const JwStoredAccount(
            cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
            account: '202600000001',
            student: storedStudent,
            savedAt: null,
          ),
        ),
        isTrue,
        reason: '每次读主页面都写一遍同样的内容没意义',
      );
      expect(storedAccount.sameContentAs(null), isFalse);
      expect(
        storedAccount.sameContentAs(
          const JwStoredAccount(cookie: 'JSESSIONID=new', account: '202600000001'),
        ),
        isFalse,
        reason: '会话被服务端轮换过就要重写',
      );
      expect(
        storedAccount.sameContentAs(
          const JwStoredAccount(cookie: 'JSESSIONID=old; HWWAFSESID=waf123'),
        ),
        isFalse,
        reason: '换成别的账号后学号要跟着变',
      );
      expect(
        storedAccount.sameContentAs(
          const JwStoredAccount(
            cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
            account: '202600000001',
            student: JwStudentInfo(name: '别的同学', studentId: '202600000001'),
          ),
        ),
        isFalse,
      );
      expect(
        storedAccount.sameContentAs(
          const JwStoredAccount(
            cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
            account: '202600000001',
            student: storedStudent,
            password: 'changed',
          ),
        ),
        isFalse,
        reason: '记住的密码变了（勾选状态切换）也要重写',
      );
    });
  });

  group('SharedPreferences 里的账户存储', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('没存过时读到 null', () async {
      expect(await const PrefsAccountStore().read(), isNull);
    });

    test('存下去能读回来，清掉之后又没有了', () async {
      const PrefsAccountStore store = PrefsAccountStore();

      await store.write(storedAccount);
      final JwStoredAccount? back = await store.read();
      expect(back?.cookie, storedAccount.cookie);
      expect(back?.account, '202600000001');
      expect(back?.student?.name, '张三');
      expect(back?.savedAt, isNotNull);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('本地存的内容不是 JSON 时当作没存过', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsAccountStore.storageKey: '这不是 JSON',
      });
      expect(await const PrefsAccountStore().read(), isNull);
    });

    test('内容为空时不往本地写空壳', () async {
      await const PrefsAccountStore().write(
        const JwStoredAccount(cookie: ''),
      );
      expect(await const PrefsAccountStore().read(), isNull);
    });
  });

  group('启动时的会话优先级', () {
    const JwStoredAccount saved = JwStoredAccount(cookie: 'JSESSIONID=from-store');

    test('没存过会话时交给客户端自己兜底（未登录）', () {
      expect(ScheduleController.sessionCookieOf(null), isNull);
      expect(
        ScheduleController.sessionCookieOf(const JwStoredAccount(cookie: '  ')),
        isNull,
      );
    });

    test('存过就用本机的那份', () {
      expect(ScheduleController.sessionCookieOf(saved), 'JSESSIONID=from-store');
    });
  });

  group('控制器里的账户持久化', () {
    test('启动就带上本机保存的会话，学生信息先拿快照顶上', () async {
      final RecordingTransport transport = RecordingTransport();
      final ScheduleController controller = ScheduleController(
        transport: transport.call,
        accountStore: FakeAccountStore(storedAccount),
        restoredAccount: storedAccount,
        swipeDebounce: Duration.zero,
      );

      expect(controller.student?.name, '张三', reason: '首帧就该有内容，不用等联网');
      expect(controller.studentFromStore, isTrue, reason: '得说明这是本机副本');
      expect(controller.savedAccount, '202600000001');

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        transport.headers.first['X-JW-Cookie'],
        contains('JSESSIONID=old'),
        reason: '冷启动第一次请求就要带上会话，不然又得重新登录',
      );
      controller.dispose();
    });

    test('读到主页面后把学生信息落盘，且不再标注「来自本机」', () async {
      // 本机那份是旧的（只有姓名学号），主页面读通后应该被补全。
      const JwStoredAccount stale = JwStoredAccount(
        cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
        account: '202600000001',
        student: JwStudentInfo(name: '张三', studentId: '202600000001'),
      );
      final FakeAccountStore store = FakeAccountStore(stale);
      final ScheduleController controller = ScheduleController(
        transport: RecordingTransport().call,
        accountStore: store,
        restoredAccount: stale,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.studentFromStore, isFalse);
      expect(store.writes, 1, reason: '主页面读通了，学生信息该更新到本机');
      expect(store.value?.student?.name, '张三');
      expect(store.value?.student?.department, '信息学院');
      expect(
        store.value?.account,
        '202600000001',
        reason: '读到主页面不能把学号抹掉',
      );

      await controller.syncTermWithServer();
      expect(store.writes, 1, reason: '内容没变就别再写一遍');
      controller.dispose();
    });

    test('没有会话时读通主页面也不写盘（没东西可存）', () async {
      final FakeAccountStore store = FakeAccountStore();
      final ScheduleController controller = ScheduleController(
        transport: RecordingTransport().call,
        accountStore: store,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(store.writes, 0);
      expect(store.value, isNull);
      controller.dispose();
    });

    test('登录成功后把新会话与学号存到本机', () async {
      var loggedIn = false;
      final FakeLoginTransport login = FakeLoginTransport();
      final FakeAccountStore store = FakeAccountStore();
      final ScheduleController controller = ScheduleController(
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          if (!u.path.contains('xsMain')) {
            return fixtureHtml;
          }
          return loggedIn
              ? fixtureWeekInfoHtmlToday
              : '<html><head><title>用户登录</title></head></html>';
        },
        detailedTransport: (
          String m,
          Uri u,
          String b,
          Map<String, String> h,
        ) async {
          final JwHttpResponse response = await login.call(m, u, b, h);
          if (!u.path.contains('verifycode')) {
            loggedIn = true;
          }
          return response;
        },
        accountStore: store,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(store.writes, 0, reason: '还没登录，没东西可存');

      await controller.startLogin();
      final bool ok = await controller.submitLogin(
        account: '202600000001',
        password: 'ab>',
        captcha: 'A1B2',
      );

      expect(ok, isTrue);
      expect(store.value?.account, '202600000001');
      expect(
        store.value?.cookie,
        contains('JSESSIONID=after-login'),
        reason: '存下来的必须是登录换到的那份新会话',
      );
      expect(store.value?.student?.name, '张三');
      expect(controller.savedAccount, '202600000001', reason: '登录页下次要回填');
      controller.dispose();
    });

    test('勾选「记住密码」登录后，密码跟着落盘且回填', () async {
      var loggedIn = false;
      final FakeLoginTransport login = FakeLoginTransport();
      final FakeAccountStore store = FakeAccountStore();
      final ScheduleController controller = ScheduleController(
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          if (!u.path.contains('xsMain')) {
            return fixtureHtml;
          }
          return loggedIn
              ? fixtureWeekInfoHtmlToday
              : '<html><head><title>用户登录</title></head></html>';
        },
        detailedTransport: (
          String m,
          Uri u,
          String b,
          Map<String, String> h,
        ) async {
          final JwHttpResponse response = await login.call(m, u, b, h);
          if (!u.path.contains('verifycode')) {
            loggedIn = true;
          }
          return response;
        },
        accountStore: store,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await controller.startLogin();
      final bool ok = await controller.submitLogin(
        account: '202600000001',
        password: 'ab>',
        captcha: 'A1B2',
        rememberPassword: true,
      );

      expect(ok, isTrue);
      expect(store.value?.password, 'ab>', reason: '勾了就要存');
      expect(controller.savedPassword, 'ab>', reason: '登录页下次免输');
      controller.dispose();
    });

    test('不勾「记住密码」登录后，之前存的密码被抹掉', () async {
      var loggedIn = false;
      final FakeLoginTransport login = FakeLoginTransport();
      // 本机存过一份带密码的账户（用户之前勾过）。
      const JwStoredAccount remembered = JwStoredAccount(
        cookie: 'JSESSIONID=old; HWWAFSESID=waf123',
        account: '202600000001',
        password: 'ab>',
      );
      final FakeAccountStore store = FakeAccountStore(remembered);
      final ScheduleController controller = ScheduleController(
        transport: (String m, Uri u, String b, Map<String, String> h) async {
          if (!u.path.contains('xsMain')) {
            return fixtureHtml;
          }
          return loggedIn
              ? fixtureWeekInfoHtmlToday
              : '<html><head><title>用户登录</title></head></html>';
        },
        detailedTransport: (
          String m,
          Uri u,
          String b,
          Map<String, String> h,
        ) async {
          final JwHttpResponse response = await login.call(m, u, b, h);
          if (!u.path.contains('verifycode')) {
            loggedIn = true;
          }
          return response;
        },
        accountStore: store,
        restoredAccount: remembered,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.savedPassword, 'ab>');

      await controller.startLogin();
      // 注意没传 rememberPassword（默认 false）。
      final bool ok = await controller.submitLogin(
        account: '202600000001',
        password: 'ab>',
        captcha: 'A1B2',
      );

      expect(ok, isTrue);
      expect(
        store.value?.password,
        isEmpty,
        reason: '用户取消勾选的心意要立刻生效，不能留着旧密码',
      );
      expect(controller.savedPassword, isEmpty);
      controller.dispose();
    });

    test('退出登录：清掉本机账户，课表退回未登录', () async {
      final FakeAccountStore store = FakeAccountStore(storedAccount);
      final ScheduleController controller = ScheduleController(
        transport: jwExpiredTransport,
        accountStore: store,
        restoredAccount: storedAccount,
        swipeDebounce: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.hasSavedAccount, isTrue);

      await controller.signOut();

      expect(store.clears, 1);
      expect(store.value, isNull);
      expect(controller.savedAccount, isEmpty);
      expect(controller.savedPassword, isEmpty, reason: '记住的密码也一并清掉');
      expect(controller.student, isNull);
      expect(controller.studentFromStore, isFalse);
      expect(controller.hasSavedAccount, isFalse);
      expect(
        controller.sessionsOfWeek(controller.currentWeek),
        isEmpty,
        reason: '退出后不能再拿上一个会话的课表充数',
      );
      expect(controller.error, isNotNull, reason: '该给出可读的「未登录」提示');
      controller.dispose();
    });
  });

  group('「我的信息」页里的账户入口', () {
    testWidgets('本机存过账号时才有「退出登录」', (WidgetTester tester) async {
      await tester.pumpWidget(jwApp(transport: jwExpiredTransport));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      expect(find.text('退出登录'), findsNothing, reason: '什么都没存过就没什么可退的');
    });

    testWidgets('点「退出登录」后入口消失，账号快照也清掉', (WidgetTester tester) async {
      final FakeAccountStore store = FakeAccountStore(storedAccount);
      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          accountStore: store,
          restoredAccount: storedAccount,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      expect(find.text('退出登录'), findsOneWidget);
      expect(
        find.textContaining('这是本机保存的账号信息'),
        findsOneWidget,
        reason: '会话失效时要说清这份信息是从哪来的',
      );

      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();

      expect(store.value, isNull);
      expect(find.text('退出登录'), findsNothing);
      expect(find.text('还没有读到学生信息'), findsOneWidget);
    });

    testWidgets('读到主页面后不再标注「本机保存」', (WidgetTester tester) async {
      await tester.pumpWidget(
        jwApp(
          transport: jwOkTransport,
          accountStore: FakeAccountStore(storedAccount),
          restoredAccount: storedAccount,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      expect(find.textContaining('这是本机保存的账号信息'), findsNothing);
      expect(find.textContaining('登录信息（会话与学号）保存在本机'), findsOneWidget);
    });

    testWidgets('登录页会预填本机存过的学号', (WidgetTester tester) async {
      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          accountStore: FakeAccountStore(storedAccount),
          restoredAccount: storedAccount,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      expect(find.text('202600000001'), findsOneWidget);
    });

    testWidgets('记住过密码时，登录页预填密码且勾选默认打开', (WidgetTester tester) async {
      const JwStoredAccount remembered = JwStoredAccount(
        cookie: 'JSESSIONID=old',
        account: '202600000001',
        password: 'ab>',
      );
      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          accountStore: FakeAccountStore(remembered),
          restoredAccount: remembered,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      // 密码框是 obscureText 的，直接断言控制器/开关状态。
      expect(find.text('记住密码'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue,
          reason: '存过密码就默认勾上');
      // 预填值：从 LoginScreen 的状态里拿不到 TextField controller，
      // 通过「记住密码」开关的初始状态 + savedPassword getter 间接验证。
      final ScheduleController controller = ScheduleScope.of(
        tester.element(find.byType(Checkbox)),
      );
      expect(controller.savedPassword, 'ab>');
    });

    testWidgets('没记住密码时，登录页勾选默认关闭', (WidgetTester tester) async {
      await tester.pumpWidget(
        jwApp(
          transport: jwExpiredTransport,
          accountStore: FakeAccountStore(storedAccount),
          restoredAccount: storedAccount,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的信息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录教务系统'));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });
  });
}

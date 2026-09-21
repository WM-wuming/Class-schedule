import 'package:class_schedule/data/keep_alive_store.dart';
import 'package:class_schedule/models/keep_alive.dart';
import 'package:class_schedule/screens/settings_screen.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:class_schedule/widgets/sheet_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('保活设置模型', () {
    test('JSON 走个来回不丢字段', () {
      const KeepAliveSettings source = KeepAliveSettings(autoStart: true);

      final KeepAliveSettings restored = KeepAliveSettings.fromJson(
        source.toJson(),
      );

      expect(restored, source);
      expect(restored.autoStart, isTrue);
    });

    test('缺字段的存档退回默认值（不开机自启）', () {
      expect(
        KeepAliveSettings.fromJson(<String, dynamic>{}),
        const KeepAliveSettings(),
      );
      expect(
        KeepAliveSettings.fromJson(<String, dynamic>{'autoStart': 'yes'}),
        const KeepAliveSettings(),
        reason: '类型不对也要退回默认，而不是崩',
      );
    });
  });

  group('保活设置存储', () {
    test('没存过返回 null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const KeepAliveStore store = PrefsKeepAliveStore();

      expect(await store.read(), isNull);
    });

    test('写入后能原样读回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const KeepAliveStore store = PrefsKeepAliveStore();

      await store.write(const KeepAliveSettings(autoStart: true));

      expect(await store.read(), const KeepAliveSettings(autoStart: true));
    });

    test('存档坏掉时返回 null 而不是抛异常', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PrefsKeepAliveStore.storageKey: '{不是 JSON',
      });
      const KeepAliveStore store = PrefsKeepAliveStore();

      expect(await store.read(), isNull);
    });
  });

  group('控制器里的保活', () {
    ScheduleController build({
      FakeKeepAliveStore? store,
      FakeKeepAlivePlatform? platform,
      KeepAliveSettings? restored,
    }) => ScheduleController(
      transport: jwOkTransport,
      accountStore: FakeAccountStore(),
      reminderNotifier: FakeReminderNotifier(),
      reminderStore: FakeReminderStore(),
      customCourseStore: FakeCustomCourseStore(),
      keepAliveStore: store ?? FakeKeepAliveStore(),
      keepAlivePlatform: platform ?? FakeKeepAlivePlatform(),
      restoredKeepAlive: restored,
      swipeDebounce: Duration.zero,
    );

    /// 等冷启动那几件异步事（含电池优化状态查询）跑完。
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 120));

    test('冷启动还原上次保存的开关', () async {
      final ScheduleController controller = build(
        restored: const KeepAliveSettings(autoStart: true),
      );
      await settle();

      expect(controller.keepAliveSettings.autoStart, isTrue);
      controller.dispose();
    });

    test('打开开关后立刻落库', () async {
      final FakeKeepAliveStore store = FakeKeepAliveStore();
      final ScheduleController controller = build(store: store);
      await settle();

      await controller.updateKeepAliveSettings(
        controller.keepAliveSettings.copyWith(autoStart: true),
      );

      expect(store.writes, 1);
      expect(store.value?.autoStart, isTrue);
      controller.dispose();
    });

    test('值没变就不重复写盘', () async {
      final FakeKeepAliveStore store = FakeKeepAliveStore();
      final ScheduleController controller = build(store: store);
      await settle();

      await controller.updateKeepAliveSettings(controller.keepAliveSettings);

      expect(store.writes, 0);
      controller.dispose();
    });

    test('启动后能查到电池优化白名单状态', () async {
      final FakeKeepAlivePlatform platform = FakeKeepAlivePlatform(
        ignoring: true,
      );
      final ScheduleController controller = build(platform: platform);
      await settle();

      expect(controller.ignoringBatteryOptimizations, isTrue);
      controller.dispose();
    });

    test('申请跳过电池优化后状态跟着刷新', () async {
      final FakeKeepAlivePlatform platform = FakeKeepAlivePlatform();
      final ScheduleController controller = build(platform: platform);
      await settle();
      expect(controller.ignoringBatteryOptimizations, isFalse);

      final bool granted = await controller.requestIgnoreBatteryOptimizations();

      expect(granted, isTrue);
      expect(platform.batteryRequests, 1);
      expect(controller.ignoringBatteryOptimizations, isTrue);
      controller.dispose();
    });

    test('跳自启动管理走平台口', () async {
      final FakeKeepAlivePlatform platform = FakeKeepAlivePlatform();
      final ScheduleController controller = build(platform: platform);
      await settle();

      await controller.openAutoStartSettings();

      expect(platform.autoStartOpens, 1);
      controller.dispose();
    });

    test('不支持的平台上一切照旧、状态保持未知', () async {
      final FakeKeepAlivePlatform platform = FakeKeepAlivePlatform(
        supported: false,
      );
      final ScheduleController controller = build(platform: platform);
      await settle();

      expect(controller.keepAliveSupported, isFalse);
      expect(controller.ignoringBatteryOptimizations, isNull);

      await controller.refreshBatteryOptimizationStatus();
      expect(controller.ignoringBatteryOptimizations, isNull);
      expect(platform.batteryRequests, 0);
      controller.dispose();
    });
  });

  group('设置页的保活栏目', () {
    late FakeKeepAlivePlatform platform;
    late FakeKeepAliveStore store;
    late ScheduleController controller;

    Widget app() => FTheme(
      data: FThemeData(colors: FColors.neutralLight, touch: true),
      child: ScheduleScope(
        controller: controller,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    Future<void> pumpToKeepAlive(WidgetTester tester) async {
      // ListView 懒加载：保活栏目排在页面下方，视口必须拉够大才构建得出来。
      tester.view.physicalSize = const Size(1500, 5200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      // 设置页改成了二级页面结构：保活类在「保活」子页里。
      await tester.tap(find.text('保活'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      platform = FakeKeepAlivePlatform();
      store = FakeKeepAliveStore();
      controller = ScheduleController(
        transport: jwOkTransport,
        accountStore: FakeAccountStore(),
        reminderNotifier: FakeReminderNotifier(),
        reminderStore: FakeReminderStore(),
        customCourseStore: FakeCustomCourseStore(),
        keepAliveStore: store,
        keepAlivePlatform: platform,
        swipeDebounce: Duration.zero,
      );
    });

    tearDown(() => controller.dispose());

    testWidgets('栏目里有开机自启开关和耗电限制指引', (WidgetTester tester) async {
      await pumpToKeepAlive(tester);

      expect(find.text('保活'), findsOneWidget);
      expect(find.text('开机自启'), findsOneWidget);
      expect(find.text('后台耗电限制取消指引'), findsOneWidget);
    });

    testWidgets('打开自启开关会落库并跳去系统设置', (WidgetTester tester) async {
      await pumpToKeepAlive(tester);

      await tester.tap(find.text('开机自启'));
      await tester.pumpAndSettle();
      // 落库是异步的；testWidgets 里不能用真实延时（FakeAsync 区会死等），用泵表推进。
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.keepAliveSettings.autoStart, isTrue);
      expect(store.writes, 1);
      expect(platform.autoStartOpens, 1);
    });

    testWidgets('点指引打开保活弹层，里面能申请跳过电池优化', (WidgetTester tester) async {
      await pumpToKeepAlive(tester);

      await tester.tap(find.text('后台耗电限制取消指引'));
      await tester.pumpAndSettle();

      expect(find.text('保活指引'), findsOneWidget);
      expect(find.textContaining('尚未放行'), findsOneWidget);

      await tester.tap(find.text('申请跳过电池优化'));
      await tester.pumpAndSettle();

      expect(platform.batteryRequests, 1);
      // 用整句匹配：设置页被弹层盖着的那行副标题申请成功后也含「已放行」三个字。
      expect(
        find.textContaining('已放行：本应用在电池优化白名单里'),
        findsOneWidget,
        reason: '申请成功后状态卡片要从黄变绿',
      );
      expect(find.textContaining('尚未放行'), findsNothing);

      // 去自启动设置的按钮也在弹层里。
      await tester.tap(find.text('去自启动设置'));
      await tester.pumpAndSettle();
      expect(platform.autoStartOpens, 1);
    });

    testWidgets('保活弹层有白色 Material 底（forui 弹层不自带背景）', (
      WidgetTester tester,
    ) async {
      await pumpToKeepAlive(tester);

      await tester.tap(find.text('后台耗电限制取消指引'));
      await tester.pumpAndSettle();

      expect(find.text('保活指引'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('保活指引'),
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Material && widget.color == sheetSurfaceColor,
          ),
        ),
        findsOneWidget,
        reason: '弹层内容必须包在 SheetSurface（玻璃底 + Material）里，否则透出被压暗的页面',
      );
      // 液态玻璃：弹层本体一块 BackdropFilter，背后的 barrier 一块。
      expect(find.byType(BackdropFilter), findsAtLeastNWidgets(2));
    });

    testWidgets('不支持的平台上只给一句说明', (WidgetTester tester) async {
      platform.supported = false;
      await pumpToKeepAlive(tester);

      expect(find.text('开机自启'), findsNothing);
      expect(find.textContaining('没有后台概念'), findsOneWidget);
    });
  });
}

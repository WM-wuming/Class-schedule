import '../models/next_class.dart';
import 'widget_updater.dart';

/// 非 Android 平台（Web / 桌面）没有桌面小组件这回事，全部空操作。
class NoopWidgetUpdater implements WidgetUpdater {
  @override
  bool get isSupported => false;

  @override
  Future<void> update(List<NextClassEntry> entries) async {}
}

WidgetUpdater createPlatformWidgetUpdater() => NoopWidgetUpdater();

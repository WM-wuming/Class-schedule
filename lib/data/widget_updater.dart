import '../models/next_class.dart';

import 'widget_updater_stub.dart'
    if (dart.library.io) 'widget_updater_io.dart';

/// 把「接下来要上的课」推给 Android 桌面小组件的投递口。
///
/// 与存储类接口同一契约：**实现不许抛异常** —— 小组件显示旧内容没有关系，
/// 不能为了它打扰用户或弄崩课表页。
abstract interface class WidgetUpdater {
  /// 当前平台是否支持桌面小组件（只有 Android 支持）。
  bool get isSupported;

  /// 用新的条目列表刷新小组件。实现内部吞掉所有错误。
  Future<void> update(List<NextClassEntry> entries);
}

/// 按当前平台建投递口：Android 走平台通道，其它平台是空操作。
WidgetUpdater createWidgetUpdater() => createPlatformWidgetUpdater();

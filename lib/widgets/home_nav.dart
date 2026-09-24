import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 底部主导航的四个页面。
enum HomeTab {
  /// 课表。
  timetable('课表', FLucideIcons.layoutGrid),

  /// 教室状态查询。
  classroom('教室状态', FLucideIcons.doorOpen),

  /// 选课。
  selection('选课', FLucideIcons.bookOpen),

  /// 我的信息。
  profile('我的信息', FLucideIcons.user);

  const HomeTab(this.label, this.icon);

  /// 导航栏文案。
  final String label;

  /// 导航栏图标。
  final IconData icon;
}

/// 底部导航条：课表 / 教室状态 / 选课 / 我的信息。
///
/// forui 的 [FBottomNavigationBar] 通过 `index` + `onChange` 受控，
/// 子项 [FBottomNavigationBarItem] 只负责显示，不接收点击回调。
///
/// 手机上 forui 默认按系统手势条高度的 2/3 附加底部留白，菜单栏被顶得离屏幕底
/// 很远 —— 这里关掉 safeAreaBottom，改成固定的小留白让它贴近屏幕底部；
/// 桌面/Web 没有系统手势区，保持默认样式。
FBottomNavigationBar homeNavBar({
  required BuildContext context,
  required HomeTab current,
  required ValueChanged<HomeTab> onSelect,
}) {
  final bool hasSystemInset = MediaQuery.viewPaddingOf(context).bottom > 0;
  return FBottomNavigationBar(
    index: current.index,
    style: hasSystemInset
        ? const FBottomNavigationBarStyleDelta.delta(
            padding: EdgeInsetsGeometryDelta.value(
              EdgeInsets.only(left: 5, top: 5, right: 5, bottom: 10),
            ),
          )
        : const FBottomNavigationBarStyleDelta.context(),
    onChange: (int index) => onSelect(HomeTab.values[index]),
    children: <Widget>[
      for (final HomeTab tab in HomeTab.values)
        FBottomNavigationBarItem(
          icon: Icon(tab.icon, size: 22),
          label: Text(tab.label),
          semanticsLabel: tab.label,
        ),
    ],
  );
}

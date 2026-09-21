import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// 底部主导航的四个页面。
enum HomeTab {
  /// 课表。
  timetable('课表', FLucideIcons.layoutGrid),

  /// 空教室查询。
  classroom('空教室', FLucideIcons.doorOpen),

  /// 我的信息。
  profile('我的信息', FLucideIcons.user),

  /// 选课。
  selection('选课', FLucideIcons.bookOpen);

  const HomeTab(this.label, this.icon);

  /// 导航栏文案。
  final String label;

  /// 导航栏图标。
  final IconData icon;
}

/// 底部导航条：课表 / 空教室 / 我的信息 / 选课。
///
/// forui 的 [FBottomNavigationBar] 通过 `index` + `onChange` 受控，
/// 子项 [FBottomNavigationBarItem] 只负责显示，不接收点击回调。
FBottomNavigationBar homeNavBar({
  required HomeTab current,
  required ValueChanged<HomeTab> onSelect,
}) => FBottomNavigationBar(
  index: current.index,
  safeAreaBottom: true,
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

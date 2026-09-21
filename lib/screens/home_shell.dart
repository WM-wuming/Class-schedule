import 'package:flutter/widgets.dart';

import '../widgets/home_nav.dart';
import 'classroom_screen.dart';
import 'course_selection_screen.dart';
import 'profile_screen.dart';
import 'timetable_screen.dart';

/// 应用主框架：底部四个 Tab（课表 / 空教室 / 我的信息 / 选课）。
///
/// 每个 Tab 自己是完整的 `FScaffold`（各自有标题栏），底部共用同一个导航条。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late HomeTab _tab = _tabFromUrl();

  /// 初始 Tab 可以由 URL 片段指定
  /// （Web 端 `#classroom` / `#profile` / `#selection`，便于直达与截图）。
  static HomeTab _tabFromUrl() {
    final String fragment = Uri.base.fragment.toLowerCase();
    if (fragment.contains('classroom') || fragment.contains('room')) {
      return HomeTab.classroom;
    }
    if (fragment.contains('profile')) {
      return HomeTab.profile;
    }
    if (fragment.contains('selection') || fragment.contains('select')) {
      return HomeTab.selection;
    }
    return HomeTab.timetable;
  }

  @override
  Widget build(BuildContext context) => switch (_tab) {
    HomeTab.timetable => TimetableScreen(
      currentTab: _tab,
      onSelectTab: _select,
    ),
    HomeTab.classroom => ClassroomScreen(
      currentTab: _tab,
      onSelectTab: _select,
    ),
    HomeTab.profile => ProfileScreen(currentTab: _tab, onSelectTab: _select),
    HomeTab.selection => CourseSelectionScreen(
      currentTab: _tab,
      onSelectTab: _select,
    ),
  };

  void _select(HomeTab tab) {
    if (tab == _tab) {
      return;
    }
    setState(() => _tab = tab);
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../state/schedule_controller.dart';
import '../widgets/home_nav.dart';
import 'classroom_screen.dart';
import 'course_selection_screen.dart';
import 'profile_screen.dart';
import 'timetable_screen.dart';

/// 应用主框架：底部四个 Tab（课表 / 教室状态 / 选课 / 我的信息）。
///
/// 每个 Tab 自己是完整的 `FScaffold`（各自有标题栏），底部共用同一个导航条。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late HomeTab _tab = _tabFromUrl();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 回到前台时做提醒巡检：一条提醒触发之后，排期窗口末端就往未来挪了，
  /// 这时把还没拉的周课表补回来、新覆盖到的课接着排上提醒（见
  /// [ScheduleController.onAppResumed]）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(ScheduleScope.of(context).onAppResumed());
  }

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

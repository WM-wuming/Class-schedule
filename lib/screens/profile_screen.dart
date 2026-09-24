import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../data/jw_client.dart';
import '../data/keep_alive_platform.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/home_nav.dart';
import '../widgets/sheet_surface.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

/// 「我的信息」页：学生信息（来自教务系统主页面）+ 同步状态。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// 当前 Tab（底部导航高亮用）。
  final HomeTab currentTab;

  /// 切换 Tab。
  final ValueChanged<HomeTab> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final JwStudentInfo? student = controller.student;

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: const Text(
          '我的信息',
          style: TextStyle(
            color: GridColors.textPrimary,
            fontSize: 20,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      footer: homeNavBar(
        context: context,
        current: currentTab,
        onSelect: onSelectTab,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          _StudentCard(
            student: student,
            controller: controller,
            fromStore: controller.studentFromStore,
            onLogin: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LoginScreen(
                  initialAccount: controller.savedAccount,
                  initialPassword: controller.savedPassword,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('应用'),
          _group(<FTileMixin>[
            FTile(
              title: const Text('设置'),
              subtitle: const Text('学期与显示选项'),
              prefix: const Icon(FLucideIcons.settings, size: 18),
              onPress: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
            FTile(
              title: const Text('关于'),
              subtitle: const Text('版本信息与项目地址'),
              prefix: const Icon(FLucideIcons.info, size: 18),
              onPress: () => unawaited(_showAboutSheet(context)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// 顶部学生卡片。
class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.controller,
    required this.fromStore,
    required this.onLogin,
  });

  final JwStudentInfo? student;
  final ScheduleController controller;

  /// 这份学生信息是不是「本机保存的副本」（还没跟教务系统核对上）。
  final bool fromStore;

  /// 打开登录页。
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final JwStudentInfo? info = student;
    if (info == null || info.isEmpty) {
      return FCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '还没有读到学生信息',
                style: TextStyle(
                  color: GridColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '学生信息来自教务系统主页面；会话过期时就读不到了。'
                '可以用学号密码登录，换一份新的会话。',
                style: TextStyle(
                  color: GridColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  FButton(onPress: onLogin, child: const Text('登录教务系统')),
                  if (controller.hasSavedAccount) ...<Widget>[
                    const SizedBox(width: 10),
                    FButton(
                      variant: .outline,
                      onPress: () =>
                          unawaited(_confirmSignOut(context, controller)),
                      child: const Text(
                        '退出登录',
                        style: TextStyle(color: Color(0xFFD9534F)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  FButton(
                    variant: .outline,
                    onPress: controller.syncTermWithServer,
                    child: const Text('重新读取'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final String initial = info.name.isEmpty ? '?' : info.name.characters.first;

    return FCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 54,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: GridColors.today.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: GridColors.today,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        info.name.isEmpty ? '未知名' : info.name,
                        style: const TextStyle(
                          color: GridColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        info.studentId.isEmpty ? '—' : info.studentId,
                        style: const TextStyle(
                          color: GridColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (info.department != null)
              _InfoRow(label: '院系', value: info.department!),
            if (info.major != null) _InfoRow(label: '专业', value: info.major!),
            if (info.className != null)
              _InfoRow(label: '班级', value: info.className!),
            const SizedBox(height: 16),
            const Divider(height: 1, color: GridColors.divider),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FButton(
                  variant: .outline,
                  onPress: onLogin,
                  child: const Text('登录教务系统'),
                ),
                if (controller.hasSavedAccount) ...<Widget>[
                  const SizedBox(width: 10),
                  FButton(
                    variant: .outline,
                    onPress: () => unawaited(_confirmSignOut(context, controller)),
                    child: const Text(
                      '退出登录',
                      style: TextStyle(color: Color(0xFFD9534F)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              fromStore
                  ? '这是本机保存的账号信息，正在向教务系统核对；'
                        '会话过期时重新登录一次即可。'
                  : '登录信息（会话与学号）保存在本机，不会保存密码。',
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: GridColors.textPrimary, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// 项目主页（GitHub）。
const String _repoUrl = 'https://github.com/WM-wuming/Class-schedule';

/// 当前版本号。**发版时记得与 pubspec.yaml 的 version 同步改**。
const String _appVersion = '1.1.57';

/// 「关于」弹层：版本信息 + GitHub 项目入口（顺手点个 Star）。
Future<void> _showAboutSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  builder: (BuildContext sheetContext) => SheetSurface(
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '广应科课表',
              style: TextStyle(
                color: GridColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '版本 $_appVersion',
              style: const TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '这是一个开源项目，如果觉得好用，欢迎到 GitHub 给它点个 Star：',
              style: TextStyle(
                color: GridColors.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _repoUrl,
              style: const TextStyle(
                color: GridColors.today,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            FButton(
              onPress: () => unawaited(
                createKeepAlivePlatform().openUrl(_repoUrl),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(FLucideIcons.star, size: 16),
                  SizedBox(width: 6),
                  Text('去 GitHub 点个 Star'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

FTileGroup _group(List<FTileMixin> children) => FTileGroup(
  physics: const NeverScrollableScrollPhysics(),
  children: children,
);

/// 退出登录的二次确认弹窗；确认后执行 [controller.signOut]。
Future<void> _confirmSignOut(
  BuildContext context,
  ScheduleController controller,
) => showAppDialog<void>(
  context: context,
  builder: (BuildContext dialogContext) => GlassDialogSurface(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '退出登录',
            style: TextStyle(
              color: GridColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '将清除本机保存的登录信息（会话与学号），'
            '退出后需要重新登录才能刷新课表。自己添加的课程会保留。',
            style: TextStyle(
              color: GridColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              FButton(
                variant: .outline,
                onPress: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 10),
              FButton(
                onPress: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(controller.signOut());
                },
                child: const Text(
                  '退出',
                  style: TextStyle(color: Color(0xFFD9534F)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: GridColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

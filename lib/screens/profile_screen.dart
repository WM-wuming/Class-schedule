import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../data/jw_client.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/home_nav.dart';
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
        suffixes: <Widget>[
          FHeaderAction(
            icon: const Icon(FLucideIcons.refreshCw, size: 20),
            onPress: controller.syncTermWithServer,
          ),
        ],
      ),
      footer: homeNavBar(current: currentTab, onSelect: onSelectTab),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          _StudentCard(
            student: student,
            controller: controller,
            fromStore: controller.studentFromStore,
            onLogin: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LoginScreen(
                      initialAccount: controller.savedAccount,
                      initialPassword: controller.savedPassword,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionLabel('教务系统'),
          _group(<FTileMixin>[
            FTile(
              title: const Text('当前周次'),
              subtitle: Text(
                controller.weekInfoError ?? '来自教务系统主页面（周一到周日口径）',
              ),
              prefix: const Icon(FLucideIcons.calendarDays, size: 18),
              details: Text(
                controller.serverCurrentWeek == null
                    ? '未读取'
                    : '第 ${controller.serverCurrentWeek} 周',
              ),
              onPress: controller.syncTermWithServer,
            ),
            if (controller.hasSavedAccount)
              FTile(
                title: const Text('退出登录'),
                subtitle: const Text('清除本机保存的会话与学号'),
                prefix: const Icon(FLucideIcons.logOut, size: 18),
                onPress: controller.signOut,
              ),
          ]),
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
              title: const Text('版本'),
              details: const Text('1.1.7'),
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
                style: TextStyle(color: GridColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  FButton(onPress: onLogin, child: const Text('登录教务系统')),
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
            Align(
              alignment: Alignment.centerLeft,
              child: FButton(
                variant: .outline,
                onPress: onLogin,
                child: const Text('登录教务系统'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              fromStore
                  ? '这是本机保存的账号信息，正在向教务系统核对；'
                        '会话过期时重新登录一次即可。'
                  : '登录信息（会话与学号）保存在本机，不会保存密码。',
              style: const TextStyle(color: GridColors.textSecondary, fontSize: 12),
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
            style: const TextStyle(
              color: GridColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

FTileGroup _group(List<FTileMixin> children) => FTileGroup(
  physics: const NeverScrollableScrollPhysics(),
  children: children,
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

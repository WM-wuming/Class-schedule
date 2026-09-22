import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/keep_alive.dart';
import '../models/reminder.dart';
import '../models/week.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/keep_alive_sheet.dart';

/// 设置主页：每个类一个二级页面；「学期 / 显示 / 周次」三类合并进「课表」。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => FScaffold(
    childPad: false,
    header: _pageHeader(context, '设置'),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: <Widget>[
        _group(<FTileMixin>[
          _entryTile(
            context,
            icon: FLucideIcons.calendarDays,
            title: '课表',
            subtitle: '学期 · 显示 · 周次',
            page: const TimetableSettingsScreen(),
          ),
          _entryTile(
            context,
            icon: FLucideIcons.bell,
            title: '上课提醒',
            subtitle: '上课前的通知与提前量',
            page: const ReminderSettingsScreen(),
          ),
          _entryTile(
            context,
            icon: FLucideIcons.batteryCharging,
            title: '保活',
            subtitle: '开机自启与后台耗电',
            page: const KeepAliveSettingsScreen(),
          ),
        ]),
      ],
    ),
  );

  /// 一行二级页面入口。
  static FTile _entryTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) => FTile(
    title: Text(title),
    subtitle: Text(subtitle),
    prefix: Icon(icon, size: 18),
    suffix: const Icon(
      FLucideIcons.chevronRight,
      size: 16,
      color: GridColors.textSecondary,
    ),
    onPress: () =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => page)),
  );
}

/// 二级页面统一的页头：左侧标题 + 返回键。
FHeader _pageHeader(BuildContext context, String title) => FHeader.nested(
  title: Text(
    title,
    style: const TextStyle(
      color: GridColors.textPrimary,
      fontSize: 17,
      height: 1.1,
      fontWeight: FontWeight.w600,
    ),
  ),
  prefixes: <Widget>[
    FHeaderAction(
      icon: const Icon(FLucideIcons.chevronLeft, size: 20),
      onPress: () => Navigator.of(context).maybePop(),
    ),
  ],
);

/// 「课表」二级页：学期设置 + 显示选项 + 周次状态，三块合一。
class TimetableSettingsScreen extends StatelessWidget {
  const TimetableSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);
    final AppSettings settings = controller.settings;
    final Term term = settings.term;

    return FScaffold(
      childPad: false,
      header: _pageHeader(context, '课表'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: <Widget>[
          if (controller.error != null) ...<Widget>[
            const SizedBox(height: 8),
            _ErrorCard(message: controller.error!, onRetry: controller.refresh),
          ],
          const SizedBox(height: 18),
          const _SectionLabel('学期'),
          _group(<FTileMixin>[
            FTile(
              title: const Text('开学日期'),
              subtitle: const Text('第 1 周的周日'),
              prefix: const Icon(FLucideIcons.calendarDays, size: 18),
              details: Text(_formatDate(term.startDate)),
            ),
            FTile(
              title: const Text('往前挪一周'),
              subtitle: const Text('整个学期提前 7 天'),
              prefix: const Icon(FLucideIcons.chevronLeft, size: 18),
              onPress: () => controller.shiftTermStart(-7),
            ),
            FTile(
              title: const Text('往后挪一周'),
              subtitle: const Text('整个学期推迟 7 天'),
              prefix: const Icon(FLucideIcons.chevronRight, size: 18),
              onPress: () => controller.shiftTermStart(7),
            ),
            FTile(
              title: const Text('总周数'),
              subtitle: const Text('决定可选周次范围'),
              details: Text('${term.totalWeeks} 周'),
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FButton.icon(
                    variant: .outline,
                    onPress: () => controller.updateSettings(
                      settings.copyWith(
                        term: term.copyWith(
                          totalWeeks: _step(term.totalWeeks, -2),
                        ),
                      ),
                    ),
                    child: const Icon(FLucideIcons.chevronLeft, size: 16),
                  ),
                  const SizedBox(width: 6),
                  FButton.icon(
                    variant: .outline,
                    onPress: () => controller.updateSettings(
                      settings.copyWith(
                        term: term.copyWith(
                          totalWeeks: _step(term.totalWeeks, 2),
                        ),
                      ),
                    ),
                    child: const Icon(FLucideIcons.chevronRight, size: 16),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 18),
          const _SectionLabel('显示'),
          _group(<FTileMixin>[
            _switchTile(
              title: '显示周末',
              subtitle: '显示周六、周日两列',
              value: settings.showWeekend,
              onChanged: (bool value) => controller.updateSettings(
                settings.copyWith(showWeekend: value),
              ),
            ),
            _switchTile(
              title: '淡化非本周课程',
              subtitle: '本周不上课的课程变淡显示',
              value: settings.dimInactiveCourses,
              onChanged: (bool value) => controller.updateSettings(
                settings.copyWith(dimInactiveCourses: value),
              ),
            ),
            _switchTile(
              title: '显示教师',
              subtitle: '在课程卡片上显示任课教师',
              value: settings.showTeacher,
              onChanged: (bool value) => controller.updateSettings(
                settings.copyWith(showTeacher: value),
              ),
            ),
            _switchTile(
              title: '显示节次时间',
              subtitle: '在左侧时间轴显示每节起止时间',
              value: settings.showPeriodTime,
              onChanged: (bool value) => controller.updateSettings(
                settings.copyWith(showPeriodTime: value),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          const _SectionLabel('周次'),
          _group(<FTileMixin>[
            FTile(
              title: const Text('回到本周'),
              subtitle: Text('今天是第 ${controller.todayWeek} 周'),
              prefix: const Icon(FLucideIcons.calendarDays, size: 18),
              onPress: controller.backToCurrentWeek,
            ),
            FTile(
              title: const Text('本周排课'),
              subtitle: Text('第 ${controller.currentWeek} 周'),
              details: Text(
                '${controller.sessionsOfWeek(controller.currentWeek).length} 条',
              ),
            ),
            FTile(
              title: const Text('本周课时'),
              subtitle: Text('第 ${controller.currentWeek} 周'),
              details: Text(
                '${controller.weeklyPeriodCount(controller.currentWeek)} 节',
              ),
            ),
            if (controller.serverWeekOf(controller.currentWeek) != null)
              FTile(
                title: const Text('教务系统周次'),
                subtitle: const Text('若与本地不一致，可用「开学日期」校准'),
                details: Text(
                  '第 ${controller.serverWeekOf(controller.currentWeek)} 周',
                ),
              ),
          ]),
        ],
      ),
    );
  }

  static int _step(int current, int delta) {
    final int next = current + delta;
    if (next < 4) {
      return 4;
    }
    return next > 30 ? 30 : next;
  }

  static String _formatDate(DateTime date) =>
      '${date.year}/${date.month}/${date.day}';
}

/// 「上课提醒」二级页：开关 + 提前量 + 排期状态。
class ReminderSettingsScreen extends StatelessWidget {
  const ReminderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);

    return FScaffold(
      childPad: false,
      header: _pageHeader(context, '上课提醒'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: _reminderSection(controller),
      ),
    );
  }

  /// 「上课提醒」区：开关 + 提前量 + 排期状态。
  ///
  /// 界面要如实反映三件**互相独立**的事，不能混成一句「已开启」：
  /// * 用户在不在 App 里开着提醒（[ClassReminderSettings.enabled]）；
  /// * 系统放没放行通知权限 —— 没放行时提醒排得上但不会弹；
  /// * 这段时间到底排了几条、最近一条是什么时候。
  static List<Widget> _reminderSection(ScheduleController controller) {
    final ClassReminderSettings reminder = controller.reminderSettings;
    final bool supported = controller.reminderSupported;
    final bool enabled = reminder.enabled && supported;
    final bool granted = controller.reminderPermissionGranted;
    final ClassReminder? next = controller.nextReminder;
    final String? failure = controller.reminderError;

    return <Widget>[
      const SizedBox(height: 18),
      _group(<FTileMixin>[
        _reminderSwitchTile(controller: controller, supported: supported),
        FTile(
          title: const Text('提前时间'),
          subtitle: const Text('上课前多久提醒'),
          details: Text(reminder.leadLabel),
        ),
      ]),
      if (enabled) ...<Widget>[
        const SizedBox(height: 8),
        _leadPicker(controller, reminder),
        if (!granted) ...<Widget>[
          const SizedBox(height: 8),
          _NoticeCard(
            message: '系统还没放行通知权限，提醒排上了也弹不出来。',
            actionLabel: '去设置',
            onAction: () => unawaited(controller.openReminderSystemSettings()),
          ),
        ],
        // 响铃（勿扰豁免）：只查状态不弹窗，所以这里给入口让用户主动去授权。
        // 未知状态（null）不提示，避免「查不到」被误报成「没授权」。
        if (controller.ringSupported && controller.dndAccess == false) ...<Widget>[
          const SizedBox(height: 8),
          _NoticeCard(
            message: '手机开着勿扰或静音时，提醒不会响铃。点「去授权」后：'
                '在勿扰设置里点「允许例外」→ 勾选广应科课表；'
                '找不到就到系统设置搜「勿扰访问」，允许本应用。',
            actionLabel: '去授权',
            onAction: () => unawaited(controller.openRingSettings()),
          ),
        ],
        if (failure != null) ...<Widget>[
          const SizedBox(height: 8),
          _NoticeCard(
            message: failure,
            actionLabel: '重排',
            onAction: () => unawaited(controller.resyncReminders()),
          ),
        ],
        const SizedBox(height: 8),
        _group(<FTileMixin>[
          FTile(
            title: const Text('已排提醒'),
            subtitle: const Text('按手上的课表排未来两周，每次开 App 重排'),
            details: Text('${controller.reminders.length} 条'),
          ),
          // 勿扰豁免已拿到的正反馈：让用户确认「响铃」这事已经办妥了。
          if (controller.ringSupported && controller.dndAccess == true)
            FTile(
              title: const Text('响铃'),
              subtitle: const Text('已允许勿扰打扰，静音/勿扰下提醒照常响铃'),
            ),
          if (next != null)
            FTile(
              title: const Text('最近一条'),
              subtitle: Text('${next.courseName} · ${next.periodsLabel}'),
              details: Text(next.whenLabel),
            ),
        ]),
      ],
    ];
  }

  /// 开关那一行。
  ///
  /// 平台不支持系统通知时（Web）不给开关 —— 给了也只是个点不动的假开关，
  /// 不如直接说清为什么没有。
  static FTile _reminderSwitchTile({
    required ScheduleController controller,
    required bool supported,
  }) {
    if (!supported) {
      return FTile(
        title: const Text('上课前提醒'),
        subtitle: const Text('当前平台不支持系统通知（浏览器里关掉页面就提醒不了）'),
        prefix: const Icon(FLucideIcons.info, size: 18),
      );
    }
    final ClassReminderSettings reminder = controller.reminderSettings;
    return _switchTile(
      title: '上课前提醒',
      subtitle: '每节课上课前发一条通知',
      value: reminder.enabled,
      onChanged: (bool value) {
        unawaited(
          controller.updateReminderSettings(reminder.copyWith(enabled: value)),
        );
        if (value) {
          // 顺手把权限要下来；用户拒绝过的话系统不会再弹，界面会给提示。
          unawaited(controller.requestReminderPermission());
        }
      },
    );
  }

  /// 提前量：一排小标签，点一下就换。
  ///
  /// 存档里万一是个不在选项里的值（老版本写的），也把它摆出来，别让用户看到
  /// 「提前 7 分钟」却在下面找不到任何被选中的选项。
  static Widget _leadPicker(
    ScheduleController controller,
    ClassReminderSettings reminder,
  ) {
    final List<int> options = <int>[
      ...ClassReminderSettings.leadOptions,
      if (!ClassReminderSettings.leadOptions.contains(reminder.leadMinutes))
        reminder.leadMinutes,
    ]..sort();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final int minutes in options)
            _OptionChip(
              label: _minutesLabel(minutes),
              selected: reminder.leadMinutes == minutes,
              onTap: () => unawaited(
                controller.updateReminderSettings(
                  reminder.copyWith(leadMinutes: minutes),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 60 → 「1 小时」，其余 → 「10 分钟」。
  static String _minutesLabel(int minutes) => minutes >= 60 && minutes % 60 == 0
      ? '${minutes ~/ 60} 小时'
      : '$minutes 分钟';
}

/// 「保活」二级页：开机自启 + 后台耗电限制取消指引。
class KeepAliveSettingsScreen extends StatelessWidget {
  const KeepAliveSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);

    final List<Widget> children;
    if (!controller.keepAliveSupported) {
      children = <Widget>[
        const SizedBox(height: 18),
        _group(<FTileMixin>[
          FTile(
            title: const Text('开机自启 / 后台保活'),
            subtitle: const Text('当前平台（浏览器）没有后台概念，也不存在保活'),
            prefix: const Icon(FLucideIcons.info, size: 18),
          ),
        ]),
      ];
    } else {
      final KeepAliveSettings keepAlive = controller.keepAliveSettings;
      final bool? ignoring = controller.ignoringBatteryOptimizations;
      children = <Widget>[
        const SizedBox(height: 18),
        _group(<FTileMixin>[
          _switchTile(
            title: '开机自启',
            subtitle: '重启手机后自动恢复上课提醒（还需在系统里放行自启动）',
            value: keepAlive.autoStart,
            onChanged: (bool value) {
              unawaited(
                controller.updateKeepAliveSettings(
                  keepAlive.copyWith(autoStart: value),
                ),
              );
              if (value) {
                // 打开就带用户去系统的自启动管理 —— 那才是真正的开关。
                unawaited(controller.openAutoStartSettings());
              }
            },
          ),
          FTile(
            title: const Text('后台耗电限制取消指引'),
            subtitle: Text(
              ignoring == true
                  ? '已放行电池优化白名单，提醒可以准点响'
                  : '被系统杀后台是提醒不响的头号原因，点开看分步指引',
            ),
            prefix: const Icon(FLucideIcons.batteryCharging, size: 18),
            onPress: () => showKeepAliveGuide(context, controller: controller),
          ),
        ]),
      ];
    }

    return FScaffold(
      childPad: false,
      header: _pageHeader(context, '保活'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: children,
      ),
    );
  }
}

/// 一组设置项。[FTileGroup] 内部的滚动视图会 shrinkWrap，
/// 所以这里可以直接放进 [ListView]，不需要额外限高。
FTileGroup _group(List<FTileMixin> children) => FTileGroup(
  physics: const NeverScrollableScrollPhysics(),
  children: children,
);

/// 一行「标题 + 说明 + 开关」的设置项。
///
/// [FTileGroup] 只接受 [FTileMixin]，所以这里返回 [FTile] 而不是包一层自定义组件。
FTile _switchTile({
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => FTile(
  title: Text(title),
  subtitle: Text(subtitle),
  onPress: () => onChanged(!value),
  suffix: FSwitch(value: value, onChange: onChanged),
);

/// 一个小圆角标签，选中时用主色调（和「空教室」页的筛选标签同一套样子）。
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? GridColors.today : const Color(0xFFF2F4F8),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFFFFFFFF) : GridColors.textPrimary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}

/// 一条需要用户处理的提示（权限没给、排期失败），带一个动作按钮。
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF0D9A8)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8A6116), fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FButton(
            variant: .outline,
            onPress: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

/// 拉取失败时的提示卡片。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF0D9A8)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8A6116), fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FButton(variant: .outline, onPress: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

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

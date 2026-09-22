import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import 'sheet_surface.dart';

/// 弹出「保活指引」底部弹层。
///
/// 讲清楚两件事：为什么课表 App 要保活（提醒要在后台准点响），
/// 以及在常见国产 ROM 上分别去哪里放行。弹层是**只读指引 + 跳转入口**，
/// App 自己没有能力也不该代替用户去改系统设置。
Future<void> showKeepAliveGuide(
  BuildContext context, {
  required ScheduleController controller,
}) => showAppSheet<void>(
  context: context,
  builder: (BuildContext sheetContext) => SheetSurface(
    child: _KeepAliveGuideSheet(
      controller: controller,
      onClose: () => Navigator.of(sheetContext).maybePop(),
    ),
  ),
);

class _KeepAliveGuideSheet extends StatelessWidget {
  const _KeepAliveGuideSheet({required this.controller, required this.onClose});

  final ScheduleController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // 控制器是 ChangeNotifier：用户点了「申请跳过电池优化」后状态会变，
    // 弹层要跟着重画（状态卡片从黄变绿）。
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final bool? ignoring = controller.ignoringBatteryOptimizations;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '保活指引',
                          style: TextStyle(
                            color: GridColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(FLucideIcons.x, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const _Paragraph(
                    '上课提醒靠系统闹钟在后台准点响。省电策略太狠的系统会把闹钟一并拦下——'
                    '提醒排上了却不弹，多半就是被「杀后台」了。按下面的步骤放行一次即可。',
                  ),
                  const SizedBox(height: 12),
                  if (controller.keepAliveSupported) ...<Widget>[
                    _batteryStatusCard(ignoring),
                    const SizedBox(height: 12),
                  ],
                  _GroupLabel('第一步 · 允许自启动'),
                  const _GuideCard(<String>[
                    '系统设置 → 应用管理 → 广应科课表 → 自启动，打开开关。',
                    '小米/华为/OPPO/vivo 等机型有独立的「自启动管理」入口，点下面的按钮直达。',
                  ]),
                  const SizedBox(height: 10),
                  _ActionRow(
                    label: '去自启动设置',
                    icon: FLucideIcons.power,
                    onTap: () => unawaited(controller.openAutoStartSettings()),
                  ),
                  const SizedBox(height: 12),
                  _GroupLabel('第二步 · 后台不受限制'),
                  const _GuideCard(<String>[
                    '设置 → 电池 → 找到本应用 → 选「不受限制 / 无限制 / 允许后台运行」。',
                    'Android 原生入口在「电池优化」列表里：全部应用 → 广应科课表 → 不优化。',
                  ]),
                  const SizedBox(height: 10),
                  if (controller.keepAliveSupported) ...<Widget>[
                    _ActionRow(
                      label: '申请跳过电池优化',
                      icon: FLucideIcons.batteryCharging,
                      onTap: () => unawaited(
                        controller.requestIgnoreBatteryOptimizations(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActionRow(
                      label: '打开电池优化列表',
                      icon: FLucideIcons.list,
                      onTap: () => unawaited(
                        controller.openBatteryOptimizationSettings(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _GroupLabel('第三步 · 关掉省电模式'),
                  const _GuideCard(<String>[
                    '低电量自动开启省电模式的机型（低端机尤其常见），即使白名单放行也会连闹钟一起拦。',
                    '关掉省电模式 / 超级省电，或在省电设置里允许本应用后台运行。',
                  ]),
                  const SizedBox(height: 10),
                  if (controller.keepAliveSupported) ...<Widget>[
                    _ActionRow(
                      label: '打开省电模式设置',
                      icon: FLucideIcons.batteryLow,
                      onTap: () => unawaited(
                        controller.openBatterySaverSettings(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _GroupLabel('第四步 · 锁定后台（可选）'),
                  const _GuideCard(<String>[
                    '打开最近任务（多任务）卡片，下拉本应用卡片出现锁图标即已锁定。',
                    '再在系统的通知设置里确认「上课提醒」渠道没有被静音或关闭。',
                  ]),
                  const SizedBox(height: 12),
                  _ActionRow(
                    label: '打开应用详情页',
                    icon: FLucideIcons.settings2,
                    onTap: () => unawaited(controller.openAppDetailsSettings()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 电池优化白名单现状 + 一键放行。
  Widget _batteryStatusCard(bool? ignoring) {
    final String text;
    switch (ignoring) {
      case true:
        text = '已放行：本应用在电池优化白名单里，闹钟基本不会被省电策略拦截。';
      case false:
        text = '尚未放行：点「申请跳过电池优化」，在弹出的系统确认框里选「允许」。';
      case null:
        text = '正在查询电池优化状态…';
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ignoring == true
            ? const Color(0xFFEAF7EE)
            : const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ignoring == true
              ? const Color(0xFFBFE3C8)
              : const Color(0xFFF0D9A8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(
              ignoring == true ? FLucideIcons.checkCircle2 : FLucideIcons.info,
              size: 16,
              color: ignoring == true
                  ? const Color(0xFF2E7D43)
                  : const Color(0xFFB7791F),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: ignoring == true
                      ? const Color(0xFF2E7D43)
                      : const Color(0xFF8A6116),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一段普通说明文字。
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: GridColors.textSecondary,
      fontSize: 12.5,
      height: 1.45,
    ),
  );
}

/// 步骤卡片：灰底圆角容器里列几条要点。
class _GuideCard extends StatelessWidget {
  const _GuideCard(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF6F7FA),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String item in items) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(
                    FLucideIcons.circleSmall,
                    size: 12,
                    color: GridColors.today,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: GridColors.textPrimary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (item != items.last) const SizedBox(height: 6),
          ],
        ],
      ),
    ),
  );
}

/// 一个整行可点的动作按钮。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FButton(
    variant: .outline,
    onPress: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(icon, size: 15),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
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

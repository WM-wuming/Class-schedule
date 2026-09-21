import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';

/// 「第 N 周 ▾」胶囊按钮：点开后弹出周次列表，可直接跳到某一周。
class WeekPickerPill extends StatelessWidget {
  const WeekPickerPill({super.key, required this.controller});

  /// 课表状态。
  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return FPopover(
      popoverAnchor: Alignment.bottomCenter,
      childAnchor: Alignment.topCenter,
      builder: (BuildContext context, FPopoverController popover, Widget? child) =>
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: popover.toggle,
            child: child,
          ),
      popoverBuilder: (BuildContext context, FPopoverController popover) =>
          _WeekList(controller: controller, popover: popover),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: GridColors.weekBadgeFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '第 ${controller.currentWeek} 周',
              style: const TextStyle(
                color: GridColors.weekBadgeText,
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              FLucideIcons.chevronDown,
              size: 14,
              color: GridColors.weekBadgeText,
            ),
          ],
        ),
      ),
    );
  }
}

/// 周次列表弹层。
class _WeekList extends StatelessWidget {
  const _WeekList({required this.controller, required this.popover});

  final ScheduleController controller;
  final FPopoverController popover;

  @override
  Widget build(BuildContext context) {
    final List<int> weeks = controller.term.weeks;

    return SizedBox(
      width: 220,
      height: 320,
      child: FCard(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '选择周次',
                      style: TextStyle(
                        color: GridColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!controller.isCurrentWeek)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        controller.backToCurrentWeek();
                        popover.hide();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          '回到本周',
                          style: TextStyle(
                            color: GridColors.today,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: weeks.length,
                itemBuilder: (BuildContext context, int index) {
                  final int week = weeks[index];
                  return FTile(
                    title: Text('第 $week 周'),
                    subtitle: Text(controller.term.rangeLabelOf(week)),
                    selected: week == controller.currentWeek,
                    onPress: () {
                      controller.goToWeek(week);
                      popover.hide();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

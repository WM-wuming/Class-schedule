import 'package:class_schedule/models/week.dart';
import 'package:class_schedule/state/schedule_controller.dart';
import 'package:class_schedule/widgets/timetable_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 今天落在第几周（钳到学期范围内），与 `ScheduleController.todayWeek` 同一口径。
int todayWeek(Term term) => term.weekOf(DateTime.now()).clamp(1, term.totalWeeks);

void main() {
  testWidgets('手机宽度下 7 列都应在视口内', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    // 课表默认停在「本周」，日期随今天是哪天而变 —— 别写死，按当前周算。
    final List<ScheduleDay> days = defaultTerm.daysOf(todayWeek(defaultTerm));

    final double viewport =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final double gridWidth = tester.getSize(find.byType(TimetableGrid)).width;
    final Rect last = tester.getRect(find.text(days.last.dateLabel));
    final Rect first = tester.getRect(find.text(days.first.dateLabel));

    debugPrint(
      '视口=$viewport 网格=$gridWidth 首列中心=${first.center.dx} 末列中心=${last.center.dx}',
    );

    expect(gridWidth, closeTo(viewport, 1.0));
    expect(last.center.dx, lessThan(viewport));
    expect(last.right, lessThanOrEqualTo(viewport + 1));
  });
}

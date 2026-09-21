import 'package:class_schedule/widgets/timetable_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('手机宽度下 7 列都应在视口内', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    final double viewport = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final double gridWidth = tester.getSize(find.byType(TimetableGrid)).width;
    final Rect last = tester.getRect(find.text('9/26'));
    final Rect first = tester.getRect(find.text('9/20'));

    debugPrint('视口=$viewport 网格=$gridWidth 首列中心=${first.center.dx} 末列中心=${last.center.dx}');

    expect(gridWidth, closeTo(viewport, 1.0));
    expect(last.center.dx, lessThan(viewport));
    expect(last.right, lessThanOrEqualTo(viewport + 1));
  });
}

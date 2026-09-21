import 'package:class_schedule/widgets/timetable_grid.dart';
import 'package:class_schedule/widgets/week_strip.dart';

import 'fakes.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课表里的字由系统字号设置缩放，网格尺寸要跟着一起缩放 ——
/// 否则字放大了格子没变，文字就被固定大小的格子裁掉。
void main() {
  group('排版尺度', () {
    /// 取某个字号设置下的缩放系数。
    Future<double> factorAt(WidgetTester tester, TextScaler scaler) async {
      late double factor;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Builder(
            builder: (BuildContext context) {
              factor = TimetableScale.of(context).factor;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return factor;
    }

    testWidgets('跟随系统字号，并按上下限收口', (WidgetTester tester) async {
      expect(await factorAt(tester, const TextScaler.linear(1)), 1);
      expect(
        await factorAt(tester, const TextScaler.linear(1.3)),
        closeTo(1.3, 0.001),
      );
      // 系统字号调到极端时，网格不跟着无限放大/缩小。
      expect(
        await factorAt(tester, const TextScaler.linear(3)),
        TimetableScale.maxFactor,
      );
      expect(
        await factorAt(tester, const TextScaler.linear(0.4)),
        TimetableScale.minFactor,
      );
    });

    testWidgets('固定像素按系数换算', (WidgetTester tester) async {
      const TimetableScale scale = TimetableScale(1.5);
      expect(scale.px(70), closeTo(105, 0.001));
      expect(scale.px(TimetableGrid.gutterWidth), closeTo(60, 0.001));
      expect(const TimetableScale(1).px(TimetableGrid.periodHeight), 62);
    });
  });

  testWidgets('系统字号放大时，格子、间距与网格一起放大', (WidgetTester tester) async {
    const double factor = 1.5;
    tester.platformDispatcher.textScaleFactorTestValue = factor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    // 节次行高（时间轴里相邻两节的行距）变高，字才有地方站。
    expect(
      tester.getCenter(find.text('第二节')).dy -
          tester.getCenter(find.text('第一节')).dy,
      closeTo(TimetableGrid.periodHeight * factor, 0.6),
    );

    // 左侧时间轴跟着变宽，节次名仍在时间轴里水平居中。
    expect(
      tester.getCenter(find.text('第一节')).dx,
      closeTo(TimetableGrid.gutterWidth * factor / 2, 0.6),
    );

    // 顶部日期条跟网格同一套尺度，否则日期列会和下面的格子错位。
    expect(
      tester.getSize(find.byType(WeekStrip)).height,
      closeTo(WeekStrip.height * factor, 0.6),
    );

    // 课程卡片：格子（含上下让出的间隙）按节数 × 行高 × 系数长高。
    final Rect military = tester.getRect(
      find
          .ancestor(
            of: find.text('军事理论'),
            matching: find.byType(CourseBlock),
          )
          .first,
    );
    expect(
      military.height,
      closeTo(TimetableGrid.periodHeight * 3 * factor, 0.6),
    );
    expect(
      military.width,
      closeTo(
        (tester.getSize(find.byType(TimetableGrid)).width -
                TimetableGrid.gutterWidth * factor) /
            7 -
            TimetableGrid.columnInset * 2,
        0.6,
      ),
    );

    // 放大过程中不能有溢出报错（字会被格子裁掉是这次要修的问题）。
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统字号缩小时，网格跟着收紧', (WidgetTester tester) async {
    const double factor = 0.85;
    tester.platformDispatcher.textScaleFactorTestValue = factor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(jwApp());
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('第二节')).dy -
          tester.getCenter(find.text('第一节')).dy,
      closeTo(TimetableGrid.periodHeight * factor, 0.6),
    );
    expect(tester.takeException(), isNull);
  });
}

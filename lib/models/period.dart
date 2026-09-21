import 'package:flutter/foundation.dart';

/// 课表中的一个节次（第 N 节）。
@immutable
class Period {
  const Period({
    required this.index,
    required this.label,
    required this.start,
    required this.end,
    this.breakAfter,
  });

  /// 第几节，从 1 开始。
  final int index;

  /// 节次名称，例如「第一节」。
  final String label;

  /// 开始时间，格式 HH:mm。
  final String start;

  /// 结束时间，格式 HH:mm。
  final String end;

  /// 该节次之后插入的全宽休息行标题，例如「午休」。
  final String? breakAfter;

  /// 默认节次表。
  static const List<Period> defaults = <Period>[
    Period(index: 1, label: '第一节', start: '08:20', end: '09:05'),
    Period(index: 2, label: '第二节', start: '09:10', end: '09:55'),
    Period(index: 3, label: '第三节', start: '10:15', end: '11:00'),
    Period(
      index: 4,
      label: '第四节',
      start: '11:05',
      end: '11:50',
      breakAfter: '午休',
    ),
    Period(index: 5, label: '第五节', start: '14:30', end: '15:15'),
    Period(index: 6, label: '第六节', start: '15:20', end: '16:05'),
    Period(index: 7, label: '第七节', start: '16:25', end: '17:10'),
    Period(
      index: 8,
      label: '第八节',
      start: '17:15',
      end: '18:00',
      breakAfter: '晚休',
    ),
    Period(index: 9, label: '第九节', start: '19:00', end: '19:45'),
    Period(index: 10, label: '第十节', start: '19:50', end: '20:35'),
    Period(index: 11, label: '第十一节', start: '20:40', end: '21:25'),
  ];
}

import 'package:flutter/widgets.dart';

/// 课程卡片的配色：柔和的底色 + 用于文字和左侧色条的强调色。
@immutable
class CourseColor {
  const CourseColor({required this.fill, required this.accent});

  /// 卡片底色。
  final Color fill;

  /// 课程名文字与左侧色条的颜色。
  final Color accent;
}

/// 按课程名稳定取色，保证同名课程始终是同一种颜色。
abstract final class CoursePalette {
  static const List<CourseColor> _palette = <CourseColor>[
    CourseColor(fill: Color(0xFFFBF3D6), accent: Color(0xFF9C7A1B)), // 黄
    CourseColor(fill: Color(0xFFE4EDFD), accent: Color(0xFF2C63D4)), // 蓝
    CourseColor(fill: Color(0xFFE3F3E7), accent: Color(0xFF2C7A45)), // 绿
    CourseColor(fill: Color(0xFFDCF2ED), accent: Color(0xFF1B8E7D)), // 青
    CourseColor(fill: Color(0xFFFBE2EE), accent: Color(0xFFBE3D77)), // 粉
    CourseColor(fill: Color(0xFFE8EAF6), accent: Color(0xFF4B5AA5)), // 蓝紫
    CourseColor(fill: Color(0xFFFCE8DC), accent: Color(0xFFB65C2E)), // 橙
    CourseColor(fill: Color(0xFFEDE4F7), accent: Color(0xFF6A4CA8)), // 紫
  ];

  /// 课程 [courseName] 对应的配色。
  static CourseColor of(String courseName) =>
      _palette[_stableHash(courseName) % _palette.length];

  static int _stableHash(String value) {
    var hash = 0;
    for (final int unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

/// 课表网格用到的中性色。
abstract final class GridColors {
  /// 页面背景。
  static const Color page = Color(0xFFF5F5F7);

  /// 课程区域背景。
  static const Color surface = Color(0xFFFFFFFF);

  /// 左侧节次时间轴背景。
  static const Color gutter = Color(0xFFF7F7F9);

  /// 午休分隔行背景。
  static const Color breakBand = Color(0xFFEFEFF3);

  /// 网格分隔线。
  static const Color divider = Color(0xFFEDEDF1);

  /// 今天所在列的淡淡高亮。
  static const Color todayColumn = Color(0xFFF3F7FE);

  /// 主要文字。
  static const Color textPrimary = Color(0xFF1F2430);

  /// 次要文字（时间、地点、教师、周次）。
  static const Color textSecondary = Color(0xFF8A8F9C);

  /// 当前日期与「第 N 周」标签的强调色。
  static const Color today = Color(0xFF2C63D4);

  /// 「第 N 周」标签的底色与文字色。
  static const Color weekBadgeFill = Color(0xFFFDE7E7);
  static const Color weekBadgeText = Color(0xFFD9534F);
}

import 'package:flutter/foundation.dart';

/// 一段节次范围，对应教室空余表里的一列（一个「大节」，例如第 1-2 节）。
@immutable
class JwPeriodRange {
  const JwPeriodRange({required this.start, required this.end});

  /// 起始节次（含）。
  final int start;

  /// 结束节次（含）。
  final int end;

  /// 描述，例如「第 1-2 节」。
  String get label => start == end ? '第 $start 节' : '第 $start-$end 节';

  /// 与 [other] 有没有重叠（用于「这段时间空不空」的判断）。
  bool overlaps(JwPeriodRange other) => start <= other.end && other.start <= end;

  @override
  bool operator ==(Object other) =>
      other is JwPeriodRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'JwPeriodRange($start-$end)';
}

/// 教室表格里一个被占用的格子。
@immutable
class JwClassroomBusy {
  const JwClassroomBusy({
    required this.weekday,
    required this.periods,
    required this.label,
    this.detail,
  });

  /// 星期几，取值 `DateTime.monday` ~ `DateTime.sunday`。
  final int weekday;

  /// 被占用的节次。
  final JwPeriodRange periods;

  /// 占用它的课程名（格子里的第一行）。
  final String label;

  /// 格子里的其余内容（教师、班级等），可能为空。
  final String? detail;
}

/// 一间教室在某个星期、某一周的占用情况。
@immutable
class JwClassroom {
  const JwClassroom({
    required this.name,
    this.busy = const <JwClassroomBusy>[],
    this.extras = const <String, String>{},
  });

  /// 教室名，例如「J1-101」。
  final String name;

  /// 有课的格子（空格子 = 空闲，不入列表）。
  final List<JwClassroomBusy> busy;

  /// 表格里其它列的值，键是表头文字（例如「容量」→「60」）。
  ///
  /// 不同学校的表格列不一样（有的给容量、有的给教室类型），所以这里不硬编码字段。
  final Map<String, String> extras;

  /// [periods] 这段时间里有没有课。
  bool isBusyIn(JwPeriodRange periods) =>
      busy.any((JwClassroomBusy item) => item.periods.overlaps(periods));

  /// [periods] 这段时间里占用的课。
  List<JwClassroomBusy> busyIn(JwPeriodRange periods) => <JwClassroomBusy>[
    for (final JwClassroomBusy item in busy)
      if (item.periods.overlaps(periods)) item,
  ];

  /// 整天都没有课。
  bool get isFreeAllDay => busy.isEmpty;
}

/// 下拉选项（校区 / 教学楼）。
@immutable
class JwClassroomOption {
  const JwClassroomOption({required this.id, required this.name});

  /// 提交给教务系统的值（`xqid` / `jzwid`）。
  final String id;

  /// 显示名，例如「南校区」「第一教学楼」。
  final String name;

  @override
  bool operator ==(Object other) =>
      other is JwClassroomOption && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// 教室空余查询的查询条件 —— 只有这里的字段会影响**联网请求**。
///
/// 「只看第几节」不在其中：接口一次返回一整天，节次筛选在本地做（见
/// [JwClassroomBoard.periodColumns]），所以切节次不需要重新联网。
@immutable
class JwClassroomQuery {
  const JwClassroomQuery({
    required this.week,
    required this.weekday,
    this.campusId = '',
    this.buildingId = '',
  });

  /// 周次（`zc1` / `zc2`）。
  final int week;

  /// 星期几（`skxq1` / `skxq2`），1 = 周一。
  final int weekday;

  /// 校区（`xqid`）；空串 = 不限。
  final String campusId;

  /// 教学楼（`jzwid`）；空串 = 不限。
  final String buildingId;

  /// 复制并替换部分字段。
  JwClassroomQuery copyWith({
    int? week,
    int? weekday,
    String? campusId,
    String? buildingId,
  }) => JwClassroomQuery(
    week: week ?? this.week,
    weekday: weekday ?? this.weekday,
    campusId: campusId ?? this.campusId,
    buildingId: buildingId ?? this.buildingId,
  );

  /// 是否与 [other] 是同一组请求参数（相同就不必重新联网）。
  bool sameRequestAs(JwClassroomQuery other) =>
      week == other.week &&
      weekday == other.weekday &&
      campusId == other.campusId &&
      buildingId == other.buildingId;
}

/// 一次「教室空余查询」的结果。
@immutable
class JwClassroomBoard {
  const JwClassroomBoard({
    required this.classrooms,
    required this.week,
    required this.weekday,
    this.periodColumns = const <JwPeriodRange>[],
    this.campusOptions = const <JwClassroomOption>[],
    this.buildingOptions = const <JwClassroomOption>[],
  });

  /// 表格里的教室（一行一间）。
  final List<JwClassroom> classrooms;

  /// 查询的周次。
  final int week;

  /// 查询的星期几。
  final int weekday;

  /// 表格里的节次列，按列的顺序排列；用来做「只看某几节」的筛选。
  final List<JwPeriodRange> periodColumns;

  /// 校区下拉选项（页面里读到的；读不到就是空）。
  final List<JwClassroomOption> campusOptions;

  /// 教学楼下拉选项（页面里读到的；读不到就是空）。
  final List<JwClassroomOption> buildingOptions;

  /// 一天里全部有课的节次范围（把 [periodColumns] 合成一段）。
  JwPeriodRange? get wholeDay {
    if (periodColumns.isEmpty) {
      return null;
    }
    return JwPeriodRange(
      start: periodColumns.first.start,
      end: periodColumns.last.end,
    );
  }

  /// [periods] 这段时间空闲的教室。
  List<JwClassroom> freeIn(JwPeriodRange periods) => <JwClassroom>[
    for (final JwClassroom room in classrooms)
      if (!room.isBusyIn(periods)) room,
  ];

  /// 是否一间教室都没读到。
  bool get isEmpty => classrooms.isEmpty;
}

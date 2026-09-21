import 'dart:convert';

import 'package:class_schedule/data/timetable_cache.dart';
import 'package:class_schedule/models/course.dart';
import 'package:class_schedule/models/custom_course.dart';
import 'package:class_schedule/state/schedule_controller.dart' show defaultTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CourseSession session({
  String name = '高等数学',
  String location = 'J3-311',
  String teacher = '王可芸',
  String? credits,
  String? category,
  int weekday = DateTime.monday,
  int startPeriod = 1,
  int endPeriod = 2,
  int startWeek = 4,
  int endWeek = 18,
}) => CourseSession(
  course: Course(
    name: name,
    location: location,
    teacher: teacher,
    credits: credits,
    category: category,
  ),
  weekday: weekday,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  startWeek: startWeek,
  endWeek: endWeek,
);

void main() {
  group('课表快照编解码', () {
    test('编码后能原样还原（含学分/属性与空周）', () {
      final Map<int, List<CourseSession>> weeks = <int, List<CourseSession>>{
        4: <CourseSession>[
          session(
            credits: '3',
            category: '必修',
            weekday: DateTime.friday,
            startPeriod: 9,
            endPeriod: 11,
          ),
          session(name: '大学英语', teacher: ''),
        ],
        5: <CourseSession>[], // 空周（放假）也要记下来，不然每次切过去都联网
      };

      final Map<int, List<CourseSession>> back = TimetableCacheCodec.decode(
        TimetableCacheCodec.encode(weeks, savedAt: DateTime(2026, 9, 21)),
      );

      expect(back.keys, <int>[4, 5]);
      final CourseSession first = back[4]![0];
      expect(first.course.name, '高等数学');
      expect(first.course.location, 'J3-311');
      expect(first.course.teacher, '王可芸');
      expect(first.course.credits, '3');
      expect(first.course.category, '必修');
      expect(first.weekday, DateTime.friday);
      expect(first.startPeriod, 9);
      expect(first.endPeriod, 11);
      expect(first.startWeek, 4);
      expect(first.endWeek, 18);
      expect(back[4]![1].course.name, '大学英语');
      expect(back[5], isEmpty);
    });

    test('版本不认 / 结构不对 → 整份当没存过', () {
      expect(TimetableCacheCodec.decode(null), isEmpty);
      expect(TimetableCacheCodec.decode('不是 JSON'), isEmpty);
      expect(TimetableCacheCodec.decode(<String, Object?>{}), isEmpty);
      expect(
        TimetableCacheCodec.decode(<Object?, Object?>{
          'version': 99,
          'weeks': <String, Object?>{'1': <Object?>[]},
        }),
        isEmpty,
        reason: '旧版本结构不保证能读，宁可重拉',
      );
      expect(
        TimetableCacheCodec.decode(<Object?, Object?>{
          'version': 1,
          'weeks': '不是表',
        }),
        isEmpty,
      );
    });

    test('单条坏数据整条丢掉，好条目照常还原；越界字段就地摆正', () {
      final Map<int, List<CourseSession>> back = TimetableCacheCodec.decode(
        <Object?, Object?>{
          'version': 1,
          'weeks': <Object?, Object?>{
            '4': <Object?>[
              <Object?, Object?>{
                'n': '线性代数',
                'l': 'J1-103',
                'w': 2,
                'sp': 4,
                'ep': 3, // 起止颠倒 → 摆正
                'sw': 18,
                'ew': 4,
              },
              <Object?, Object?>{'n': '   '}, // 连课名都没有 → 丢
              <Object?, Object?>{'n': '缺节次', 'w': 1},
              '垃圾',
              42,
            ],
            '不是数字': <Object?>[], // 键解析不出周次 → 丢
            '0': <Object?>[], // 周次非法 → 丢
          },
        },
      );

      expect(back.keys, <int>[4]);
      expect(back[4], hasLength(1));
      expect(back[4]!.single.course.name, '线性代数');
      expect(back[4]!.single.course.location, 'J1-103');
      expect(back[4]!.single.startPeriod, 3);
      expect(back[4]!.single.endPeriod, 4);
      expect(back[4]!.single.startWeek, 4);
      expect(back[4]!.single.endWeek, 18);
    });
  });

  group('PrefsTimetableCacheStore', () {
    test('写入后能读回，clear 之后读回空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PrefsTimetableCacheStore store = PrefsTimetableCacheStore();

      expect(await store.read(), isEmpty, reason: '没存过返回空表');

      await store.write(<int, List<CourseSession>>{
        defaultTerm.totalWeeks: <CourseSession>[session(name: '最后一周的课')],
      });
      final Map<int, List<CourseSession>> back = await store.read();
      expect(back, hasLength(1));
      expect(back[defaultTerm.totalWeeks]!.single.course.name, '最后一周的课');

      await store.clear();
      expect(await store.read(), isEmpty);
    });

    test('存的就是合法 JSON（方便人工排查与跨版本迁移）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const PrefsTimetableCacheStore store = PrefsTimetableCacheStore();
      await store.write(<int, List<CourseSession>>{
        1: <CourseSession>[session()],
      });

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Object? raw = jsonDecode(prefs.getString(PrefsTimetableCacheStore.storageKey)!);
      expect(raw, isA<Map<dynamic, dynamic>>());
      expect((raw as Map<dynamic, dynamic>)['version'], 1);
      expect((raw['weeks'] as Map<dynamic, dynamic>).keys, <String>['1']);
    });
  });

  group('与自建课程的边界', () {
    test('快照编解码不保留 customId —— 所以快照里只装教务课', () {
      // 快照的写入端只喂 [_remote]（教务课），自建课走 CustomCourseStore 单独落盘。
      // 这里从反面验证：即使把带 customId 的排课误喂进编解码，
      // 出来的也只是普通教务课字段，不会带上「能编辑」的标记。
      final CustomCourse custom = CustomCourse(
        id: 'c1',
        name: '自习',
        weekday: 1,
        startPeriod: 9,
        endPeriod: 10,
        startWeek: 1,
        endWeek: defaultTerm.totalWeeks,
      );
      final CourseSession asSession = custom.toSession();
      expect(asSession.isCustom, isTrue);

      final Map<int, List<CourseSession>> back = TimetableCacheCodec.decode(
        TimetableCacheCodec.encode(<int, List<CourseSession>>{
          1: <CourseSession>[asSession],
        }),
      );
      expect(back[1]!.single.isCustom, isFalse);
      expect(back[1]!.single.course.name, '自习');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/custom_course.dart';
import '../models/week.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';

/// 弹出「添加课程 / 编辑课程」表单。
///
/// [editing] 为 null 是新建，否则改这一条（按 id 覆盖）。保存成功后表单自己关掉弹层；
/// 用户直接划走就是放弃修改 —— 表单里的草稿只活在弹层里，关掉即丢。
Future<void> showCustomCourseForm(
  BuildContext context, {
  required ScheduleController controller,
  CustomCourse? editing,
}) => showFSheet<void>(
  context: context,
  side: FLayout.btt,
  builder: (BuildContext sheetContext) => _CustomCourseForm(
    controller: controller,
    editing: editing,
    onDone: () => Navigator.of(sheetContext).maybePop(),
  ),
);

class _CustomCourseForm extends StatefulWidget {
  const _CustomCourseForm({
    required this.controller,
    required this.onDone,
    this.editing,
  });

  final ScheduleController controller;

  /// 保存成功后调用（关掉弹层）。
  final VoidCallback onDone;

  /// 要编辑的课程；null 表示新建。
  final CustomCourse? editing;

  @override
  State<_CustomCourseForm> createState() => _CustomCourseFormState();
}

class _CustomCourseFormState extends State<_CustomCourseForm> {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final TextEditingController _teacher;
  late int _weekday;
  late int _startPeriod;
  late int _endPeriod;
  late int _startWeek;
  late int _endWeek;
  bool _saving = false;

  /// 已经点过一次「删除」、正在等第二次确认。
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    final CustomCourse? editing = widget.editing;
    final Term term = widget.controller.term;
    _name = TextEditingController(text: editing?.name ?? '');
    _location = TextEditingController(text: editing?.location ?? '');
    _teacher = TextEditingController(text: editing?.teacher ?? '');
    // 新建时默认落在「今天」那一列，比默认周一少点几次。
    _weekday = editing?.weekday ?? DateTime.now().weekday;
    _startPeriod = editing?.startPeriod ?? 1;
    _endPeriod = editing?.endPeriod ?? 2;
    _startWeek = editing?.startWeek ?? CustomCourse.minWeek;
    _endWeek = editing?.endWeek ?? _clamp(term.totalWeeks, 1, CustomCourse.maxWeek);
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _teacher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.editing != null;
    final bool canSave = _name.text.trim().isNotEmpty && !_saving;

    return SafeArea(
      child: ConstrainedBox(
        // 表单比一屏长（三行输入 + 三组选择器），给个高度上限让它在小屏手机上也能滚。
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                editing ? '编辑课程' : '添加课程',
                style: const TextStyle(
                  color: GridColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '自己添加的课不受刷新影响，换账号、退出登录也都留着。',
                style: TextStyle(color: GridColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _name,
                  onChange: (_) => setState(() {}),
                ),
                label: const Text('课程名'),
                hint: '必填，例如 高等数学',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(controller: _location),
                label: const Text('地点'),
                hint: '例如 J1-507，可以留空',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(controller: _teacher),
                label: const Text('教师'),
                hint: '可以留空',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 18),
              _Group(
                children: <Widget>[
                  _StepperRow(
                    label: '星期',
                    value: '周${_weekdayLabel(_weekday)}',
                    onPrevious: _weekday > DateTime.monday
                        ? () => setState(() => _weekday -= 1)
                        : null,
                    onNext: _weekday < DateTime.sunday
                        ? () => setState(() => _weekday += 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _GroupLabel('节次'),
              _Group(
                children: <Widget>[
                  _StepperRow(
                    label: '开始',
                    value: '第 $_startPeriod 节',
                    onPrevious: _startPeriod > CustomCourse.minPeriod
                        ? () => setState(() => _startPeriod -= 1)
                        : null,
                    onNext: _startPeriod < CustomCourse.maxPeriod
                        ? () => setState(() {
                            _startPeriod += 1;
                            // 区间顺过来：起点推到终点之后，终点跟着走。
                            if (_startPeriod > _endPeriod) {
                              _endPeriod = _startPeriod;
                            }
                          })
                        : null,
                  ),
                  _StepperRow(
                    label: '结束',
                    value: '第 $_endPeriod 节',
                    onPrevious: _endPeriod > CustomCourse.minPeriod
                        ? () => setState(() {
                            _endPeriod -= 1;
                            if (_endPeriod < _startPeriod) {
                              _startPeriod = _endPeriod;
                            }
                          })
                        : null,
                    onNext: _endPeriod < CustomCourse.maxPeriod
                        ? () => setState(() => _endPeriod += 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _GroupLabel('周次'),
              _Group(
                children: <Widget>[
                  _StepperRow(
                    label: '从',
                    value: '第 $_startWeek 周',
                    onPrevious: _startWeek > CustomCourse.minWeek
                        ? () => setState(() => _startWeek -= 1)
                        : null,
                    onNext: _startWeek < CustomCourse.maxWeek
                        ? () => setState(() {
                            _startWeek += 1;
                            if (_startWeek > _endWeek) {
                              _endWeek = _startWeek;
                            }
                          })
                        : null,
                  ),
                  _StepperRow(
                    label: '到',
                    value: '第 $_endWeek 周',
                    onPrevious: _endWeek > CustomCourse.minWeek
                        ? () => setState(() {
                            _endWeek -= 1;
                            if (_endWeek < _startWeek) {
                              _startWeek = _endWeek;
                            }
                          })
                        : null,
                    onNext: _endWeek < CustomCourse.maxWeek
                        ? () => setState(() => _endWeek += 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FButton(
                onPress: canSave ? _save : null,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              if (editing) ...<Widget>[
                const SizedBox(height: 10),
                if (_confirmingDelete)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FButton(
                          variant: .outline,
                          onPress: _saving
                              ? null
                              : () => setState(() => _confirmingDelete = false),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FButton(
                          onPress: _saving ? null : _delete,
                          child: const Text('确认删除'),
                        ),
                      ),
                    ],
                  )
                else
                  FButton(
                    variant: .outline,
                    onPress: _saving
                        ? null
                        : () => setState(() => _confirmingDelete = true),
                    child: const Text('删除这门课'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final String name = _name.text.trim();
    if (name.isEmpty) {
      return; // 按钮本来就是禁用的，这里是第二道
    }
    setState(() => _saving = true);

    final ScheduleController controller = widget.controller;
    final CustomCourse? editing = widget.editing;
    final String location = _location.text.trim();
    final String teacher = _teacher.text.trim();
    if (editing == null) {
      await controller.addCustomCourse(
        name: name,
        weekday: _weekday,
        startPeriod: _startPeriod,
        endPeriod: _endPeriod,
        startWeek: _startWeek,
        endWeek: _endWeek,
        location: location,
        teacher: teacher,
      );
    } else {
      await controller.updateCustomCourse(
        editing.copyWith(
          name: name,
          weekday: _weekday,
          startPeriod: _startPeriod,
          endPeriod: _endPeriod,
          startWeek: _startWeek,
          endWeek: _endWeek,
          location: location,
          teacher: teacher,
        ),
      );
    }
    if (!mounted) {
      return;
    }
    widget.onDone();
  }

  Future<void> _delete() async {
    final CustomCourse? editing = widget.editing;
    if (editing == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    await widget.controller.removeCustomCourse(editing.id);
    if (!mounted) {
      return;
    }
    widget.onDone();
  }
}

/// 一行「◀ 值 ▶」选择器；到头的那一侧按钮置灰（不循环，避免误点一路滑到周日）。
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    this.onPrevious,
    this.onNext,
  });

  final String label;
  final String value;

  /// 上一个；null 表示已经到头。
  final VoidCallback? onPrevious;

  /// 下一个；null 表示已经到头。
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
        FButton.icon(
          variant: .outline,
          onPress: onPrevious,
          child: const Icon(FLucideIcons.chevronLeft, size: 16),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GridColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        FButton.icon(
          variant: .outline,
          onPress: onNext,
          child: const Icon(FLucideIcons.chevronRight, size: 16),
        ),
      ],
    ),
  );
}

/// 一组选择器：浅灰底、圆角，把相关的几行框在一起。
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: GridColors.gutter,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(children: children),
    ),
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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

String _weekdayLabel(int weekday) =>
    const <String>['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

int _clamp(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  return value > max ? max : value;
}

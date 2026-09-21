import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../data/jw_client.dart';
import '../state/schedule_controller.dart';
import '../theme/course_palette.dart';
import '../widgets/home_nav.dart';

/// 「选课」页：读取教务系统学生选课中心的轮次列表（**只读**，不提交选课）。
class CourseSelectionScreen extends StatefulWidget {
  const CourseSelectionScreen({
    super.key,
    required this.currentTab,
    required this.onSelectTab,
  });

  /// 当前 Tab（底部导航高亮用）。
  final HomeTab currentTab;

  /// 切换 Tab。
  final ValueChanged<HomeTab> onSelectTab;

  @override
  State<CourseSelectionScreen> createState() => _CourseSelectionScreenState();
}

class _CourseSelectionScreenState extends State<CourseSelectionScreen> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) {
      return;
    }
    _requested = true;
    final ScheduleController controller = ScheduleScope.of(context);
    // 放到帧后执行：loadSelectionRounds 会立刻 notifyListeners()，
    // 在 build/didChangeDependencies 期间通知会触发断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(controller.loadSelectionRounds());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ScheduleController controller = ScheduleScope.of(context);

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: const Text(
          '选课',
          style: TextStyle(
            color: GridColors.textPrimary,
            fontSize: 20,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      footer: homeNavBar(
        current: widget.currentTab,
        onSelect: widget.onSelectTab,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          if (controller.selectionLoading && controller.selectionRounds == null)
            const _LoadingCard()
          else if (controller.selectionError != null)
            _ErrorCard(
              message: controller.selectionError!,
              onRetry: () => controller.loadSelectionRounds(force: true),
            )
          else if (controller.selectionRounds != null &&
              controller.selectionRounds!.isEmpty)
            const _HintCard(
              title: '当前没有开放的选课轮次',
              message:
                  '教务系统学生选课中心返回「未查询到数据」。选课一般在学期初开放，'
                  '开放后这里会列出轮次名称、选课时间；重新进入本页会自动刷新。',
            )
          else ...<Widget>[
            const _SectionLabel('选课轮次'),
            _group(<FTileMixin>[
              for (final JwSelectionRound round
                  in controller.selectionRounds ?? const <JwSelectionRound>[])
                FTile(
                  title: Text(round.name.isEmpty ? '选课轮次' : round.name),
                  subtitle: Text(
                    <String>[
                      if (round.term.isNotEmpty) round.term,
                      if (round.timeRange.isNotEmpty) round.timeRange,
                    ].join(' · '),
                  ),
                  prefix: const Icon(FLucideIcons.bookOpen, size: 18),
                  details: Text(
                    round.roundId == null ? '' : '轮次 ${round.roundId}',
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          const _SectionLabel('说明'),
          _group(<FTileMixin>[
            FTile(
              title: const Text('这里只做查询'),
              subtitle: const Text('本页只读取选课轮次，不会替你提交选课志愿（避免误改你的选课结果）'),
              prefix: const Icon(FLucideIcons.info, size: 18),
            ),
            FTile(
              title: const Text('已选课程'),
              subtitle: const Text('已选上的课会出现在「课表」页'),
              prefix: const Icon(FLucideIcons.layoutGrid, size: 18),
            ),
          ]),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在读取选课中心…',
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => FCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: GridColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: GridColors.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF6E5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF0D9A8)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          const Icon(FLucideIcons.info, size: 16, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF8A6116), fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FButton(variant: .outline, onPress: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

FTileGroup _group(List<FTileMixin> children) => FTileGroup(
  physics: const NeverScrollableScrollPhysics(),
  children: children,
);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
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

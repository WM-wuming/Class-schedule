import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 弹层玻璃面的底色：接近纯白的半透明，模糊后的页面能微微透出来，
/// 是「液态玻璃」质感的基底。
const Color sheetSurfaceColor = Color(0xF2FBFCFE);

/// 底部弹层的公共「底」：一块液态玻璃卡。
///
/// forui 0.26 的 `showFSheet` **不画弹层背景**（`FSheetStyle` 里没有任何
/// surface / decoration 字段，弹层内容直接浮在被压暗的页面上），也不提供
/// Material 祖先（弹层是普通 PopupRoute，不是 MaterialPageRoute）。
/// 所以每个弹层内容都要包上这个组件：
/// - 玻璃面：[BackdropFilter] 把身后的页面糊开，再叠一层半透明白，
///   顶部圆角 + 一圈白色高光描边；
/// - [Material] 祖先，让弹层里的 [IconButton]、[Checkbox]、[InkWell] 等
///   Material 组件能正常工作。
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
      child: Material(
        // 一圈白色高光描边，玻璃卡的「边缘感」就靠它。
        color: sheetSurfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: Color(0x8CFFFFFF)),
        ),
        child: child,
      ),
    ),
  );
}

/// 居中弹窗的公共「底」：四角圆角的液态玻璃卡（[SheetSurface] 的居中版），
/// 同样负责给内容提供 Material 祖先。
class GlassDialogSurface extends StatelessWidget {
  const GlassDialogSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
      child: Material(
        color: sheetSurfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0x8CFFFFFF)),
        ),
        child: child,
      ),
    ),
  );
}

/// 弹出底部弹层的统一入口：在 forui 的 [showFSheet] 上给整个背景界面
/// 加「液态玻璃」效果 —— 弹出时页面先被磨砂模糊，再叠一点玻璃提亮与轻压暗，
/// 出场动画随进度渐变（`barrierFilter` 的第二个参数就是 0→1 的动画值）。
///
/// 新弹层一律走这里，内容记得包 [SheetSurface]。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FLayout side = FLayout.btt,
}) => showFSheet<T>(
  context: context,
  side: side,
  style: FModalSheetStyleDelta.delta(barrierFilter: liquidGlassBarrierFilter),
  builder: builder,
);

/// 弹出居中弹窗的统一入口：与 [showAppSheet] 同一套液态玻璃语言 ——
/// 整个背景先磨砂模糊（随进度渐入）再轻压暗，卡片居中淡入 + 轻微放大。
///
/// 内容记得包 [GlassDialogSurface]。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (BuildContext dialogContext, _, _) => builder(dialogContext),
  transitionBuilder:
      (
        BuildContext dialogContext,
        Animation<double> animation,
        Animation<double> _,
        Widget child,
      ) {
        final double t = Curves.easeOutCubic.transform(animation.value);
        return SizedBox.expand(
          child: BackdropFilter(
            filter: ImageFilter.compose(
              outer: ColorFilter.mode(
                Color.lerp(
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.32),
                  t,
                )!,
                BlendMode.srcOver,
              ),
              inner: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
            ),
            child: Center(
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
);

/// 液态玻璃 barrier：模糊 → 轻压暗（保留 forui 默认的可读性压暗，但更淡）
/// → 玻璃提亮。三段按动画进度同步渐入。
ImageFilter liquidGlassBarrierFilter(BuildContext context, double t) {
  final Color dim = Color.lerp(
    Colors.transparent,
    context.theme.colors.barrier.withValues(alpha: 0.30),
    t,
  )!;
  final Color gloss = Color.lerp(
    Colors.transparent,
    Colors.white.withValues(alpha: 0.14),
    t,
  )!;

  return ImageFilter.compose(
    outer: ColorFilter.mode(gloss, BlendMode.srcOver),
    inner: ImageFilter.compose(
      outer: ColorFilter.mode(dim, BlendMode.srcOver),
      inner: ImageFilter.blur(sigmaX: 22 * t, sigmaY: 22 * t),
    ),
  );
}

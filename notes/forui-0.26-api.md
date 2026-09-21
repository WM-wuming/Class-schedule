# forui 0.26.0 — exact caller-facing API cheat sheet

Read from `C:\Users\wuming\AppData\Local\Pub\Cache\hosted\pub.dev\forui-0.26.0` and `...\forui_lucide-0.26.1` (read-only). Project Dart SDK is 3.13 so dot-shorthands compile, but every default below is written **explicitly**. Decoding: source `const .context()` = `const <ThatStyle>Delta.context()` (generated const factory = "keep inherited style"); `const .spacing(4)` = `const FPortalSpacing.spacing(4)` = `const FPortalSpacing(4)`; `const .managed()` = `const FPopoverControl.managed()`; `icons ??= const FIcons.lucide()` is real.

## 0. Icons — no SVG, no `FSvgAsset`, no asset images
* **`FSvgAsset` does not exist in 0.26.0** (0 grep hits in `lib/`). No SVG/image assets at all.
* Every forui `icon:`-ish parameter is a plain **`Widget`**; forui wraps it in `IconTheme`+`Padding`. So **`Icon(Icons.add)` works**, as does any widget.
* Bundled icons = the **Lucide icon font** via transitive dep `forui_lucide: ^0.26.0`. `lib/assets.dart` is exactly `export 'package:forui_lucide/forui_lucide.dart';` and `forui.dart` exports `assets.dart`, so `import 'package:forui/forui.dart';` alone gives you **`FLucideIcons`** (not `ForuiLucideIcons`; the *font family string* is `'ForuiLucideIcons'`). Exact symbol path: `Icon(FLucideIcons.chevronDown)`.
* You do **not** add `forui_lucide` to `pubspec.yaml` to use `FLucideIcons` (forui re-exports it); you would only need it to `import 'package:forui_lucide/...'` directly. `forui_phosphor` exists upstream but is not a forui dep and is not in this cache.
* Theme icon tokens: `FIcons` has 22 **required** `FIcon` fields (`arrowLeft, calendar, check, chevronDown/Left/Right/Up, chevronsUpDown, circleAlert, clock4, ellipsis, error, eye, eyeClosed, gripHorizontal, gripVertical, loader, loaderCircle, loaderPinwheel, search, userRound, x`) plus `const factory FIcons.lucide()`. `abstract interface class FIcon { const factory FIcon(IconData icon) = _Icon; Widget call(BuildContext context, {String? semanticsLabel}); }` → wrap other sets as `FIcon(Icons.check)`, implement `FIcon` for duotone/SVG sets.

## 1. Theme / colours / localization
**`FThemes` does not exist. `FColorScheme` does not exist. `fromSeed` does not exist.** There is **no seed/accent generator in the package.** The only ready colour sets are `FColors.neutralLight` / `FColors.neutralDark`; seed themes come from the external CLI (`dart run forui theme create`) or create.forui.dev.
```dart
const FTheme({required FThemeData data, required Widget child, TextDirection? textDirection, FPlatformVariant? platform, FAccessibility? accessibility, FThemeMotion motion = const FThemeMotion(), VoidCallback? onEnd, Key? key})
// textDirection defaults to Directionality.maybeOf(context) ?? TextDirection.ltr ; FThemeMotion = 200ms + Curves.linear
const FBasicTheme({required FThemeData data, required Widget child, FPlatformVariant? platform, FAccessibility? accessibility, TextDirection? textDirection, Key? key})  // non-animated
FThemeData({required FColors colors, required bool touch, String? debugLabel, FBreakpoints breakpoints = const FBreakpoints(), FTypography? typography, FIcons? icons, FStyle? style, FHapticFeedback hapticFeedback = const FHapticFeedback(), /* ~50 nullable per-widget *Style/*Styles overrides, e.g. scaffoldStyle cardStyle tileStyles popoverStyle selectStyle tabsStyle toasterStyle, each defaulting to `.inherit(...)` */ Iterable<ThemeExtension<dynamic>> extensions = const []})
// typography null => FTypography.inherit(colors: colors, touch: touch) ; icons null => const FIcons.lucide() ; style null => FStyle.inherit(colors: colors, typography: typography, touch: touch)
```
```dart
// minimal app setup that compiles; overriding the accent:
final FThemeData theme = FThemeData(touch: true, colors: FColors.neutralLight.copyWith(primary: const Color(0xFF0D47A1)));
MaterialApp(
  localizationsDelegates: FLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('zh'), Locale('en')],
  builder: (BuildContext context, Widget? child) => FTheme(data: theme, child: child!),
  home: const FScaffold(child: SizedBox()),
);
```

* **Overriding individual colours:** `FColors.copyWith({Brightness? brightness, SystemUiOverlayStyle? systemOverlayStyle, Color? barrier, background, foreground, primary, primaryForeground, secondary, secondaryForeground, muted, mutedForeground, destructive, destructiveForeground, error, errorForeground, card, border, double? hoverLighten, double? hoverDarken, double? disabledOpacity})`. Constructing `FColors` from scratch needs **17 required** args (`brightness, systemOverlayStyle, barrier, background, foreground, primary, primaryForeground, secondary, secondaryForeground, muted, mutedForeground, destructive, destructiveForeground, error, errorForeground, card, border`) + `hoverLighten = 0.075`, `hoverDarken = 0.05`, `disabledOpacity = 0.5`, `extensions = const []` — so **always prefer `neutralLight/neutralDark.copyWith(...)`**. Helpers: `colors.hover(color)`, `colors.disable(color, [background])`. `FThemeData.toApproximateMaterialTheme()` → Material `ThemeData`.
* **RISK:** `FThemeData.copyWith({...})` has **no `colors`, `typography`, `style` or `touch` parameter** and hard-codes `touch: true`. Change colours by building a **new `FThemeData`**; `copyWith` only takes `debugLabel`, `breakpoints`, the per-widget `*StyleDelta`s and `extensions`.
* **Localization is NOT required for widgets to render** — every call site is `FLocalizations.of(context) ?? FDefaultLocalizations()` (English fallback). It **is** required for non-English strings. Exact delegate list, all `const`: `FLocalizations.localizationsDelegates` == `[FLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate, GlobalWidgetsLocalizations.delegate]`; `FLocalizations.supportedLocales` is a 115-locale const list that includes `Locale('zh')`. `FLocalizations.delegate` alone (what `lib/main.dart` does now) compiles too, but then `Localizations.of<MaterialLocalizations>(context, MaterialLocalizations)` is missing for `FTabs`, `FTextField`/`FOTPField`, `FAutocomplete`.

## 2. `FScaffold` — the parameter is `scaffoldStyle`, **not** `style`
```dart
const FScaffold({required Widget child, FScaffoldStyleDelta scaffoldStyle = const FScaffoldStyleDelta.context(), Widget? header, Widget? sidebar, Widget? footer, bool childPad = true, bool resizeToAvoidBottomInset = true, Key? key})
```
`FScaffoldStyle` fields: `systemOverlayStyle`, `backgroundColor`, `sidebarBackgroundColor`, `childPadding` (default `EdgeInsets.symmetric(horizontal: 12)` = `style.pagePadding.copyWith(top: 0, bottom: 0)`), `footerDecoration` (default 1px top border), `headerDecoration` (default `const BoxDecoration()`).
`FScaffold` paints the sidebar as `ColoredBox(color: style.sidebarBackgroundColor)`, injects `IconTheme(data: theme.style.iconStyle)`, and wraps everything in `FSheets` (so `showFPersistentSheet` works anywhere inside). It does **not** add an `FToaster`.

## 3. `FHeader`, `FHeader.nested`, `FHeaderAction`
```dart
const factory FHeader({Widget title = const SizedBox(), FHeaderStyleDelta style = const FHeaderStyleDelta.context(), List<Widget> suffixes = const [], Key? key})                 // title aligned start
const factory FHeader.nested({Widget title = const SizedBox(), AlignmentGeometry titleAlignment = Alignment.center, FHeaderStyleDelta style = const FHeaderStyleDelta.context(), List<Widget> prefixes = const [], List<Widget> suffixes = const [], Key? key})
const FHeaderAction({required Widget icon, required VoidCallback? onPress, FHeaderActionStyleDelta style = const FHeaderActionStyleDelta.context(), bool selected = false, String? semanticsLabel, String? semanticsTooltip, bool autofocus = false, FocusNode? focusNode, ValueChanged<bool>? onFocusChange, ValueChanged<bool>? onHoverChange, FTappableVariantChangeCallback? onVariantChange, VoidCallback? onLongPress, VoidCallback? onDoubleTap, VoidCallback? onSecondaryPress, VoidCallback? onSecondaryLongPress, Map<ShortcutActivator, Intent>? shortcuts, Map<Type, Action<Intent>>? actions, Key? key})
factory FHeaderAction.back({required VoidCallback? onPress, /* + every param above except icon/selected */})
factory FHeaderAction.x({required VoidCallback? onPress, /* same */})
```
```dart
FHeader.nested(
  title: const Text('Timetable'),
  prefixes: [FHeaderAction.back(onPress: () => Navigator.maybePop(context))],
  suffixes: [FHeaderAction(icon: Icon(FLucideIcons.settings), onPress: openSettings)],
)
```
`onPress` is **required but nullable** (null ⇒ disabled, not hoverable). `FHeaderAction` **must** sit inside an `FHeader`/`FHeader.nested` — it calls `FHeaderData.of(context)`, which asserts.

## 4. `FCard`
```dart
const FCard({FCardStyleDelta style = const FCardStyleDelta.context(), Clip clipBehavior = Clip.none, ValueWidgetBuilder<FCardStyle> builder = FCard.defaultBuilder, Widget? child, Key? key}) // assert(builder != defaultBuilder || child != null); defaultBuilder = (context, style, child) => child!
```
`FCardStyle({required Decoration decoration, required TextStyle titleTextStyle, required TextStyle subtitleTextStyle, EdgeInsetsGeometry padding = const EdgeInsets.all(16)})`. `FCard` has **no** title/subtitle params.
```dart
FCard(child: Padding(padding: const EdgeInsets.all(16), child: Text('Week 3', style: context.theme.cardStyle.titleTextStyle)))
```

## 5. `FTile`, `FTileGroup`, `FItem`, `FItemGroup`, `FItemDivider`
```dart
FTile({required Widget title, FItemVariant variant = FItemVariant.primary /* or .destructive */, FItemStyleDelta style = const FItemStyleDelta.context(), bool? enabled, bool selected = false, String? semanticsLabel, String? semanticsTooltip, bool? semanticsExpanded, bool autofocus = false, FocusNode? focusNode, ValueChanged<bool>? onFocusChange, ValueChanged<bool>? onHoverChange, FTappableVariantChangeCallback? onVariantChange, VoidCallback? onPress, VoidCallback? onLongPress, VoidCallback? onDoubleTap, VoidCallback? onSecondaryPress, VoidCallback? onSecondaryLongPress, Map<ShortcutActivator, Intent>? shortcuts, Map<Type, Action<Intent>>? actions, Widget? prefix, Widget? subtitle, Widget? details, Widget? suffix, Key? key})  // `new`, not const
FTile.raw({required Widget child, /* same minus title/subtitle/details/suffix */ Widget? prefix, Key? key})
FTileGroup({required List<FTileMixin> children, FTileGroupStyleDelta style = const FTileGroupStyleDelta.context(), ScrollController? scrollController, ScrollCacheExtent? scrollCacheExtent, double maxHeight = double.infinity, DragStartBehavior dragStartBehavior = DragStartBehavior.start, ScrollPhysics physics = const ClampingScrollPhysics(), bool? enabled, bool? intrinsicWidth, FItemDivider divider = FItemDivider.indented, String? semanticsLabel, Widget? label, Widget? description, Widget? error, Key? key}) // assert(maxHeight > 0)
FTileGroup.builder({required NullableIndexedWidgetBuilder tileBuilder, int? count, /* same as above */})   // divider default also .indented
FTileGroup.merge({required List<FTileGroupMixin> children, /* same */})                                    // divider default .full
FItem({required Widget title, FItemVariant variant = FItemVariant.primary, FItemStyleDelta style = const FItemStyleDelta.context(), bool? enabled, bool selected = false, /* same callbacks as FTile */ Widget? prefix, Widget? subtitle, Widget? details, Widget? suffix, Key? key})
FItem.raw({required Widget child, Widget? prefix, /* same */})
FItemGroup({required List<FItemMixin> children, /* same shape as FTileGroup */ FItemDivider divider = FItemDivider.none, Key? key})
FItemGroup.group({...})   // == FItemGroup.new ; FItemGroup.merge(...) defaults divider = .full
```
```dart
FTileGroup(label: const Text('Mon'), children: [
  FTile(title: const Text('Math'), subtitle: const Text('Room 301'), onPress: () {}),
  FTile(title: const Text('Physics'), details: const Text('08:00'), onPress: () {}),
])
```
`enum FItemDivider { full, indented, none }`. `children` are typed `FTileMixin`/`FItemMixin`, so only `FTile`/`FSelectTile` (resp. `FItem`/`FSelectItem`) are accepted.

## 6. `FSwitch` — **`value` + `onChange`** (there is no control object)
```dart
const FSwitch({FSwitchStyleDelta style = const FSwitchStyleDelta.context(), bool leadingLabel = false, Widget? label, Widget? description, Widget? error, String? semanticsLabel, bool value = false, ValueChanged<bool>? onChange, bool enabled = true, bool autofocus = false, FocusNode? focusNode, ValueChanged<bool>? onFocusChange, DragStartBehavior dragStartBehavior = DragStartBehavior.start, Key? key})
FSwitch(value: on, label: const Text('24-hour clock'), onChange: (v) => setState(() => on = v))
```
Tapping the `label` toggles too. A non-null `error` puts the switch in the error state.

## 7. `FDivider`, `FBadge`, `FAlert`, progress
```dart
const FDivider({FDividerStyleDelta style = const FDividerStyleDelta.context(), Axis axis = Axis.horizontal, Key? key})
FBadge({required Widget child, FBadgeVariant variant = FBadgeVariant.primary, FBadgeStyleDelta style = const FBadgeStyleDelta.context(), Key? key})   // `new`, not const
const FBadge.raw({required Widget Function(BuildContext context, FBadgeStyle style) builder, FBadgeVariant variant = FBadgeVariant.primary, FBadgeStyleDelta style = const FBadgeStyleDelta.context(), Key? key})
// FBadgeVariant static consts: .primary .secondary .outline .destructive (+ platform variants)
const FAlert({required Widget title, FAlertVariant variant = FAlertVariant.primary, FAlertStyleDelta style = const FAlertStyleDelta.context(), bool liveRegion = true, Clip clipBehavior = Clip.none, Widget? icon, Widget? subtitle, Key? key})  // FAlertVariant consts: .primary .destructive; icon defaults to theme.icons.circleAlert
const FProgress({FProgressStyleDelta style = const FProgressStyleDelta.context(), String? semanticsLabel, Key? key})                                  // indeterminate linear
const FDeterminateProgress({required double value /* 0.0..1.0, asserted */, FDeterminateProgressStyleDelta style = const FDeterminateProgressStyleDelta.context(), String? semanticsLabel, Key? key})
// FCircularProgress also exists (indeterminate, circular)
```
`FAlertVariant` / `FBadgeVariant` are **classes with static consts, not Dart `enum`s** — write `FAlertVariant.destructive` (or dot-shorthand `.destructive`).

## 8. `FPopover`, `FPopoverControl`, `FPopoverMenu`
```dart
enum FPopoverHideRegion { anywhere, excludeChild, none }
const FPopover({required Widget Function(BuildContext context, FPopoverController controller) popoverBuilder /* 2 ARGS ONLY */,
  FPopoverControl control = const FPopoverControl.managed(), FPopoverStyleDelta style = const FPopoverStyleDelta.context(),
  FPortalConstraints constraints = const FPortalConstraints(), FPortalSpacing spacing = const FPortalSpacing.spacing(4),
  FPortalOverflow overflow = FPortalOverflow.flip, bool useViewPadding = true, bool useViewInsets = true,
  OverlayChildLocation overlayLocation = OverlayChildLocation.nearestOverlay, Offset offset = Offset.zero,
  Object? groupId /* assert: groupId != null requires hideRegion == .excludeChild */,
  FPopoverHideRegion hideRegion = FPopoverHideRegion.excludeChild, VoidCallback? onTapHide, bool? autofocus,
  FocusScopeNode? focusNode, ValueChanged<bool>? onFocusChange,
  TraversalEdgeBehavior? traversalEdgeBehavior /* assert: not with focusNode */, bool traversalGrouped = true,
  String? barrierSemanticsLabel, bool barrierSemanticsDismissible = true, bool cutout = true,
  void Function(Path path, Rect bounds) cutoutBuilder = FModalBarrier.defaultCutoutBuilder, String? semanticsLabel,
  Map<ShortcutActivator, VoidCallback>? shortcuts, ValueWidgetBuilder<FPopoverController> builder = FPopover.defaultBuilder,
  Widget? child, AlignmentGeometry? popoverAnchor, AlignmentGeometry? childAnchor, Clip popoverClipBehavior = Clip.none, Key? key})
// assert(builder != defaultBuilder || child != null)
const factory FPopoverControl.managed({FPopoverController? controller, bool? initial, ValueChanged<bool>? onChange})
const factory FPopoverControl.lifted({required bool shown, required ValueChanged<bool> onChange})
// FPopoverController({required TickerProvider vsync, bool shown = false}); .toggle()/.show()/.hide({bool animated = true})
```
**Trap:** `FPopover.defaultPopoverBuilder` is a **4-arg** static `(context, Object, FPopoverController, Widget)` and does **not** match `FPopover.popoverBuilder`. That 4-arg shape is `FSelectPopoverBuilder<T>` / `FAutocompletePopoverBuilder`.
```dart
FPopoverMenu({FPopoverControl control = const FPopoverControl.managed(), ScrollController? scrollController,
  FPopoverMenuStyleDelta style = const FPopoverMenuStyleDelta.context(), ScrollCacheExtent? scrollCacheExtent,
  double maxHeight = double.infinity, bool intrinsicWidth = true, DragStartBehavior dragStartBehavior = DragStartBehavior.start,
  ScrollPhysics physics = const ClampingScrollPhysics(), FItemDivider divider = FItemDivider.full,
  AlignmentGeometry menuAnchor = Alignment.topCenter, AlignmentGeometry childAnchor = Alignment.bottomCenter,
  FPortalSpacing spacing = const FPortalSpacing.spacing(4), FPortalOverflow overflow = FPortalOverflow.flip,
  bool useViewPadding = true, bool useViewInsets = true, OverlayChildLocation overlayLocation = OverlayChildLocation.nearestOverlay,
  Offset offset = Offset.zero, Object? groupId, FPopoverHideRegion hideRegion = FPopoverHideRegion.excludeChild,
  VoidCallback? onTapHide, String? barrierSemanticsLabel, bool barrierSemanticsDismissible = true, bool cutout = true,
  void Function(Path, Rect) cutoutBuilder = FModalBarrier.defaultCutoutBuilder, String? semanticsLabel, bool? autofocus,
  FocusScopeNode? focusNode, ValueChanged<bool>? onFocusChange, TraversalEdgeBehavior? traversalEdgeBehavior, bool? faded,
  List<FItemGroupMixin> Function(BuildContext, FPopoverController, List<FItemGroupMixin>? menu) menuBuilder = FPopoverMenu.defaultItemBuilder,
  List<FItemGroupMixin>? menu, ValueWidgetBuilder<FPopoverController> builder = FPopover.defaultBuilder, Widget? child, Key? key})
// assert(builder != defaultBuilder || child != null); assert(menuBuilder != defaultItemBuilder || menu != null)
FPopoverMenu.tiles({...})   // same params but List<FTileGroupMixin> menu / FPopoverMenu.defaultTileBuilder
```
There is **no `FPopoverMenuEntry`**. Menu content is `List<FItemGroupMixin>` (or `List<FTileGroupMixin>`), i.e. wrap `FItem`s in `FItem.group(...)`/`FItemGroup(...)`. Tapping an item does **not** close the menu by itself — call `controller.hide()`. (`FSubmenuTile` / `FSubmenuTrigger` exist for submenus.)
```dart
// tap-a-pill -> scrollable option list that closes when one is tapped
FPopoverMenu(
  maxHeight: 220,                                   // finite => scrollable
  menuBuilder: (context, controller, _) => [FItemGroup.group(children: [
    for (final o in options) FItem(title: Text(o), onPress: () { controller.hide(); setState(() => selected = o); }),
  ])],
  builder: (context, controller, _) => FButton(onPress: controller.toggle, child: Text(selected)),
  child: const SizedBox.shrink(),
)
```

## 9. Sheets + sidebar
**The modal-sheet helper is `showFSheet`, not `showFModalSheet`.**
```dart
Future<T?> showFSheet<T>({required BuildContext context, required WidgetBuilder builder, required FLayout side, bool useRootNavigator = false, FModalSheetStyleDelta style = const FModalSheetStyleDelta.context(), double? mainAxisMaxRatio = 9 / 16, bool useSafeArea = false, bool resizeToAvoidBottomInset = true, String? barrierLabel, bool barrierDismissible = true, BoxConstraints constraints = const BoxConstraints(), bool draggable = true, RouteSettings? routeSettings, AnimationController? transitionAnimationController, Offset? anchorPoint, VoidCallback? onClosing})
// FLayout is a class of static consts: FLayout.ttb .btt .ltr .rtl (not an enum)
@useResult FPersistentSheetController showFPersistentSheet({required BuildContext context, required FLayout side, required Widget Function(BuildContext context, FPersistentSheetController controller) builder, FPersistentSheetStyleDelta style = const FPersistentSheetStyleDelta.context(), double? mainAxisMaxRatio = 9 / 16, BoxConstraints constraints = const BoxConstraints(), bool draggable = true, Offset? anchorPoint, bool useSafeArea = false, bool resizeToAvoidBottomInset = true, bool keepAliveOffstage = false, VoidCallback? onClosing, Key? key})
const FSheets({required Widget child, Key? key})   // no FSheets.of static exists
```
```dart
showFSheet<void>(context: context, side: FLayout.btt, builder: (context) => FScaffold(child: FTileGroup(children: [...])));
// persistent: requires an FSheets/FScaffold ancestor; controller has .show() .toggle() .hide() -> TickerFuture, .status ; dispose() it yourself
```
**`FSidebar` is a static layout column, not a drawer** — no open/close, no scrim. `FSidebar({required List<Widget> children, Widget? header, Widget? footer, FSidebarStyleDelta style = const FSidebarStyleDelta.context(), bool autofocus = false, FocusScopeNode? focusNode, TraversalEdgeBehavior? traversalEdgeBehavior, Key? key})`, `FSidebar.builder({required itemBuilder, required itemCount, ...})`, `const FSidebar.raw({required Widget child, ...})`. Width = `FSidebarStyle.constraints = const BoxConstraints.tightFor(width: 256)`. **For a mobile drawer-ish panel use `showFSheet(side: FLayout.ltr)` (modal + barrier) or `FScaffold.sidebar`.**

## 10. Select family — single vs multi
| Widget | value type | single/multi | item type |
|---|---|---|---|
| `FSelect<T>` | `T` | **single** | `Map<String,T> items` (or `.rich` with `List<FSelectItemMixin>`) |
| `FMultiSelect<T>` | `Set<T>` | **multi** | `Map<String,T>` / `.rich` with `FSelectItem<T>`, `FSelectSection<T>` |
| `FSelectGroup<T>` | `Set<T>` | multi (`Set`) | `required List<FSelectGroupItemMixin<T>> children` via `FSelectGroupItemMixin.checkbox<T>(value: …)` / `.radio<T>(value: …)` |
| `FSelectTileGroup<T>` | `Set<T>` | multi | `List<FSelectTile<T>>` (`.tile(...)`), also `.builder({required FSelectTile<T>? Function(BuildContext,int) tileBuilder})` |
| `FSelectMenuTile<T>` | `Set<T>` | multi | `List<FSelectTile<T>> menu`, also `.builder`, `.fromMap` |

`FSelectItem<T>({required Widget title, required T value, FItemStyleDelta style = const FItemStyleDelta.context(), bool? enabled, Widget? prefix, Widget? subtitle, Widget Function(BuildContext context, bool selected) suffixBuilder = <check icon when selected>, Key? key})`; also `.raw<T>`, and on `FSelectItemMixin`: `.item<T>(...)`, `.raw<T>(...)`, `.section<T>({required Widget label, required Map<String,T> items, ...})`, `.richSection<T>({required Widget label, required List<FSelectItem<T>> children, ...})`. `FSelectSection<T>({required Widget label, required Map<String,T> items, ...})` / `.rich({required label, required List<FSelectItem<T>> children, ...})`.
```dart
FSelect<String>({required Map<String, T> items /* {displayText: value} */, FSelectControl<T>? control, FPopoverControl popoverControl = const FPopoverControl.managed(), FTextFieldSizeVariant size = FTextFieldSizeVariant.md, FSelectStyleDelta style = const FSelectStyleDelta.context(), bool autofocus = false, FocusNode? focusNode, Widget? label, Widget? description, bool enabled = true, FormFieldSetter<T>? onSaved, VoidCallback? onReset, AutovalidateMode autovalidateMode = AutovalidateMode.onUnfocus, String? forceErrorText, FormFieldValidator<T> validator, Widget Function(BuildContext, String) errorBuilder, String? hint, TextAlign textAlign = TextAlign.start, bool expands = false, bool clearable = false, FSelectPopoverBuilder<T> popoverBuilder = FPopover.defaultPopoverBuilder, FPortalConstraints contentConstraints = const FAutoWidthPortalConstraints(maxHeight: 300), FPortalSpacing contentSpacing = const FPortalSpacing.spacing(4), bool autoHide = true, FItemDivider contentDivider = FItemDivider.none, ScrollController? contentScrollController, ScrollPhysics contentPhysics = const ClampingScrollPhysics(), Key? formFieldKey, Key? key, /* + contentAnchor = Alignment.topStart, fieldAnchor = Alignment.bottomStart, contentOffset, contentHideRegion, contentCutout, retainFocus … */})
const factory FSelect.rich({required String Function(T value) format, required List<FSelectItemMixin> children, ...})
// FSelectControl.managed({FSelectController<T>? controller, T? initial, bool toggleable, ValueChanged<T?>? onChange}) ; FSelectControl.lifted({required T? value, required ValueChanged<T?> onChange})
```
```dart
// minimal single-select dropdown of strings
FSelect<String>(items: const {'Monday': 'mon', 'Tuesday': 'tue', 'Wednesday': 'wed'}, label: const Text('Day'), onSaved: (value) {}, onReset: () {})
```
Always write the type argument (`FSelect<String>`), else "No FSelect<$T> found in context" asserts.

## 11. `FTabs` / `FTabEntry` / `FAutocomplete`
```dart
class FTabEntry { final Widget label; final Widget child; const FTabEntry({required this.label, required this.child}); const factory FTabEntry.entry({required Widget label, required Widget child}); }
// There is NO public FTab widget — tab chrome comes from FTabsStyle internally.
FTabs({required List<FTabEntry> children /* assert non-empty */, FTabControl control = const FTabControl.managed(), bool scrollable = false, ScrollPhysics? physics, ScrollPhysics contentPhysics = const BouncingScrollPhysics(), FTabsStyleDelta style = const FTabsStyleDelta.context(), ValueChanged<int>? onPress, MouseCursor mouseCursor = MouseCursor.defer, bool expands = false, Key? key})  // `new`, not const
// FTabControl.managed({FTabController? controller, int? initial, FTabMotion? motion, ValueChanged<int>? onChange})
// FTabControl.lifted({required int index, required ValueChanged<int> onChange, FTabMotion motion /* defaulted by the target ctor to const FTabMotion() */})
```
```dart
FTabs(children: const [FTabEntry.entry(label: Text('Mon'), child: Text('Monday')), FTabEntry.entry(label: Text('Tue'), child: Text('Tuesday'))])
```
`FAutocomplete<T>` — text field + suggestion popover. `FAutocomplete({required Map<String,T> items, String Function(T)? format, T? Function(String?)? parse, FAutocompleteControl control = const .managed(), FPopoverControl popoverControl = const .managed(), FTextFieldSizeVariant size = .md, FAutocompleteStyleDelta style = const .context(), Widget? label, String? hint, Object groupId = EditableText, bool enabled = true, int? maxLines = 1, FutureOr<Iterable<T>> Function(String query)? filter, bool autoHide = true, bool rightArrowToComplete = false, ValueChanged<T>? onItemPress, AutovalidateMode autovalidateMode = .disabled, ...})`; also `.builder(...)`, `.text(...)`; `FAutocompleteControl.managed/.lifted` mirror `FSelectControl`.

## 12. `FToaster` / `FToast` / `showFToast`
```dart
const FToaster({required Widget child, FToasterStyleDelta style = const FToasterStyleDelta.context(), Key? key})   // FToaster.of(context) -> FToasterState
FToasterEntry showFToast({required BuildContext context, required Widget title, FToastVariant variant = FToastVariant.primary, FToastStyleDelta style = const FToastStyleDelta.context(), Widget? icon, Widget? description, Widget Function(BuildContext context, FToasterEntry entry)? suffixBuilder, FToastAlignment? alignment, List<AxisDirection>? swipeToDismiss, double dismissThreshold = 0.5, Duration? duration = const Duration(seconds: 5) /* null disables auto-dismiss */, VoidCallback? onDismiss})
// also: FToasterEntry showRawFToast({required BuildContext context, required Widget Function(BuildContext, FToasterEntry) builder, ...})
// FToastAlignment is a class of static consts: .topStart .topCenter .topEnd .topLeft .topRight .bottomStart .bottomCenter .bottomEnd .bottomLeft .bottomRight
```
```dart
// FToaster must wrap the app (inside FTheme); showFToast throws without an FToaster ancestor
MaterialApp(builder: (context, child) => FTheme(data: theme, child: FToaster(child: child!)), home: const HomePage());
showFToast(context: context, title: const Text('Saved'), description: const Text('Timetable updated'));
```

## 13. "Must do" setup / helpers
* `WidgetsFlutterBinding.ensureInitialized()` is **not** required by forui (0 hits in `lib/`).
* **`FTheme` must wrap the app.** Without it `context.theme` silently returns `FTheme.neutral.light.touch` — no exception. Put `FTheme` in `MaterialApp.builder` and read `context.theme` only in **descendants** (`src/theme/theme.dart` documents the "always returns neutral" troubleshooting).
* Minimum required `FThemeData` fields: `colors` (`FColors`) and `touch` (`bool`); `typography`, `icons`, `style`, `hapticFeedback`, `breakpoints` and every per-widget style derive from `colors`.
* Fonts: forui bundles **Inter** (`forui/pubspec.yaml` → `flutter.fonts: family: Inter`, `assets/fonts/inter/Inter.ttf`); `forui_lucide` bundles `ForuiLucideIcons` (`assets/lucide.ttf`). Both ship with the packages — **no `fonts:` entry is needed in this app's `pubspec.yaml`**.
* `FAdaptiveScope({required Widget child, FPlatformVariant? platform, Key? key})` + `FAdaptiveScope.of(context)`; `FTheme`/`FBasicTheme` already insert one, so just use `context.platformVariant`. Direction/theme capture for routes: `FTheme.capture({required BuildContext from, required BuildContext to}) -> FCapturedTheme` (`showFSheet` does this for you).
* A11y / text scaling: `FAccessibilityScope({required Widget child, FAccessibility? data, Key? key})`; `FAccessibility({required bool accessibleNavigation, required FAccessibilityMotion motion, required bool focusHighlight})`; read via `context.accessibility` or `FAccessibilityScope.accessibleNavigationOf/motionOf/focusHighlightOf(context)`. `FTypography.inherit({required FColors colors, required bool touch})`, `FTypography.scale({double sizeScalar = 1})`.

## Commands for this project (`D:\xm\Class-schedule`)
forui 0.26.0 requires Flutter **3.47.0+**; SDK here is `D:\pata\flutter\bin\flutter.bat`, channel `stable`, rev `6a19cca56475dbfba1478ee68d7bd0c2ef891da1` (`.metadata`). Standard commands:
```
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run -d chrome
```
Caveat: 这些签名来自源码阅读。实际用到的部分已在本仓库验证：`dart analyze lib test` 无问题，
`flutter test` 12 个测试全绿（含网格几何与交互）。注意 `dart:ui`/`dart analyze` 需要能启动分析服务进程，
在受限沙箱里会被拒绝访问；`flutter test` 可正常使用。

## Uncertain / not verified
* 本文件中的签名均由源码阅读得到，其中**本应用实际用到的部分已经过编译器与运行期验证**（见上一条）；
  未被用到的部分（`FTabs`、`FSelect`、`FAutocomplete` 等）保持"源码已读、未编译验证"。
* `material_ui` / `cupertino_ui`: forui 内部 import 的是 `package:material_ui/material_ui.dart`，
  而 SDK 仍然提供 `package:flutter/material.dart`（本应用用的是后者）。调用方该 import 哪个，仅从 forui 无法确定。
* Not fully enumerated: `FPortalConstraints`, `FPortalOverflow`, `FLayout`, `OverlayChildLocation`, `FPlatformVariant`, `FHapticFeedback`, `FBreakpoints`, `FBorderRadius`, `FSizes`, `FTappableStyle` members (only those used above were read).
* `FSelectMenuTile`, `FSelectTileGroup`, `FMultiSelect` (and `FAutocomplete`) are summarised — their item/control types were verified, but not every one of their ~50–100 optional params was read individually.
* `FLucideIcons`' 6000+ icon names were not enumerated; only the class, font family `ForuiLucideIcons` and the path `Icon(FLucideIcons.<camelCaseName>)` were verified.
* `FSidebarStyle`'s decoration/border defaults come from `FSidebarStyle.inherit(...)`; only `constraints` (width 256) and the three paddings were read.
* Nothing outside `notes/forui-0.26-api.md` was created or modified.

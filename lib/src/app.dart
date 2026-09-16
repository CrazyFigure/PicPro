import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 设计令牌集中在此，避免颜色、圆角、动效时长散落在各处。
///
/// 只定义亮色主题：这是工具类应用，长时间面对图片，亮色底更利于判断颜色，
/// 深色主题反而会干扰对图片明暗的判断。
class AppTokens {
  AppTokens._();

  // ---------------------------------------------------------------- 颜色

  /// 主色：用于强调与主要操作
  static const Color primary = Color(0xFF2F6FEB);

  /// 主色悬停态：比主色略亮，鼠标移上去有明确的「可点」反馈
  static const Color primaryHover = Color(0xFF3D7CF4);

  /// 主色按下态：明显压暗，点击瞬间有下沉感
  static const Color primaryPressed = Color(0xFF2258C4);

  /// 主色的浅色底，用于选中项背景
  static const Color primarySoft = Color(0x142F6FEB);

  /// 页面底色（最底层）
  static const Color canvas = Color(0xFFF2F4F7);

  /// 卡片/面板底色
  static const Color surface = Color(0xFFFFFFFF);

  /// 次级面板底色（如分组容器、输入框内底），比 surface 略暗
  static const Color surfaceAlt = Color(0xFFF7F8FA);

  /// 交互元素悬停时的底色
  static const Color hoverWash = Color(0xFFEEF1F6);

  /// 交互元素按下时的底色
  static const Color pressWash = Color(0xFFE3E8F0);

  /// 分隔线与常规边框
  static const Color border = Color(0xFFE2E5EA);

  /// 强边框：悬停/聚焦时的描边
  static const Color borderStrong = Color(0xFFC8D0DA);

  /// 主要文字
  static const Color textPrimary = Color(0xFF1B1F24);

  /// 次要文字
  static const Color textSecondary = Color(0xFF5A6472);

  /// 更弱的辅助文字（说明、单位）
  static const Color textTertiary = Color(0xFF8A94A2);

  /// 成功
  static const Color success = Color(0xFF1A7F37);

  /// 失败
  static const Color danger = Color(0xFFCF222E);

  /// 警告
  static const Color warning = Color(0xFF9A6700);

  // ---------------------------------------------------------------- 形状

  static const double radius = 12;
  static const double radiusSmall = 8;
  static const double radiusPill = 999;

  /// 统一动效时长，保证全应用交互反馈节奏一致
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);

  /// 卡片投影：非常克制，只用来表达层级，不制造浮夸的立体感
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A101828),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  /// 主按钮悬停/按下时的投影
  static const List<BoxShadow> primaryShadow = [
    BoxShadow(
      color: Color(0x332F6FEB),
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];
}

/// 中文优先的字体候选表。
///
/// 不能只依赖框架默认字体：Windows 默认会落到 Segoe UI，中文字形由系统回退
/// 接管，字重与基线在不同机器上并不一致；Web 端更是直接取决于用户系统。
/// 因此给出显式的首选字体 + 一组中日韩兜底，让三端观感尽量接近。
const List<String> _cjkFallback = <String>[
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Hiragino Sans GB',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'Segoe UI',
  'Roboto',
];

/// 按平台挑选首选字体族。
///
/// Android 与 Web 返回 null：Android 系统默认字体本就完整覆盖中文，
/// 强行指定一个可能不存在的字体族反而会触发额外的字体回退；
/// Web 端由浏览器/CSS 字体栈决定，交由引擎处理更合适。
String? _primaryFontFamily() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return 'Microsoft YaHei UI';
    case TargetPlatform.macOS:
    case TargetPlatform.iOS:
      return 'PingFang SC';
    default:
      return null;
  }
}

/// 应用主题。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.primary,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppTokens.surface,
    primary: AppTokens.primary,
    onPrimary: Colors.white,
    surfaceContainerHighest: AppTokens.surfaceAlt,
    outlineVariant: AppTokens.border,
  );

  final fontFamily = _primaryFontFamily();
  final radius = BorderRadius.circular(AppTokens.radiusSmall);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.canvas,
    dividerColor: AppTokens.border,
    fontFamily: fontFamily,
    fontFamilyFallback: _cjkFallback,
    // 桌面端保持紧凑、移动端自动放宽，避免两端手感割裂
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
        letterSpacing: 0.1,
      ),
      titleMedium: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
        letterSpacing: 0.1,
      ),
      bodyLarge: TextStyle(fontSize: 14, color: AppTokens.textPrimary, height: 1.45),
      bodyMedium: TextStyle(fontSize: 13, color: AppTokens.textPrimary, height: 1.45),
      bodySmall: TextStyle(fontSize: 11.5, color: AppTokens.textSecondary, height: 1.45),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    // ---------------- 按钮：显式区分 Hover / Pressed ----------------
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppTokens.primary.withValues(alpha: 0.34);
          }
          if (states.contains(WidgetState.pressed)) return AppTokens.primaryPressed;
          if (states.contains(WidgetState.hovered)) return AppTokens.primaryHover;
          return AppTokens.primary;
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        // 悬停轻微上浮、按下收起，形成「按得下去」的物理感
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return 0;
          if (states.contains(WidgetState.pressed)) return 0;
          if (states.contains(WidgetState.hovered)) return 4;
          return 1;
        }),
        shadowColor: const WidgetStatePropertyAll(Color(0x552F6FEB)),
        animationDuration: AppTokens.fast,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const BorderSide(color: AppTokens.border);
          }
          if (states.contains(WidgetState.pressed)) {
            return const BorderSide(color: AppTokens.primaryPressed, width: 1.4);
          }
          if (states.contains(WidgetState.hovered)) {
            return const BorderSide(color: AppTokens.primary, width: 1.4);
          }
          return const BorderSide(color: AppTokens.border);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppTokens.textTertiary;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return AppTokens.primary;
          }
          return AppTokens.textPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return AppTokens.pressWash;
          if (states.contains(WidgetState.hovered)) return AppTokens.hoverWash;
          return Colors.transparent;
        }),
        animationDuration: AppTokens.fast,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return AppTokens.pressWash;
          if (states.contains(WidgetState.hovered)) return AppTokens.hoverWash;
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppTokens.textTertiary;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return AppTokens.primary;
          }
          return AppTokens.textSecondary;
        }),
        animationDuration: AppTokens.fast,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppTokens.textTertiary;
          if (states.contains(WidgetState.pressed)) return AppTokens.primaryPressed;
          if (states.contains(WidgetState.hovered)) return AppTokens.primary;
          return AppTokens.textSecondary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) return AppTokens.pressWash;
          if (states.contains(WidgetState.hovered)) return AppTokens.hoverWash;
          return Colors.transparent;
        }),
      ),
    ),
    // ---------------- 输入控件 ----------------
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: AppTokens.primary,
      inactiveTrackColor: AppTokens.border,
      // 悬停/拖动时滑轨与滑块一起变亮，明确「正在操作这个参数」
      thumbColor: AppTokens.primary,
      overlayColor: AppTokens.primary.withValues(alpha: 0.14),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
      valueIndicatorColor: AppTokens.textPrimary,
      valueIndicatorTextStyle: const TextStyle(fontSize: 12, color: Colors.white),
      showValueIndicator: ShowValueIndicator.onlyForDiscrete,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.white;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppTokens.border;
        }
        if (states.contains(WidgetState.selected)) {
          if (states.contains(WidgetState.pressed)) return AppTokens.primaryPressed;
          if (states.contains(WidgetState.hovered)) return AppTokens.primaryHover;
          return AppTokens.primary;
        }
        if (states.contains(WidgetState.hovered)) return AppTokens.borderStrong;
        return AppTokens.border;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          if (states.contains(WidgetState.hovered)) return AppTokens.primaryHover;
          return AppTokens.primary;
        }
        return Colors.transparent;
      }),
      side: const BorderSide(color: AppTokens.borderStrong, width: 1.4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppTokens.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      hintStyle: const TextStyle(fontSize: 12.5, color: AppTokens.textTertiary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        borderSide: const BorderSide(color: AppTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        borderSide: const BorderSide(color: AppTokens.border),
      ),
      hoverColor: AppTokens.hoverWash.withValues(alpha: 0.5),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: AppTokens.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          borderSide: const BorderSide(color: AppTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        side: const BorderSide(color: AppTokens.border),
      ),
      textStyle: const TextStyle(fontSize: 13, color: AppTokens.textPrimary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppTokens.textPrimary,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    dividerTheme: const DividerThemeData(
      color: AppTokens.border,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppTokens.primary,
      linearTrackColor: AppTokens.border,
      circularTrackColor: AppTokens.border,
      linearMinHeight: 5,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) return AppTokens.borderStrong;
        return AppTokens.border;
      }),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppTokens.textPrimary,
      contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusSmall)),
    ),
  );
}

/// 「次级填充按钮」（`FilledButton.tonal`）的样式。
///
/// ThemeData 没有 `tonalButtonTheme` 这一项，无法统一在主题里配置，
/// 只能由调用方显式传入。集中在这里定义，避免各处各写一套颜色，
/// 也保证次级按钮的悬停/按下反馈与主按钮同一套语言。
ButtonStyle appTonalButtonStyle() => ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusSmall)),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppTokens.surfaceAlt.withValues(alpha: 0.6);
        }
        if (states.contains(WidgetState.pressed)) return AppTokens.pressWash;
        if (states.contains(WidgetState.hovered)) return AppTokens.hoverWash;
        return AppTokens.surfaceAlt;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return AppTokens.textTertiary;
        return AppTokens.textPrimary;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
          return const BorderSide(color: AppTokens.borderStrong);
        }
        return const BorderSide(color: AppTokens.border);
      }),
      animationDuration: AppTokens.fast,
    );

/// 面板容器：统一圆角、边框、投影与内边距。
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.elevated = false});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// 是否带投影。列表/主工作区用投影表达层级，配置面板保持扁平。
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
        boxShadow: elevated ? AppTokens.cardShadow : null,
      ),
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }
}

/// 分组容器：用较小的内边距与浅底把一组相关控件聚在一起。
///
/// 相比「一条左侧竖线」，浅色底在窄面板里更容易被识别为同一组，
/// 且不会与滑杆的轨道产生视觉竞争。
class FieldGroup extends StatelessWidget {
  const FieldGroup({super.key, required this.children, this.enabled = true});

  final List<Widget> children;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppTokens.fast,
      opacity: enabled ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: AppTokens.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          border: Border.all(color: AppTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// 一行「开关 + 名称」控件。
///
/// 名称用普通正文而非小标题；悬停整行变底、按下再深一层，
/// 让「整行可点」这件事在鼠标移到之前就能被看出来。
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PressableBuilder(
      onTap: () => onChanged(!value),
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: AppTokens.fast,
        decoration: BoxDecoration(
          color: pressed
              ? AppTokens.pressWash
              : hovered
                  ? AppTokens.hoverWash
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IgnorePointer(
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行「标签 + 值」控件。
class LabeledRow extends StatelessWidget {
  const LabeledRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = 68,
  });

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 只关心悬停状态的构建器。
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

/// 同时给出悬停与按下两种状态，供自绘按钮、卡片与列表项使用。
///
/// Flutter 的 InkWell 只提供水波纹，工具类界面更需要「整块变底 + 按下压暗」
/// 这种更明确的反馈，因此统一在这里收口，避免各处重复写状态机。
class PressableBuilder extends StatefulWidget {
  const PressableBuilder({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  @override
  State<PressableBuilder> createState() => _PressableBuilderState();
}

class _PressableBuilderState extends State<PressableBuilder> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool v) {
    if (_hovered != v) setState(() => _hovered = v);
  }

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? widget.cursor : MouseCursor.defer,
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled
          ? (_) {
              _setHovered(false);
              _setPressed(false);
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onTap,
        child: widget.builder(
          context,
          enabled && _hovered,
          enabled && _pressed,
        ),
      ),
    );
  }
}

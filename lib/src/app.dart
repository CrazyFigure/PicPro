import 'package:flutter/material.dart';

/// 设计令牌集中在此，避免颜色与圆角散落在各处。
class AppTokens {
  AppTokens._();

  /// 主色：用于强调与主要操作
  static const Color primary = Color(0xFF2F6FEB);

  /// 主色按下态
  static const Color primaryActive = Color(0xFF2557C0);

  /// 页面底色
  static const Color canvas = Color(0xFFF5F6F8);

  /// 卡片/面板底色
  static const Color surface = Color(0xFFFFFFFF);

  /// 分隔线与边框
  static const Color border = Color(0xFFE2E5EA);

  /// 主要文字
  static const Color textPrimary = Color(0xFF1F2328);

  /// 次要文字
  static const Color textSecondary = Color(0xFF646C76);

  /// 成功
  static const Color success = Color(0xFF1A7F37);

  /// 失败
  static const Color danger = Color(0xFFCF222E);

  /// 警告
  static const Color warning = Color(0xFF9A6700);

  static const double radius = 10;
  static const double radiusSmall = 7;
}

/// 应用主题。
///
/// 只定义亮色主题：这是工具类应用，长时间面对图片，亮色底更利于判断颜色，
/// 深色主题反而会干扰对图片明暗的判断。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.primary,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppTokens.surface,
    primary: AppTokens.primary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.canvas,
    dividerColor: AppTokens.border,
    fontFamily: null, // 使用系统默认字体，保证中文字形正常
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: AppTokens.textPrimary),
      bodySmall: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
        borderSide: const BorderSide(color: AppTokens.primary, width: 1.4),
      ),
    ),
  );
}

/// 面板容器：统一圆角、边框与内边距。
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.border),
      ),
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }
}

/// 分组容器：用一条左侧竖线表示层级，替代小标题文字，减少视觉噪音。
class FieldGroup extends StatelessWidget {
  const FieldGroup({super.key, required this.children, this.enabled = true});

  final List<Widget> children;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 一行「开关 + 名称」控件。
///
/// 名称用普通正文而非小标题，符合精简标题的要求；
/// 悬停整行即变底色，给出可点反馈。
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
    return _HoverBuilder(
      builder: (hovered) => InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        onTap: () => onChanged(!value),
        child: Container(
          color: hovered ? AppTokens.canvas : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    if (detail != null)
                      Text(detail!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行「标签 + 值」控件。
class LabeledRow extends StatelessWidget {
  const LabeledRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 悬停状态构建器。
///
/// Flutter 的 InkWell 只给水波纹，工具类界面更需要整行变底的悬停反馈，
/// 因此统一用 MouseRegion 包一层。
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(bool hovered) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}

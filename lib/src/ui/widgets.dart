import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';

/// 轻量分段控件。
///
/// 不用 Material 的 SegmentedButton 是因为它带较多内边距，
/// 在紧凑的工具面板里显得笨重；同时需要自己实现悬停/按下反馈。
class AppSegmented extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.compact = true,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  /// 紧凑模式：用于面板内；非紧凑用于预览页签
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            PressableBuilder(
              onTap: () => onChanged(i),
              builder: (context, hovered, pressed) {
                final selected = i == index;
                return AnimatedContainer(
                  duration: AppTokens.fast,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 14,
                    vertical: compact ? 5 : 6,
                  ),
                  decoration: BoxDecoration(
                    // 选中态用白底浮起；未选中时靠悬停底色表达「可点」
                    color: selected
                        ? AppTokens.surface
                        : pressed
                            ? AppTokens.pressWash
                            : hovered
                                ? AppTokens.hoverWash
                                : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSmall - 2),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 3,
                              offset: Offset(0, 1),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: compact ? 12 : 12.5,
                      color: selected ? AppTokens.textPrimary : AppTokens.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 状态标签：用小色块 + 文案表达当前状态。
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 区块头：标题在左，操作在右。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// 参数分组之间的分隔，带一点呼吸感。
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1));
}

/// 「标签 + 滑杆 + 当前值」三段式。
///
/// 把数值显式写在右侧是刻意的：滑杆的视觉长度有限，用户很难从滑块位置
/// 判断出精确取值，容易出现「调了半天不知道调成了多少」的困惑。
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    required this.valueLabel,
    this.tooltip,
    this.labelWidth = 68,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

  /// 右侧数值文案：直接给可读单位（如「2px」「0.30 收缩」）
  final String valueLabel;

  /// 悬停提示，用于解释这个参数到底改变什么
  final String? tooltip;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final slider = Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTokens.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: tooltip == null
                ? Text(label, style: Theme.of(context).textTheme.bodySmall)
                : Tooltip(
                    message: tooltip!,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.help_outline,
                            size: 11, color: AppTokens.textTertiary),
                      ],
                    ),
                  ),
          ),
          Expanded(child: slider),
        ],
      ),
    );
  }
}

/// 数字输入框，带范围限制。
class AppNumberField extends StatefulWidget {
  const AppNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.suffix,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? hint;
  final String? suffix;

  @override
  State<AppNumberField> createState() => _AppNumberFieldState();
}

class _AppNumberFieldState extends State<AppNumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(AppNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（如切换规格）改变了取值时同步到输入框，
    // 但正在输入的相同数值不打断光标位置
    if (widget.value.toString() != _controller.text &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 13),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(hintText: widget.hint, suffixText: widget.suffix),
      onSubmitted: (v) {
        final n = int.tryParse(v);
        // 忽略空值与 0：0 尺寸会让内核直接报错
        if (n != null && n > 0) widget.onChanged(n);
      },
    );
  }
}

/// 十六进制颜色输入。
class HexColorField extends StatefulWidget {
  const HexColorField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  State<HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<HexColorField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _hex(widget.value));
  }

  @override
  void didUpdateWidget(HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从色板选了颜色时同步回输入框，否则输入框会与当前底色脱节
    final next = _hex(widget.value);
    if (next != _controller.text && !_controller.text.startsWith('/')) {
      _controller.text = next;
    }
  }

  static String _hex(Color c) =>
      '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: const TextStyle(fontSize: 13),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
        LengthLimitingTextInputFormatter(7),
      ],
      decoration: const InputDecoration(hintText: '#438EDB'),
      onSubmitted: (v) {
        final hex = v.replaceAll('#', '');
        if (hex.length != 6) return;
        final value = int.tryParse(hex, radix: 16);
        if (value == null) return;
        widget.onChanged(
          Color.fromARGB(255, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF),
        );
      },
    );
  }
}

/// 底色小圆点色板。
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: PressableBuilder(
        onTap: onTap,
        builder: (context, hovered, pressed) => AnimatedContainer(
          duration: AppTokens.fast,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: pressed
                ? AppTokens.pressWash
                : hovered
                    ? AppTokens.hoverWash
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            border: Border.all(
              color: selected
                  ? AppTokens.primary
                  : hovered
                      ? AppTokens.borderStrong
                      : AppTokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTokens.border),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? AppTokens.textPrimary : AppTokens.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态提示。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: AppTokens.textTertiary),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// 带忙碌指示的主操作按钮。
///
/// 忙碌时不用 `onPressed: null` 把按钮变灰，而是保留填充色并换成转圈 + 文案：
/// 灰掉的按钮和「程序没反应」在视觉上难以区分，正是这一条导致用户
/// 误判「点了没反应」。
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      child: AnimatedSwitcher(
        duration: AppTokens.normal,
        child: busy
            ? Row(
                key: const ValueKey('busy'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(busyLabel),
                ],
              )
            : Row(
                key: const ValueKey('idle'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../settings.dart';
import '../state/app_state.dart';

/// 参数面板：裁剪、换背景、输出格式与体积控制。
class ParamPanel extends StatelessWidget {
  const ParamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      child: ListView(
        padding: EdgeInsets.zero,
        children: const [
          _CropSection(),
          _Divider(),
          _BackgroundSection(),
          _Divider(),
          _FormatSection(),
          _Divider(),
          _SizeSection(),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1));
}

// ------------------------------------------------------------------ 裁剪

class _CropSection extends StatelessWidget {
  const _CropSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '证件照规格',
          trailing: _Segmented(
            options: const ['关', '预设', '自定义'],
            index: s.cropMode.index,
            onChanged: (i) {
              s.cropMode = CropMode.values[i];
              state.settingsChanged();
            },
          ),
        ),
        if (s.cropMode == CropMode.preset) ...[
          const SizedBox(height: 8),
          _PresetPicker(
            presets: state.presets,
            value: s.presetId,
            onChanged: state.selectPreset,
          ),
          if (s.presetId != null) ...[
            const SizedBox(height: 6),
            _PresetInfo(presetId: s.presetId!, state: state),
          ],
          const SizedBox(height: 2),
          LabeledRow(
            label: '纵向位置',
            child: Slider(
              value: s.verticalAnchor,
              min: 0,
              max: 0.4,
              divisions: 20,
              label: s.verticalAnchor.toStringAsFixed(2),
              onChanged: (v) {
                s.verticalAnchor = v;
                state.settingsChanged();
              },
            ),
          ),
        ],
        if (s.cropMode == CropMode.custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: '宽(px)',
                  value: s.customWidth,
                  onChanged: (v) {
                    s.customWidth = v;
                    state.settingsChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: '高(px)',
                  value: s.customHeight,
                  onChanged: (v) {
                    s.customHeight = v;
                    state.settingsChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '先按规格像素裁剪，再压体积——顺序不可颠倒',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// 规格选择：按分类分组展示，附毫米/像素信息便于核对。
class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.presets,
    required this.value,
    required this.onChanged,
  });

  final List<dynamic> presets;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // 按分类归组，保持内核返回的顺序
    final groups = <String, List<dynamic>>{};
    for (final p in presets) {
      groups.putIfAbsent(p.categoryName as String, () => []).add(p);
    }

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      hint: const Text('选择规格', style: TextStyle(fontSize: 13)),
      style: const TextStyle(fontSize: 13, color: AppTokens.textPrimary),
      items: [
        for (final entry in groups.entries) ...[
          for (final p in entry.value)
            DropdownMenuItem<String>(
              value: p.id as String,
              child: Text(
                '${entry.key} · ${p.name}  ${p.widthPx}×${p.heightPx}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
      onChanged: onChanged,
    );
  }
}

/// 规格详情：毫米/像素/DPI 与备注，让用户能自行核对是否符合报名要求。
class _PresetInfo extends StatelessWidget {
  const _PresetInfo({required this.presetId, required this.state});

  final String presetId;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = state.presets.firstWhere(
      (e) => e.id == presetId,
      orElse: () => state.presets.first,
    );
    final mm = p.widthMm > 0 ? '${p.widthMm}×${p.heightMm}mm · ' : '';
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTokens.canvas,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$mm${p.widthPx}×${p.heightPx}px · ${p.dpi}dpi',
            style: theme.textTheme.bodySmall?.copyWith(color: AppTokens.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(p.note, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              for (var i = 0; i < p.backgroundNames.length; i++)
                _Swatch(
                  color: Color.fromARGB(
                    255,
                    p.backgroundColors[i].red,
                    p.backgroundColors[i].green,
                    p.backgroundColors[i].blue,
                  ),
                  label: p.backgroundNames[i],
                  selected: false,
                  onTap: () => state.selectBackgroundColor(
                    p.backgroundColors[i].red,
                    p.backgroundColors[i].green,
                    p.backgroundColors[i].blue,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 换背景

class _BackgroundSection extends StatelessWidget {
  const _BackgroundSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '背景底色',
          trailing: Switch(
            value: s.backgroundEnabled,
            onChanged: (v) {
              s.backgroundEnabled = v;
              state.settingsChanged();
            },
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (s.backgroundEnabled) ...[
          const SizedBox(height: 8),
          FieldGroup(
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final b in state.backgrounds)
                    _Swatch(
                      color: Color.fromARGB(255, b.color.red, b.color.green, b.color.blue),
                      label: b.name,
                      selected: s.backgroundColor.toARGB32() ==
                          Color.fromARGB(255, b.color.red, b.color.green, b.color.blue)
                              .toARGB32(),
                      onTap: () => state.selectBackgroundColor(
                        b.color.red,
                        b.color.green,
                        b.color.blue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              LabeledRow(label: '自定义', child: _HexColorField(state: state)),
              LabeledRow(
                label: '判定阈值',
                child: Slider(
                  value: s.tolerance,
                  min: 0.03,
                  max: 0.3,
                  divisions: 27,
                  label: s.tolerance.toStringAsFixed(2),
                  onChanged: (v) {
                    s.tolerance = v;
                    state.settingsChanged();
                  },
                ),
              ),
              LabeledRow(
                label: '边缘羽化',
                child: Slider(
                  value: s.featherPx.toDouble(),
                  min: 0,
                  max: 8,
                  divisions: 8,
                  label: '${s.featherPx}px',
                  onChanged: (v) {
                    s.featherPx = v.round();
                    state.settingsChanged();
                  },
                ),
              ),
              LabeledRow(
                label: '边缘收放',
                child: Slider(
                  value: s.edgeOffset,
                  min: -0.5,
                  max: 0.5,
                  divisions: 20,
                  label: s.edgeOffset.toStringAsFixed(2),
                  onChanged: (v) {
                    s.edgeOffset = v;
                    state.settingsChanged();
                  },
                ),
              ),
              ToggleRow(
                label: '消除白边',
                detail: '按原背景色反解前景，去除发丝边缘的发白轮廓',
                value: s.decontaminate,
                onChanged: (v) {
                  s.decontaminate = v;
                  state.settingsChanged();
                },
              ),
              Text(
                '适用于纯色或均匀背景。背景有强渐变或复杂纹理时效果有限。GIF 动图不支持换背景。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 十六进制颜色输入。
class _HexColorField extends StatefulWidget {
  const _HexColorField({required this.state});

  final AppState state;

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _hex(widget.state.settings.backgroundColor));
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
        widget.state.selectBackgroundColor(
          (value >> 16) & 0xFF,
          (value >> 8) & 0xFF,
          value & 0xFF,
        );
      },
    );
  }
}

/// 底色小圆点。
class _Swatch extends StatelessWidget {
  const _Swatch({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            border: Border.all(
              color: selected ? AppTokens.primary : AppTokens.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AppTokens.border),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 输出格式

class _FormatSection extends StatelessWidget {
  const _FormatSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: '输出格式'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: s.outputFormat,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppTokens.textPrimary),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('保持原格式', style: TextStyle(fontSize: 13)),
            ),
            for (final f in kOutputFormats)
              DropdownMenuItem<String?>(
                value: f.extension,
                child: Text('${f.label} — ${f.note}', style: const TextStyle(fontSize: 13)),
              ),
          ],
          onChanged: (v) {
            s.outputFormat = v;
            state.settingsChanged();
          },
        ),
        const SizedBox(height: 4),
        Text(
          'SVG 只能作为输入：位图无法反向转成矢量图',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 体积控制

class _SizeSection extends StatelessWidget {
  const _SizeSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '体积与尺寸',
          trailing: _Segmented(
            options: const ['关', '体积', '长边'],
            index: s.sizeLimitMode.index,
            onChanged: (i) {
              s.sizeLimitMode = SizeLimitMode.values[i];
              state.settingsChanged();
            },
          ),
        ),
        const SizedBox(height: 8),
        if (s.sizeLimitMode == SizeLimitMode.targetSize) ...[
          LabeledRow(
            label: '上限(KB)',
            child: _NumberField(
              value: s.targetKb,
              onChanged: (v) {
                s.targetKb = v;
                state.settingsChanged();
              },
            ),
          ),
          LabeledRow(
            label: '质量下限',
            child: Slider(
              value: s.qualityFloor.toDouble(),
              min: 60,
              max: 95,
              divisions: 35,
              label: '${s.qualityFloor}',
              onChanged: (v) {
                s.qualityFloor = v.round();
                state.settingsChanged();
              },
            ),
          ),
          Text(
            '优先保留分辨率，质量不低于下限；体积实在太紧时才继续降分辨率',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (s.sizeLimitMode == SizeLimitMode.maxLongSide)
          LabeledRow(
            label: '长边(px)',
            child: _NumberField(
              value: s.maxLongSide,
              onChanged: (v) {
                s.maxLongSide = v;
                state.settingsChanged();
              },
            ),
          ),
        const SizedBox(height: 4),
        ToggleRow(
          label: 'JPEG 无色度抽样',
          detail: '即 4:4:4，证件照发丝与文字边缘更干净，体积略增',
          value: s.jpegNoChromaSubsampling,
          onChanged: (v) {
            s.jpegNoChromaSubsampling = v;
            state.settingsChanged();
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 通用

/// 区块头：标题在左，操作在右。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

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

/// 数字输入框，带范围限制。
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.value,
    required this.onChanged,
    this.label,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（如切换预设）改变了取值时同步到输入框，
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
      decoration: InputDecoration(hintText: widget.label),
      onSubmitted: (v) {
        final n = int.tryParse(v);
        // 忽略空值与 0：0 尺寸会让内核直接报错
        if (n != null && n > 0) widget.onChanged(n);
      },
    );
  }
}

/// 紧凑分段控件（与预览面板同款，避免重复实现两套观感）。
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.index,
    required this.onChanged,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTokens.canvas,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: i == index ? AppTokens.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: i == index
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
                      fontSize: 12,
                      color: i == index ? AppTokens.textPrimary : AppTokens.textSecondary,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

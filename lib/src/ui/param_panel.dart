import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../rust/api/dto.dart';

import '../app.dart';
import '../settings.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// 参数面板：裁剪、换背景、输出格式与体积控制。
class ParamPanel extends StatelessWidget {
  const ParamPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      elevated: true,
      child: ListView(
        padding: EdgeInsets.zero,
        children: const [
          _CropSection(),
          SectionDivider(),
          _BackgroundSection(),
          SectionDivider(),
          _FormatSection(),
          SectionDivider(),
          _SizeSection(),
        ],
      ),
    );
  }
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
        SectionHeader(
          title: '证件照规格',
          trailing: AppSegmented(
            options: const ['关', '预设', '自定义'],
            index: s.cropMode.index,
            onChanged: (i) => state.cropModeChanged(CropMode.values[i]),
          ),
        ),
        if (s.cropMode == CropMode.preset) ...[
          const SizedBox(height: 10),
          _PresetPicker(
            presets: state.presets,
            value: s.presetId,
            onChanged: state.selectPreset,
          ),
          if (s.presetId != null) ...[
            const SizedBox(height: 8),
            _PresetInfo(presetId: s.presetId!, state: state),
          ],
        ],
        if (s.cropMode == CropMode.custom) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppNumberField(
                  value: s.customWidth,
                  hint: '宽 px',
                  onChanged: (v) => state.setCustomSize(width: v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppNumberField(
                  value: s.customHeight,
                  hint: '高 px',
                  onChanged: (v) => state.setCustomSize(height: v),
                ),
              ),
            ],
          ),
        ],
        if (s.cropMode != CropMode.none) ...[
          const SizedBox(height: 10),
          _CropFramingHint(state: state),
          const SizedBox(height: 6),
          Text(
            '先按规格像素裁剪，再压体积——顺序不可颠倒',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// 取景操作提示。
///
/// 这段文案不是装饰：取景框只在预览的「构图」页出现，不提示的话
/// 用户根本不知道裁剪范围还能手动调整。
class _CropFramingHint extends StatelessWidget {
  const _CropFramingHint({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final box = state.selectedJob?.cropBox;
    final info = state.selectedJob?.info;
    final sourceW = box == null || info == null ? null : (box.width * info.width).round();
    final sourceH = box == null || info == null ? null : (box.height * info.height).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: AppTokens.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.crop_free, size: 14, color: AppTokens.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '在预览的「构图」页拖动取景框',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '拖动框内平移，拖角点等比缩放，滚轮微调；比例已锁定规格，不会变形。',
            style: TextStyle(fontSize: 11.5, color: AppTokens.textSecondary, height: 1.4),
          ),
          if (sourceW != null && sourceH != null) ...[
            const SizedBox(height: 6),
            Text(
              '当前取景 $sourceW×$sourceH px',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.resetCropBox,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.restart_alt, size: 14),
              label: const Text('恢复默认取景', style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
      ),
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

  final List<PresetDto> presets;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // 按分类归组，保持内核返回的顺序
    final groups = <String, List<PresetDto>>{};
    for (final p in presets) {
      groups.putIfAbsent(p.categoryName, () => []).add(p);
    }

    return DropdownButtonFormField<String>(
      // 用取值做 key：规格被外部改回/重置时强制重建，
      // 否则表单内部状态会停留在旧值，界面显示的规格与实际裁剪不一致
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      hint: const Text('选择规格', style: TextStyle(fontSize: 13)),
      style: const TextStyle(fontSize: 13, color: AppTokens.textPrimary),
      borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      items: [
        for (final entry in groups.entries)
          for (final p in entry.value)
            DropdownMenuItem<String>(
              value: p.id,
              child: Text(
                '${entry.key} · ${p.name}  ${p.widthPx}×${p.heightPx}',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
    final presets = state.presets;
    if (presets.isEmpty) return const SizedBox.shrink();
    final p = presets.firstWhere(
      (e) => e.id == presetId,
      orElse: () => presets.first,
    );
    final mm = p.widthMm > 0 ? '${p.widthMm}×${p.heightMm}mm · ' : '';
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppTokens.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$mm${p.widthPx}×${p.heightPx}px · ${p.dpi}dpi',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTokens.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(p.note, style: theme.textTheme.bodySmall),
          if (p.backgroundNames.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (var i = 0; i < p.backgroundNames.length; i++)
                  ColorSwatchButton(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
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
          const SizedBox(height: 10),
          FieldGroup(
            children: [
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final b in state.backgrounds)
                    ColorSwatchButton(
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
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 68,
                    child: Text('自定义',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Expanded(
                    child: HexColorField(
                      value: s.backgroundColor,
                      onChanged: (c) => state.selectBackgroundColor(
                        (c.r * 255).round(),
                        (c.g * 255).round(),
                        (c.b * 255).round(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LabeledSlider(
                label: '判定阈值',
                tooltip: '越大越宽松：更多"接近背景色"的边缘像素会被判成背景，'
                    '轮廓整体向内收；背景偏亮/偏暗时适当提高',
                value: s.tolerance,
                min: 0.03,
                max: 0.30,
                divisions: 27,
                valueLabel: s.tolerance.toStringAsFixed(2),
                onChanged: (v) {
                  s.tolerance = v;
                  state.settingsChanged();
                },
              ),
              LabeledSlider(
                label: '边缘羽化',
                tooltip: '软边过渡带的宽度（像素）。越大发丝越柔和，'
                    '越小边缘越利落；与"判定阈值"无关，只影响柔化范围',
                value: s.featherPx.toDouble(),
                min: 0,
                max: 8,
                divisions: 8,
                valueLabel: '${s.featherPx}px',
                onChanged: (v) {
                  s.featherPx = v.round();
                  state.settingsChanged();
                },
              ),
              LabeledSlider(
                label: '边缘收放',
                tooltip: '几何平移前景边界：正值收缩前景（去背景残留更彻底），'
                    '负值扩张前景（保住更多发丝）',
                value: s.edgeOffset,
                min: -1,
                max: 1,
                divisions: 20,
                valueLabel: _edgeOffsetLabel(s.edgeOffset),
                onChanged: (v) {
                  s.edgeOffset = v;
                  state.settingsChanged();
                },
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
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '适用于纯色或均匀背景。背景有强渐变或复杂纹理时效果有限。GIF 动图不支持换背景。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  /// 把 -1~1 的无量纲取值翻译成用户能理解的方向词。
  static String _edgeOffsetLabel(double v) {
    if (v.abs() < 0.025) return '0 不变';
    final dir = v > 0 ? '收缩' : '扩张';
    return '${v.abs().toStringAsFixed(2)} $dir';
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
        const SectionHeader(title: '输出格式'),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: s.outputFormat,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, color: AppTokens.textPrimary),
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
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
        const SizedBox(height: 6),
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
        SectionHeader(
          title: '体积与尺寸',
          trailing: AppSegmented(
            options: const ['关', '体积', '长边'],
            index: s.sizeLimitMode.index,
            onChanged: (i) {
              s.sizeLimitMode = SizeLimitMode.values[i];
              state.settingsChanged();
            },
          ),
        ),
        const SizedBox(height: 10),
        if (s.sizeLimitMode == SizeLimitMode.targetSize) ...[
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text('上限 KB', style: theme.textTheme.bodySmall),
              ),
              Expanded(
                child: AppNumberField(
                  value: s.targetKb,
                  onChanged: (v) {
                    s.targetKb = v;
                    state.settingsChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LabeledSlider(
            label: '质量下限',
            tooltip: '体积压不下去时的质量底线；优先保留分辨率，'
                '只有体积实在太紧才继续降分辨率',
            value: s.qualityFloor.toDouble(),
            min: 60,
            max: 95,
            divisions: 35,
            valueLabel: '${s.qualityFloor}',
            onChanged: (v) {
              s.qualityFloor = v.round();
              state.settingsChanged();
            },
          ),
          Text(
            '优先保留分辨率，质量不低于下限；体积实在太紧时才继续降分辨率',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (s.sizeLimitMode == SizeLimitMode.maxLongSide) ...[
          Row(
            children: [
              SizedBox(
                width: 68,
                child: Text('长边 px', style: theme.textTheme.bodySmall),
              ),
              Expanded(
                child: AppNumberField(
                  value: s.maxLongSide,
                  onChanged: (v) {
                    s.maxLongSide = v;
                    state.settingsChanged();
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
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

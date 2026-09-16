import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../state/app_state.dart';

/// 预览面板。
///
/// 预览直接使用内核产出的图，与最终成品走同一条流水线，
/// 因此所见即所得——包括换背景后的真实边缘效果。
class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key});

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  /// 是否显示处理前原图
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final job = state.selectedJob;

    if (job == null) {
      return const Panel(
        child: Center(
          child: Text('选择一张图片查看效果', style: TextStyle(color: AppTokens.textSecondary)),
        ),
      );
    }

    final theme = Theme.of(context);
    final bytes = _showOriginal ? job.bytes : (job.previewBytes ?? job.bytes);
    final hasPreview = job.previewBytes != null;

    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Segmented(
                options: const ['效果', '原图'],
                index: _showOriginal ? 1 : 0,
                onChanged: (i) => setState(() => _showOriginal = i == 1),
              ),
              const Spacer(),
              if (job.previewLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (hasPreview && !_showOriginal)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('预览', style: theme.textTheme.bodySmall),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                // 中性灰底：避免白色或深色底干扰对图片边界的判断
                color: const Color(0xFFEFF0F2),
                borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
              ),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: Image.memory(
                  bytes,
                  key: ValueKey('${job.id}_${_showOriginal}_${job.previewBytes?.length ?? 0}'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Text(
                    '无法显示此图片',
                    style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
          if (!_showOriginal) ...[
            const SizedBox(height: 8),
            _MetaRow(job: job),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 6),
            Text(
              job.error!,
              style: theme.textTheme.bodySmall?.copyWith(color: AppTokens.danger),
            ),
          ],
          if (job.result != null) _ResultNotes(job: job),
        ],
      ),
    );
  }
}

/// 关键指标一行展示，避免堆砌小标题。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.job});

  final ImageJob job;

  @override
  Widget build(BuildContext context) {
    final r = job.result;
    final parts = <String>[
      job.sourcePixelsLabel,
      '→',
      r == null ? '${job.info?.width ?? '—'}×${job.info?.height ?? '—'}' : job.outputPixelsLabel,
    ];
    if (r != null) {
      parts.add('·');
      parts.add(r.formatName);
      if (r.quality > 0 && r.format == 'jpg') {
        parts.add('质量${r.quality}');
      }
      if (r.scale < 0.999) {
        parts.add('缩放${(r.scale * 100).toStringAsFixed(0)}%');
      }
    }
    return Text(
      parts.join(' '),
      style: Theme.of(context).textTheme.bodySmall,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 处理过程说明与降级警告。
///
/// 内核会回报「做了什么」（notes）与「可能不符合预期」（warnings），
/// 这里如实展示，让用户知道算法行为而不是靠猜。
class _ResultNotes extends StatelessWidget {
  const _ResultNotes({required this.job});

  final ImageJob job;

  @override
  Widget build(BuildContext context) {
    final r = job.result!;
    if (r.notes.isEmpty && r.warnings.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in r.notes)
            Text(n, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          for (final w in r.warnings)
            Text(
              w,
              style: theme.textTheme.bodySmall?.copyWith(color: AppTokens.warning),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// 轻量分段控件。
///
/// 不用 Material 的 SegmentedButton 是因为它带较多内边距，
/// 在紧凑的工具面板里显得笨重。
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

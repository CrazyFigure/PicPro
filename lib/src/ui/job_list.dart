import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// 任务列表：展示每一项的名称、体积变化与状态。
class JobList extends StatelessWidget {
  const JobList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.jobs.isEmpty) {
      return Panel(
        elevated: true,
        child: EmptyHint(
          icon: Icons.add_photo_alternate_outlined,
          text: '导入图片后在此批量处理',
          action: FilledButton.tonalIcon(
            style: appTonalButtonStyle(),
            onPressed: state.importFiles,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('导入图片', style: TextStyle(fontSize: 12.5)),
          ),
        ),
      );
    }

    return Panel(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: state.jobs.length,
              itemBuilder: (context, i) {
                final job = state.jobs[i];
                return _JobTile(
                  job: job,
                  selected: job.id == state.selectedJobId,
                  onTap: () => state.selectJob(job.id),
                  onRemove: () => state.removeJob(job.id),
                  onExport: () => state.exportOne(job),
                );
              },
            ),
          ),
          const Divider(height: 13),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Text(
                  '${state.jobs.length} 张 · ${_mb(state.totalInputBytes)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: state.processing ? null : state.clearJobs,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _mb(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.job,
    required this.selected,
    required this.onTap,
    required this.onRemove,
    required this.onExport,
  });

  final ImageJob job;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressableBuilder(
      onTap: onTap,
      builder: (context, hovered, pressed) {
        // 底色的优先级：按下 > 悬停 > 选中 > 常态。
        // 悬停排在选中之前是刻意的：选中项若对悬停毫无反应，
        // 用户会以为鼠标不在那一项上、怀疑点击不会生效。
        final color = pressed
            ? AppTokens.pressWash
            : hovered
                ? (selected
                    ? AppTokens.primary.withValues(alpha: 0.15)
                    : AppTokens.hoverWash)
                : selected
                    ? AppTokens.primary.withValues(alpha: 0.08)
                    : Colors.transparent;
        final border = selected || hovered
            ? (hovered
                ? AppTokens.primary.withValues(alpha: 0.6)
                : AppTokens.primary.withValues(alpha: 0.45))
            : Colors.transparent;
        return AnimatedContainer(
          duration: AppTokens.fast,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            color: color,
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumb(job: job),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${job.sourceSizeLabel} → ${job.outputSizeLabel}   ${job.ratioLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(job: job),
                        const SizedBox(width: 6),
                        if (job.error != null)
                          Expanded(
                            child: Text(
                              job.error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppTokens.danger),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  if (job.outputBytes != null)
                    IconButton(
                      tooltip: '导出这张',
                      onPressed: onExport,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.download_outlined),
                    ),
                  IconButton(
                    tooltip: '移除',
                    onPressed: onRemove,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 列表缩略图。
///
/// 优先用导入时生成的小缩略图：**不要退回原图字节**。
/// 原图即便配上 `cacheWidth`，多数解码器仍会先整张解出来再缩，
/// 每个可见项都会临时分配几十 MB，滚动时反复发生——
/// 这正是「列表卡、内存高」的主要来源之一。
/// 顺序上把处理结果放在缩略图之后，是为了让用户一眼确认这一张改成了什么样。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.job});

  final ImageJob job;

  @override
  Widget build(BuildContext context) {
    final bytes = job.thumbnailBytes ?? job.outputBytes ?? job.previewBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppTokens.surfaceAlt,
          border: Border.all(color: AppTokens.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: bytes == null
            ? const Icon(Icons.image_outlined, size: 18, color: AppTokens.textTertiary)
            : Image.memory(
                bytes,
                key: ValueKey('${job.id}_${job.status}_${job.previewRevision}'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  size: 18,
                  color: AppTokens.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.job});

  final ImageJob job;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (job.status) {
      JobStatus.pending => ('待处理', AppTokens.textSecondary),
      JobStatus.processing => ('处理中', AppTokens.primary),
      JobStatus.done => ('完成', AppTokens.success),
      JobStatus.failed => ('失败', AppTokens.danger),
    };
    return StatusChip(label: label, color: color);
  }
}

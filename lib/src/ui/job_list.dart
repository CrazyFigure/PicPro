import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../state/app_state.dart';

/// 任务列表：展示每一项的名称、体积变化与状态。
class JobList extends StatelessWidget {
  const JobList({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.jobs.isEmpty) {
      return const Panel(
        child: _EmptyHint(
          icon: Icons.add_photo_alternate_outlined,
          text: '导入图片后在此批量处理',
        ),
      );
    }

    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
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
          const Divider(height: 12),
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
                  child: const Text('清空'),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
          color: selected ? AppTokens.primary.withValues(alpha: 0.07) : null,
          border: Border.all(
            color: selected ? AppTokens.primary.withValues(alpha: 0.45) : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(job: job),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${job.sourceSizeLabel} → ${job.outputSizeLabel}   ${job.ratioLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
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
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.download_outlined),
                  ),
                IconButton(
                  tooltip: '移除',
                  onPressed: onRemove,
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表缩略图。
///
/// 用 cacheWidth 让解码器直接输出小图，避免为缩略图解码整张原图而占用大量内存；
/// 列表是懒构建的，因此只有可见项会解码。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.job});

  final ImageJob job;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 44,
        height: 44,
        color: AppTokens.canvas,
        child: Image.memory(
          job.previewBytes ?? job.bytes,
          fit: BoxFit.cover,
          cacheWidth: 96,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            size: 18,
            color: AppTokens.textSecondary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 30, color: AppTokens.textSecondary),
          const SizedBox(height: 8),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

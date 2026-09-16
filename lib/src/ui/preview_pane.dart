import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models.dart';
import '../settings.dart';
import '../state/app_state.dart';
import 'crop_overlay.dart';
import 'source_bytes.dart';
import 'widgets.dart';

/// 预览面板。
///
/// 「效果」直接使用内核产出的图，与最终成品走同一条流水线，
/// 因此所见即所得——包括换背景后的真实边缘效果；
/// 「构图」则在**原图**上叠加可取景的裁剪框，因为成品已经是裁好的，
/// 在上面画框没有意义。
class PreviewPane extends StatefulWidget {
  const PreviewPane({super.key});

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  /// 0 = 效果，1 = 原图，2 = 构图
  int _tab = 0;

  /// 上一帧「是否处于裁剪模式」，用于识别裁剪刚被打开的时刻
  bool _wasCropping = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final job = state.selectedJob;

    if (job == null) {
      return const Panel(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.photo_size_select_actual_outlined,
                  size: 30, color: AppTokens.textTertiary),
              SizedBox(height: 8),
              Text('选择一张图片查看效果',
                  style: TextStyle(color: AppTokens.textSecondary, fontSize: 12.5)),
            ],
          ),
        ),
      );
    }

    final cropping = state.settings.cropMode != CropMode.none && job.info != null;
    if (cropping && !_wasCropping) {
      // 裁剪刚打开时自动切到「构图」。
      // 直接在 build 里改字段而不调用 setState：此刻 _tab 还没被用于渲染，
      // 赋值后同帧生效，可以避免「先闪一下效果图再跳到构图层」。
      _tab = 2;
    }
    _wasCropping = cropping;
    if (!cropping && _tab == 2) _tab = 0;

    return Panel(
      padding: const EdgeInsets.all(10),
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppSegmented(
                options: cropping ? const ['效果', '原图', '构图'] : const ['效果', '原图'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
              const Spacer(),
              if (job.previewLoading && _tab == 0)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (_tab != 2) _PreviewTag(job: job, showOriginal: _tab == 1),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(state, job, cropping)),
          if (_tab == 0) ...[
            const SizedBox(height: 8),
            _MetaRow(job: job),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppTokens.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    job.error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTokens.danger),
                  ),
                ),
              ],
            ),
          ],
          if (job.result != null) _ResultNotes(job: job),
        ],
      ),
    );
  }

  Widget _buildBody(AppState state, ImageJob job, bool cropping) {
    // 「构图」与「原图」都要全分辨率像素，因此都走按需载入。
    // 原生端导入后原始字节已释放，直接用 job.bytes 会拿不到东西。
    if (_tab == 1 || (_tab == 2 && cropping)) {
      return SourceBytesBuilder(
        job: job,
        builder: (context, source) {
          if (_tab == 1) return _imageBox(source, original: true, job: job);
          return _buildCrop(state, job, source);
        },
      );
    }

    // 「效果」页用的是内核产出的预览图，本身很小，无需读回原图
    return _imageBox(job.previewBytes, original: false, job: job);
  }

  /// 构图视图：在**原图**上叠加可取景的裁剪框。
  ///
  /// 必须在原图上画框——成品已经是裁好的，在上面画框没有意义。
  Widget _buildCrop(AppState state, ImageJob job, Uint8List source) {
    final info = job.info!;
    final px = state.settings.outputPixels(state.presetWidthPx, state.presetHeightPx);
    // 预设模式下尚未选规格、或自定义尺寸非法时没有目标像素，
    // 此时必须给出明确指引——渲染成空白面板会让用户以为界面坏了
    if (px == null) {
      return _CropHint(
        text: state.settings.cropMode == CropMode.preset
            ? '先在上方选择证件照规格，再回到这里调整取景'
            : '请先填写有效的宽高像素',
      );
    }
    final aspect = px.width / px.height;
    final box = state.syncCropBox() ??
        CropBox.fitted(
          imageWidth: info.width,
          imageHeight: info.height,
          aspect: aspect,
        );
    return CropOverlay(
      bytes: source,
      imageWidth: info.width,
      imageHeight: info.height,
      box: box,
      outputWidth: px.width,
      outputHeight: px.height,
      onChanged: (b, live) => state.updateCropBox(b, live: live),
      // 不传 box：拖动过程已逐帧写入最新值，这里再传 build 期捕获的旧值
      // 会把用户最后一次调整覆盖掉（表现为松手后框跳回原处）
      onCommit: state.commitCropBox,
      onReset: state.resetCropBox,
    );
  }

  /// 普通图像展示区。[bytes] 为 null 时展示占位。
  Widget _imageBox(Uint8List? bytes, {required bool original, required ImageJob job}) {
    return Container(
      decoration: BoxDecoration(
        // 中性灰底：避免白色或深色底干扰对图片边界的判断
        color: const Color(0xFFEDEFF3),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: bytes == null
            ? const Text(
                '尚未生成预览',
                style: TextStyle(color: AppTokens.textTertiary, fontSize: 12),
              )
            : Image.memory(
                bytes,
                // 版本号变化即强制重建：字节数相同但内容不同的预览也能正确刷新
                key: ValueKey('${job.id}_${original}_${job.previewRevision}'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const Text(
                  '无法显示此图片',
                  style: TextStyle(color: AppTokens.textSecondary, fontSize: 12),
                ),
              ),
      ),
    );
  }
}

/// 构图缺少必要参数时的占位提示。
class _CropHint extends StatelessWidget {
  const _CropHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF3),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.crop_free, size: 28, color: AppTokens.textTertiary),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 右上角的来源标记：让用户一眼知道当前看的是成品、原图还是内部预览。
class _PreviewTag extends StatelessWidget {
  const _PreviewTag({required this.job, required this.showOriginal});

  final ImageJob job;
  final bool showOriginal;

  @override
  Widget build(BuildContext context) {
    final (label, color) = showOriginal
        ? ('原图', AppTokens.textSecondary)
        : (job.previewBytes == null ? ('未处理', AppTokens.textTertiary) : ('预览', AppTokens.primary));
    return StatusChip(label: label, color: color);
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
      if (r.backgroundRatio != null) {
        parts.add('背景占比${(r.backgroundRatio! * 100).toStringAsFixed(0)}%');
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
            Text(n,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
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

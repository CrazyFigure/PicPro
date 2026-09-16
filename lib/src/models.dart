import 'dart:typed_data';

import 'rust/api/dto.dart';

/// 单个待处理项的处理状态。
enum JobStatus {
  /// 已导入，尚未处理
  pending,

  /// 正在处理
  processing,

  /// 处理成功
  done,

  /// 处理失败
  failed,
}

/// 一个待处理的图片项。
///
/// 字段可变是刻意的：批量处理过程中会高频更新进度与结果，
/// 若用不可变模型 + copyWith，每次进度回报都要重建整个列表，
/// 在大批量场景下会造成不必要的分配与重建开销。
class ImageJob {
  ImageJob({
    required this.id,
    required this.name,
    required this.bytes,
    this.sourcePath,
  });

  /// 稳定标识，用于把 Rust 侧的进度回报对应回本项
  final String id;

  /// 原始文件名（含扩展名）
  final String name;

  /// 原始字节。处理需要它；Web 端没有文件路径，只能靠字节
  final Uint8List bytes;

  /// 原生端的文件路径，Web 端为 null
  final String? sourcePath;

  /// 探测得到的源信息（尺寸、格式、帧数）
  ImageInfoDto? info;

  JobStatus status = JobStatus.pending;

  /// 处理后的字节
  Uint8List? outputBytes;

  /// 输出文件名
  String? outputName;

  /// 完整处理结果（含质量、缩放、提示等）
  ProcessResultDto? result;

  /// 失败原因
  String? error;

  /// 预览图字节（JPEG）。与选中项联动刷新
  Uint8List? previewBytes;

  /// 预览是否正在生成
  bool previewLoading = false;

  /// 已生成的输出体积（字节）
  int? get outputSize => outputBytes?.length;

  /// 源体积
  int get sourceSize => bytes.length;

  /// 源尺寸文案
  String get sourceSizeLabel => _kb(sourceSize);

  /// 输出尺寸文案
  String get outputSizeLabel => outputSize == null ? '—' : _kb(outputSize!);

  /// 源像素文案
  String get sourcePixelsLabel =>
      info == null ? '—' : '${info!.width}×${info!.height}';

  /// 输出像素文案
  String get outputPixelsLabel =>
      result == null ? '—' : '${result!.width}×${result!.height}';

  /// 压缩率文案（相对于源体积）
  String get ratioLabel {
    final out = outputSize;
    if (out == null || sourceSize == 0) return '—';
    final saved = (1 - out / sourceSize) * 100;
    // 变大时用负号表达，避免出现「节省 -12%」这种误导文案
    return saved >= 0
        ? '缩小 ${saved.toStringAsFixed(1)}%'
        : '增大 ${(-saved).toStringAsFixed(1)}%';
  }

  /// 重置处理结果，用于参数变更后重新处理
  void resetResult() {
    status = JobStatus.pending;
    outputBytes = null;
    outputName = null;
    result = null;
    error = null;
  }

  static String _kb(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

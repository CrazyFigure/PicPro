import 'dart:typed_data';

import 'rust/api/dto.dart';
import 'services/file_io.dart';
import 'settings.dart';

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
///
/// **常驻内存的控制**：原始字节是本应用最大的内存占用项
/// （一张 12MP 照片解码前就有数 MB，原生端一批 20 张可达上百 MB）。
/// 因此原生端在导入时生成一张缩略图后**立即释放原始字节**，
/// 之后只在预览 / 处理时按路径读回来，用完不再缓存。
/// Web 端没有可访问的本地路径，字节只能常驻。
class ImageJob {
  ImageJob({
    required this.id,
    required this.name,
    required this.byteSize,
    Uint8List? bytes,
    this.sourcePath,
    this.thumbnailBytes,
    // 用初始化形参直接赋值，省掉一层转发
    // ignore: prefer_initializing_formals
  }) : _bytes = bytes;

  /// 稳定标识，用于把 Rust 侧的进度回报对应回本项
  final String id;

  /// 原始文件名（含扩展名）
  final String name;

  /// 原始体积（字节）。导入时记录，**不依赖 [bytes] 是否还在内存里**。
  final int byteSize;

  /// 原生端的文件路径，Web 端为 null
  final String? sourcePath;

  /// 列表缩略图（小尺寸 JPEG，通常 &lt;10KB）。
  ///
  /// 有它之后，列表不再需要为了画 46px 的方块而解码整张原图——
  /// 那会为每个可见项临时分配几十 MB，是本项目最大的一处浪费。
  Uint8List? thumbnailBytes;

  /// 原始字节。原生端导入完成后为 null，需要时用 [loadBytes] 读回。
  Uint8List? _bytes;

  /// 内存中是否还持有原始字节
  bool get hasBytesInMemory => _bytes != null;

  /// 已缓存的原始字节（可能为 null）
  Uint8List? get cachedBytes => _bytes;

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

  /// 预览版本号。
  ///
  /// 界面上用 `ValueKey(预览版本号)` 强制 Image 组件重建。
  /// 不能用 `previewBytes.length` 当标识——两张不同内容的预览
  /// 完全可能字节数相同，那时组件不会重建，用户会看到过期画面，
  /// 表现就是「换了参数却像没生效」。
  int previewRevision = 0;

  /// 预览是否正在生成
  bool previewLoading = false;

  /// 本图自己的取景框（归一化，锁定规格比例）。
  ///
  /// 放在每一项上而不是共用设置里：每张照片的构图不同，
  /// 共用一份会导致切换图片时把上一张的取景套到下一张上。
  CropBox? cropBox;

  /// 取得原始字节。
  ///
  /// 优先用内存里已有的；否则按 [sourcePath] 从磁盘读回。
  /// **读回后不再回填缓存**，否则「省内存」就名存实亡了。
  Future<Uint8List> loadBytes() async {
    final cached = _bytes;
    if (cached != null) return cached;
    final path = sourcePath;
    if (path == null) {
      throw StateError('「$name」的原始字节已释放，且没有可用于重新读取的路径');
    }
    final b = await readFileBytes(path);
    if (b == null) {
      throw StateError('原图已不可读（可能被移动或删除）：$path');
    }
    return b;
  }

  /// 释放常驻的原始字节。
  ///
  /// 仅在没有可供重新读取的路径（Web 端）时才保留，否则释放后无法恢复。
  void releaseBytes() {
    if (sourcePath != null) _bytes = null;
  }

  /// 已生成的输出体积（字节）
  int? get outputSize => outputBytes?.length;

  /// 源体积
  int get sourceSize => byteSize;

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

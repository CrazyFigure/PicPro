import 'dart:ui' show Color;

import 'rust/api/dto.dart';

/// 证件照裁剪切图规格：使用预设 or 自定义尺寸。
enum CropMode {
  /// 不裁剪
  none,

  /// 使用证件照规格预设
  preset,

  /// 自定义像素尺寸
  custom,
}

/// 体积控制方式。
enum SizeLimitMode {
  /// 不限制体积
  none,

  /// 限制单张体积上限
  targetSize,

  /// 限制长边像素
  maxLongSide,
}

/// 全部处理参数。
///
/// 用可变字段 + 单一实例，是为了让界面上的滑杆、下拉框改动能直接落到
/// 同一个对象上并立即触发预览；参数变更后统一调用 `markDirty()` 让
/// 已处理结果失效，保证界面展示的结果与当前参数一致。
class ProcessSettings {
  // ---------------- 裁剪 ----------------
  CropMode cropMode = CropMode.none;

  /// 证件照规格 id，如 size_1cun
  String? presetId;

  /// 自定义输出像素
  int customWidth = 295;
  int customHeight = 413;

  /// 自动构图的纵向锚点，0~1，越小越靠上
  double verticalAnchor = 0.06;

  // ---------------- 换背景 ----------------
  bool backgroundEnabled = false;

  /// 目标底色，默认标准蓝底 #438EDB
  Color backgroundColor = const Color.fromARGB(255, 67, 142, 219);

  /// 背景判定阈值，越大越宽松
  double tolerance = 0.12;

  /// 软边过渡带宽度（像素）
  int featherPx = 2;

  /// 是否做白底去污染（消除发丝白边）
  bool decontaminate = true;

  /// 边缘收放，-1~1，正值收缩前景
  double edgeOffset = 0.0;

  // ---------------- 输出格式 ----------------
  /// 输出格式扩展名，null 表示保持原格式
  String? outputFormat;

  /// 输出不支持透明通道时的压平底色
  Color flattenColor = const Color.fromARGB(255, 255, 255, 255);

  // ---------------- 体积控制 ----------------
  SizeLimitMode sizeLimitMode = SizeLimitMode.none;

  /// 目标体积上限（KB）
  int targetKb = 200;

  /// 长边上限（像素）
  int maxLongSide = 1920;

  /// 是否参与体积搜索的质量下限
  int qualityFloor = 85;

  /// JPEG 是否禁用色度抽样（4:4:4）
  bool jpegNoChromaSubsampling = true;

  /// 是否强制清除元数据（默认关闭：JPEG 输出本就不写 EXIF，
  /// PNG 需要保留时应显式说明）
  bool pngBestCompression = true;

  /// 压缩参数是否有效（启用体积或尺寸控制时才有意义）
  bool get hasAnyLimit =>
      sizeLimitMode != SizeLimitMode.none ||
      cropMode != CropMode.none ||
      outputFormat != null ||
      backgroundEnabled;

  /// 转换为 FFI 参数。
  ///
  /// 只填「用户确实启用了」的字段，未启用的一律传 null，
  /// 让内核用自己的默认值处理，避免两侧默认值不一致导致的隐性差异。
  ProcessOptionsDto toDto() {
    // ---------- 裁剪 ----------
    CropDto? crop;
    switch (cropMode) {
      case CropMode.none:
        crop = null;
      case CropMode.preset:
        if (presetId != null) {
          crop = CropDto(
            presetId: presetId,
            verticalAnchor: verticalAnchor,
          );
        }
      case CropMode.custom:
        crop = CropDto(
          outWidth: customWidth,
          outHeight: customHeight,
        );
    }

    // ---------- 换背景 ----------
    BackgroundDto? background;
    if (backgroundEnabled) {
      background = BackgroundDto(
        color: ColorDto(
          red: (backgroundColor.r * 255).round(),
          green: (backgroundColor.g * 255).round(),
          blue: (backgroundColor.b * 255).round(),
        ),
        tolerance: tolerance,
        featherPx: featherPx,
        decontaminate: decontaminate,
        edgeOffset: edgeOffset,
        smoothAlpha: true,
      );
    }

    // ---------- 体积与质量 ----------
    CompressDto? compress;
    if (sizeLimitMode == SizeLimitMode.targetSize) {
      compress = CompressDto(
        // KB -> 字节。u64 在 FFI 侧映射为 BigInt（避免 Dart int 与 u64 的精度差异）
        targetBytes: BigInt.from(targetKb * 1024),
        qualityFloor: qualityFloor,
        jpegNoChromaSubsampling: jpegNoChromaSubsampling,
        pngBestCompression: pngBestCompression,
      );
    } else if (sizeLimitMode == SizeLimitMode.maxLongSide) {
      compress = CompressDto(
        maxLongSide: maxLongSide,
        qualityFloor: qualityFloor,
        jpegNoChromaSubsampling: jpegNoChromaSubsampling,
        pngBestCompression: pngBestCompression,
      );
    } else if (outputFormat == 'jpg' ||
        outputFormat == 'jpeg' ||
        outputFormat == null) {
      // 未限制体积但输出 JPEG 时，仍带上编码质量相关开关，
      // 否则 4:4:4 等高质量设置不会生效
      compress = CompressDto(
        jpegNoChromaSubsampling: jpegNoChromaSubsampling,
        pngBestCompression: pngBestCompression,
      );
    }

    return ProcessOptionsDto(
      outputFormat: outputFormat,
      crop: crop,
      background: background,
      compress: compress,
      flattenColor: ColorDto(
        red: (flattenColor.r * 255).round(),
        green: (flattenColor.g * 255).round(),
        blue: (flattenColor.b * 255).round(),
      ),
    );
  }

  /// 参数是否足以构成「一次有效处理」。
  ///
  /// 全无操作时不需要跑内核，界面应提示用户先选一项处理方式。
  bool get isEffective => hasAnyLimit;
}

/// 可供选择的输出格式。
class OutputFormatOption {
  const OutputFormatOption(this.extension, this.label, this.note);

  /// 扩展名，null 语义由调用方处理（这里只列具体格式）
  final String extension;

  /// 展示名
  final String label;

  /// 附加说明，例如 GIF 不支持换背景
  final String note;
}

/// 输出格式候选。
///
/// 不含 SVG：位图无法反向矢量化，内核对 SVG 输出会直接报错。
const List<OutputFormatOption> kOutputFormats = [
  OutputFormatOption('jpg', 'JPEG', '体积最小，证件照首选'),
  OutputFormatOption('png', 'PNG', '支持透明，体积较大'),
  OutputFormatOption('webp', 'WebP', '无损编码，体积中等'),
  OutputFormatOption('gif', 'GIF', '支持动画'),
  OutputFormatOption('bmp', 'BMP', '无压缩位图'),
  OutputFormatOption('tiff', 'TIFF', '印刷级无损'),
];

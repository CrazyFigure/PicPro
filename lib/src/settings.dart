import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

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

/// 归一化裁剪框（0~1，相对原图）。
///
/// 用归一化坐标而不是像素坐标，好处是同一份数据既可用于界面上的拖动，
/// 也可直接交给内核在**全分辨率**原图上裁剪——界面不需要知道原图到底多少像素，
/// 预览与成品也就必然一致。
///
/// **关键约束：像素宽高比必须恒等于目标规格。** 归一化矩形的宽高比在非正方形
/// 原图上会失真（1000×500 的图上，归一化 0.375×1.0 实际是 375×500 像素），
/// 因此所有几何运算都走「由宽度反推高度」这一条路径，保证比例永远锁定。
@immutable
class CropBox {
  const CropBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// 左上角横坐标（0~1）
  final double x;

  /// 左上角纵坐标（0~1）
  final double y;

  /// 归一化宽度（0~1）
  final double width;

  /// 归一化高度（0~1）
  final double height;

  /// 由归一化宽度反推高度，使像素宽高比恰好等于 [aspect]。
  ///
  /// 推导：`(width·imgW) / (height·imgH) = aspect` ⟹ `height = width·imgW/(aspect·imgH)`。
  static double heightForWidth({
    required double width,
    required int imageWidth,
    required int imageHeight,
    required double aspect,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || aspect <= 0) return width;
    return width * imageWidth / (aspect * imageHeight);
  }

  /// 构造「能放下的最大居中取景框」。
  ///
  /// 这是用户尚未手动调整时的默认构图：尽量用满画面、水平居中、纵向贴顶。
  /// 纵向刻意贴顶而不居中——人像照的头部位于画面上部，
  /// 纵向居中容易让画面下缘多留一大片无关区域。
  factory CropBox.fitted({
    required int imageWidth,
    required int imageHeight,
    required double aspect,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || aspect <= 0) {
      return const CropBox(x: 0, y: 0, width: 1, height: 1);
    }
    // 归一化宽度取 1 时的高度；若超过 1 说明宽度受限，需反解宽度
    var w = 1.0;
    var h = heightForWidth(
      width: w,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspect: aspect,
    );
    if (h > 1.0) {
      h = 1.0;
      w = h * aspect * imageHeight / imageWidth;
    }
    w = w.clamp(1e-3, 1.0);
    h = h.clamp(1e-3, 1.0);
    return CropBox(x: (1.0 - w) / 2.0, y: 0.0, width: w, height: h);
  }

  /// 平移，并按「不越出画面」的规则夹紧（尺寸不变）。
  CropBox movedBy(double dx, double dy) => CropBox(
        x: (x + dx).clamp(0.0, math.max(0.0, 1.0 - width)),
        y: (y + dy).clamp(0.0, math.max(0.0, 1.0 - height)),
        width: width,
        height: height,
      );

  /// 以给定宽度重建裁剪框（宽度变化会同步换算出高度，比例恒定）。
  ///
  /// [anchorX]/[anchorY] 指定缩放时保持不动的参考点（0~1，相对裁剪框自身），
  /// 例如拖动右下角手柄时用 (0,0)、拖动左上角手柄时用 (1,1)。
  CropBox resizedWidth({
    required double newWidth,
    required int imageWidth,
    required int imageHeight,
    required double aspect,
    double anchorX = 0.5,
    double anchorY = 0.5,
  }) {
    // 归一化宽度下限取「1 像素」对应的宽度，避免缩到取不出图
    final minW = imageWidth > 0 ? 1.0 / imageWidth : 1e-3;
    var w = newWidth.clamp(minW, 1.0);
    var h = heightForWidth(
      width: w,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      aspect: aspect,
    );
    // 高度越界时以高度为准反推宽度，保证「尺寸合法」优先于「用户拖到哪」
    if (h > 1.0) {
      h = 1.0;
      w = (h * aspect * imageHeight / imageWidth).clamp(minW, 1.0);
    }
    // 参考点在缩放前后保持同一个画面位置
    final anchorAbsX = x + width * anchorX;
    final anchorAbsY = y + height * anchorY;
    return CropBox(
      x: anchorAbsX - w * anchorX,
      y: anchorAbsY - h * anchorY,
      width: w,
      height: h,
    ).clamped();
  }

  /// 整体等比缩放（以中心为锚点），用于滚轮缩放与「放大/缩小」按钮。
  CropBox scaledBy(
    double factor, {
    required int imageWidth,
    required int imageHeight,
    required double aspect,
  }) =>
      resizedWidth(
        newWidth: width * factor,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        aspect: aspect,
        anchorX: 0.5,
        anchorY: 0.5,
      );

  /// 换成另一个目标宽高比，保持画面中心与**像素面积**基本不变。
  ///
  /// 这样从「一寸」切到「小二寸」时框体不会突兀地跳到全屏或缩成一团，
  /// 用户已有的取景意图得以延续。
  CropBox withAspect({
    required double aspect,
    required int imageWidth,
    required int imageHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || aspect <= 0) return this;
    final w = imageWidth.toDouble();
    final h = imageHeight.toDouble();
    // 现有像素面积
    final area = (width * w) * (height * h);
    var pw = math.sqrt(area * aspect);
    var ph = math.sqrt(area / aspect);
    var nw = pw / w;
    var nh = ph / h;
    // 越界时按比例回退，始终保持锁定比例
    if (nw > 1.0) {
      nw = 1.0;
      nh = w / (aspect * h);
    }
    if (nh > 1.0) {
      nh = 1.0;
      nw = aspect * h / w;
    }
    // 画布极端窄长时上面两步可能互相冲突，这里再兜一次底
    nw = nw.clamp(1e-3, 1.0);
    nh = nh.clamp(1e-3, 1.0);
    final cx = x + width / 2.0;
    final cy = y + height / 2.0;
    return CropBox(x: cx - nw / 2.0, y: cy - nh / 2.0, width: nw, height: nh)
        .clamped();
  }

  /// 夹紧到画面内（尺寸不变，位置回退）。
  CropBox clamped() => CropBox(
        x: x.clamp(0.0, math.max(0.0, 1.0 - width)),
        y: y.clamp(0.0, math.max(0.0, 1.0 - height)),
        width: width.clamp(1e-3, 1.0),
        height: height.clamp(1e-3, 1.0),
      );

  /// 转换为 FFI 参数。
  CropRectDto toDto() =>
      CropRectDto(x: x, y: y, width: width, height: height);

  @override
  bool operator ==(Object other) =>
      other is CropBox &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'CropBox(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${width.toStringAsFixed(3)}, ${height.toStringAsFixed(3)})';
}

/// 全部处理参数。
///
/// 用可变字段 + 单一实例，是为了让界面上的滑杆、下拉框改动能直接落到
/// 同一个对象上并立即触发预览；参数变更后统一调用 `settingsChanged()` 让
/// 已处理结果失效，保证界面展示的结果与当前参数一致。
///
/// 注意：裁剪框**不在这里**——每张图各自有合适的取景，把它放在共用设置里
/// 会导致切换图片时构图被串改。裁剪框由 [ImageJob] 持有。
class ProcessSettings {
  // ---------------- 裁剪 ----------------
  CropMode cropMode = CropMode.none;

  /// 证件照规格 id，如 size_1cun
  String? presetId;

  /// 自定义输出像素
  int customWidth = 295;
  int customHeight = 413;

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

  /// PNG 是否使用最高压缩级别
  bool pngBestCompression = true;

  /// 目标输出像素尺寸；裁剪关闭时为 null。
  ///
  /// 规格与自定义两条路径统一收口到这里，界面上的取景框按这个比例锁定。
  /// [widthPx]/[heightPx] 由调用方提供当前选中的证件照规格。
  ({int width, int height})? outputPixels(int? presetWidthPx, int? presetHeightPx) {
    switch (cropMode) {
      case CropMode.none:
        return null;
      case CropMode.preset:
        if (presetWidthPx == null || presetHeightPx == null) return null;
        return (width: presetWidthPx, height: presetHeightPx);
      case CropMode.custom:
        if (customWidth <= 0 || customHeight <= 0) return null;
        return (width: customWidth, height: customHeight);
    }
  }

  /// 目标像素宽高比（宽/高）。
  double? outputAspect(int? presetWidthPx, int? presetHeightPx) {
    final px = outputPixels(presetWidthPx, presetHeightPx);
    if (px == null) return null;
    return px.width / px.height;
  }

  /// 压缩参数是否有效（启用体积或尺寸控制时才有意义）
  bool get hasAnyLimit =>
      sizeLimitMode != SizeLimitMode.none ||
      cropMode != CropMode.none ||
      outputFormat != null ||
      backgroundEnabled;

  /// 转换为 FFI 参数。
  ///
  /// [cropBox] 为当前选中图片的取景框；给出时内核完全按它裁剪，
  /// 不再自行推断构图（用户的手动取景永远优先于算法默认值）。
  ///
  /// 未启用的一律传 null，让内核用自己的默认值处理，
  /// 避免两侧默认值不一致导致的隐性差异。
  ProcessOptionsDto toDto({
    CropBox? cropBox,
    int? presetWidthPx,
    int? presetHeightPx,
  }) {
    // ---------- 裁剪 ----------
    final px = outputPixels(presetWidthPx, presetHeightPx);
    CropDto? crop;
    switch (cropMode) {
      case CropMode.none:
        crop = null;
      case CropMode.preset:
        if (presetId != null) {
          crop = CropDto(
            presetId: presetId,
            // 取景框由界面维护；为 null 时不传，交由内核按规格比例自动构图
            rect: cropBox?.toDto(),
            outWidth: px?.width,
            outHeight: px?.height,
          );
        }
      case CropMode.custom:
        // 自定义模式没有规格 id，必须同时给出裁剪框与目标像素，
        // 否则内核既拿不到区域也拿不到尺寸，等于什么都没做
        if (cropBox != null && px != null) {
          crop = CropDto(
            rect: cropBox.toDto(),
            outWidth: px.width,
            outHeight: px.height,
          );
        }
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

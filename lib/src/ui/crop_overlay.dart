import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../settings.dart';

/// 取景框的角点。角点在框自身坐标系中的位置与其对角锚点一一对应：
/// 拖动某个角点时，**对角**保持不动，因此缩放看起来是「以对角为支点拉伸」。
enum _Handle {
  topLeft(hx: 0, hy: 0),
  topRight(hx: 1, hy: 0),
  bottomLeft(hx: 0, hy: 1),
  bottomRight(hx: 1, hy: 1);

  const _Handle({required this.hx, required this.hy});

  /// 角点在框内的归一化横坐标（0 左 1 右）
  final double hx;

  /// 角点在框内的归一化纵坐标（0 上 1 下）
  final double hy;

  /// 拖动该角点时保持不动的锚点（即对角）
  double get anchorX => 1 - hx;
  double get anchorY => 1 - hy;
}

/// 可拖动、可等比缩放的取景框。
///
/// 之所以自己算图像显示区域，而不是把图片包一层再叠加遮罩：`BoxFit.contain`
/// 会在容器内留下不等宽的黑边，若不去除这部分偏差，取景框与图片像素就对应不上，
/// 界面框住的区域和内核实际裁剪的区域会出现系统性偏移。
///
/// 缩放**恒定锁定目标规格的像素宽高比**：这样内核只需按框裁剪再缩放到规格像素，
/// 不会因为长宽比不符而被拉伸变形。用户要做的只是「把框挪到、缩到合适的位置」。
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.box,
    required this.outputWidth,
    required this.outputHeight,
    required this.onChanged,
    required this.onCommit,
    required this.onReset,
  });

  /// 原图字节（取景必须在原图上进行，否则用户无从判断构图）
  final Uint8List bytes;

  /// 原图像素尺寸
  final int imageWidth;
  final int imageHeight;

  /// 当前取景框（归一化，比例已锁定）
  final CropBox box;

  /// 目标输出像素，仅用于文案提示
  final int outputWidth;
  final int outputHeight;

  /// 拖动过程中回调（live = true），用于即时刷新预览
  final void Function(CropBox box, bool live) onChanged;

  /// 拖动结束回调
  final VoidCallback onCommit;

  /// 恢复默认取景
  final VoidCallback onReset;

  /// 取景画布的安全内边距。
  ///
  /// 图片不能紧贴叠加层的边缘：取景框经常与图片边界重合（例如纵向铺满时），
  /// 此时角点手柄正好落在叠加层的右/下边界上，而 Flutter 的命中测试对
  /// 右、下边界取**开区间**——手柄会被判为「在控件之外」，表现为拖不动。
  /// 留出这段边距后，手柄始终完整落在可命中区域内。
  static const double canvasPadding = 12;

  /// 计算 `BoxFit.contain` 下图片实际占据的矩形（居中，已含安全边距）。
  ///
  /// 单独抽成公开静态方法而不是内联在 build 里，是为了让测试能复用同一份
  /// 几何计算去定位取景框——手写一遍容易产生系统性偏差，测试就会失真。
  static Rect imageRectFor(Size available, Size content) {
    final inner = Size(
      math.max(0.0, available.width - canvasPadding * 2),
      math.max(0.0, available.height - canvasPadding * 2),
    );
    if (inner.width <= 0 || inner.height <= 0 || content.width <= 0 || content.height <= 0) {
      return Rect.fromLTWH(canvasPadding, canvasPadding, inner.width, inner.height);
    }
    final scale = math.min(inner.width / content.width, inner.height / content.height);
    final w = content.width * scale;
    final h = content.height * scale;
    return Rect.fromLTWH(
      canvasPadding + (inner.width - w) / 2,
      canvasPadding + (inner.height - h) / 2,
      w,
      h,
    );
  }

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  /// 角点手柄的命中半径（逻辑像素）。给足尺寸是为了照顾触屏——
  /// 手指按不准 6px 的方块，这是「拖不动」问题的常见来源。
  static const double _handleHitRadius = 26;

  /// 手柄的视觉半径
  static const double _handleVisualRadius = 6;

  _Handle? _activeHandle;
  bool _moving = false;
  bool _hoveringBox = false;
  _Handle? _hoveredHandle;

  /// 拖动起点的归一化图像坐标与起始框，避免逐帧累加产生漂移
  late Offset _startNorm;
  late CropBox _startBox;

  /// 显示区域几何：由布局约束与图片比例算出
  late Rect _imageRect;

  double get _aspect => widget.outputWidth / widget.outputHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _imageRect = CropOverlay.imageRectFor(
          Size(c.maxWidth, c.maxHeight),
          Size(widget.imageWidth.toDouble(), widget.imageHeight.toDouble()),
        );
        final boxRect = _boxRect(widget.box);

        return MouseRegion(
          cursor: _cursorFor(_hoveredHandle),
          onHover: (e) {
            final h = _handleAt(e.localPosition);
            final inBox = boxRect.inflate(2).contains(e.localPosition);
            if (h != _hoveredHandle || inBox != _hoveringBox) {
              setState(() {
                _hoveredHandle = h;
                _hoveringBox = inBox;
              });
            }
          },
          onExit: (_) {
            if (_hoveredHandle != null || _hoveringBox) {
              setState(() {
                _hoveredHandle = null;
                _hoveringBox = false;
              });
            }
          },
          child: Listener(
            // 滚轮 = 以中心为锚点等比缩放，桌面端最顺手的调整方式
            onPointerSignal: (e) {
              if (e is! PointerScrollEvent) return;
              final factor = e.scrollDelta.dy > 0 ? 0.94 : 1.06;
              final next = widget.box.scaledBy(
                factor,
                imageWidth: widget.imageWidth,
                imageHeight: widget.imageHeight,
                aspect: _aspect,
              );
              widget.onChanged(next, false);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _onPanStart(d.localPosition, boxRect),
              onPanUpdate: (d) => _onPanUpdate(d.localPosition),
              onPanEnd: (_) {
                setState(() {
                  _activeHandle = null;
                  _moving = false;
                });
                widget.onCommit();
              },
              onPanCancel: () {
                setState(() {
                  _activeHandle = null;
                  _moving = false;
                });
                widget.onCommit();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 原图：按 contain 铺在算好的位置上，保证与取景框像素对齐
                  Positioned.fromRect(
                    rect: _imageRect,
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          '无法显示此图片',
                          style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  // 遮罩 + 边框 + 三分线
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CropMaskPainter(
                          boxRect: boxRect,
                          imageRect: _imageRect,
                          activeHandle: _activeHandle,
                          hoveredHandle: _hoveredHandle,
                          showHandles: !_moving,
                        ),
                      ),
                    ),
                  ),
                  // 顶部工具条：尺寸提示 + 恢复默认
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _OverlayHint(
                      cropWidth: (widget.box.width * widget.imageWidth).round(),
                      cropHeight: (widget.box.height * widget.imageHeight).round(),
                      outputWidth: widget.outputWidth,
                      outputHeight: widget.outputHeight,
                      onReset: widget.onReset,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 把局部坐标换算成归一化图像坐标
  Offset _toNorm(Offset local) => Offset(
        (_imageRect.width <= 0 ? 0 : (local.dx - _imageRect.left) / _imageRect.width),
        (_imageRect.height <= 0 ? 0 : (local.dy - _imageRect.top) / _imageRect.height),
      );

  /// 取景框在界面上的矩形
  Rect _boxRect(CropBox b) => Rect.fromLTWH(
        _imageRect.left + b.x * _imageRect.width,
        _imageRect.top + b.y * _imageRect.height,
        b.width * _imageRect.width,
        b.height * _imageRect.height,
      );

  /// 判断指针落在哪个角点手柄上（就近取，超出命中半径则返回 null）
  _Handle? _handleAt(Offset p) {
    final r = _boxRect(widget.box);
    _Handle? best;
    var bestDist = double.infinity;
    for (final h in _Handle.values) {
      final corner = Offset(
        r.left + h.hx * r.width,
        r.top + h.hy * r.height,
      );
      final d = (corner - p).distance;
      if (d < bestDist) {
        bestDist = d;
        best = h;
      }
    }
    return bestDist <= _handleHitRadius ? best : null;
  }

  MouseCursor _cursorFor(_Handle? h) {
    if (_activeHandle != null) return SystemMouseCursors.grabbing;
    return switch (h) {
      _Handle.topLeft || _Handle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      _Handle.topRight || _Handle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      null => _hoveringBox ? SystemMouseCursors.grab : MouseCursor.defer,
    };
  }

  void _onPanStart(Offset local, Rect boxRect) {
    _startNorm = _toNorm(local);
    _startBox = widget.box;
    final h = _handleAt(local);
    setState(() {
      _activeHandle = h;
      _moving = h == null && boxRect.contains(local);
    });
  }

  void _onPanUpdate(Offset local) {
    final p = _toNorm(local);
    if (_moving) {
      // 平移：尺寸不变，仅夹紧到画面内
      widget.onChanged(
        _startBox.movedBy(p.dx - _startNorm.dx, p.dy - _startNorm.dy),
        true,
      );
      return;
    }
    final h = _activeHandle;
    if (h == null) return;

    // 锚点（对角）在框自身坐标系中的位置
    final ax = _startBox.x + _startBox.width * h.anchorX;
    final ay = _startBox.y + _startBox.height * h.anchorY;

    // 由横向位移与纵向位移各推算一个宽度，取变化更大的一侧作为依据：
    // 用户可能主要在做斜向拖动，只用横向会让纵向拖动显得「没反应」
    final wFromX = h.hx == 0 ? ax - p.dx : p.dx - ax;
    final hCand = h.hy == 0 ? ay - p.dy : p.dy - ay;
    final wFromY = hCand * widget.imageHeight * _aspect / widget.imageWidth;
    final w = (wFromX - _startBox.width).abs() >= (wFromY - _startBox.width).abs()
        ? wFromX
        : wFromY;

    widget.onChanged(
      _startBox.resizedWidth(
        newWidth: w,
        imageWidth: widget.imageWidth,
        imageHeight: widget.imageHeight,
        aspect: _aspect,
        anchorX: h.anchorX,
        anchorY: h.anchorY,
      ),
      true,
    );
  }
}

/// 取景区顶部的提示条：显示源裁剪像素与最终输出像素，并提供「恢复默认取景」。
class _OverlayHint extends StatelessWidget {
  const _OverlayHint({
    required this.cropWidth,
    required this.cropHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.onReset,
  });

  final int cropWidth;
  final int cropHeight;
  final int outputWidth;
  final int outputHeight;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTokens.textPrimary.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
            ),
            child: Text(
              '取景 $cropWidth×$cropHeight px → 输出 $outputWidth×$outputHeight px',
              style: const TextStyle(fontSize: 11.5, color: Colors.white),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: '恢复默认取景',
            child: TextButton.icon(
              onPressed: onReset,
              style: TextButton.styleFrom(
                backgroundColor: AppTokens.surface.withValues(alpha: 0.9),
                foregroundColor: AppTokens.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.restart_alt, size: 15),
              label: const Text('重置', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 绘制取景遮罩：框外压暗、框体描边、三分构图参考线与角点手柄。
class _CropMaskPainter extends CustomPainter {
  _CropMaskPainter({
    required this.boxRect,
    required this.imageRect,
    required this.activeHandle,
    required this.hoveredHandle,
    required this.showHandles,
  });

  final Rect boxRect;
  final Rect imageRect;
  final _Handle? activeHandle;
  final _Handle? hoveredHandle;
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    if (boxRect.width <= 0 || boxRect.height <= 0) return;

    // 框外压暗：用 even-odd 填充图像区域减去取景框，
    // 这样压暗只作用在图片上，不会把面板留白也涂黑
    final mask = Path()..fillType = PathFillType.evenOdd;
    mask.addRect(imageRect);
    mask.addRect(boxRect);
    canvas.drawPath(
      mask,
      Paint()..color = const Color(0x8C0B0F14),
    );

    // 三分线：帮助把脸放在视觉舒适的位置
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final dx = boxRect.left + boxRect.width * i / 3;
      final dy = boxRect.top + boxRect.height * i / 3;
      canvas.drawLine(Offset(dx, boxRect.top), Offset(dx, boxRect.bottom), guide);
      canvas.drawLine(Offset(boxRect.left, dy), Offset(boxRect.right, dy), guide);
    }

    // 框体边框：拖动时加粗变亮，反馈更明确
    final active = activeHandle != null;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.4 : 1.8
        ..color = active ? AppTokens.primaryHover : Colors.white.withValues(alpha: 0.92),
    );

    if (!showHandles) return;

    // 角点手柄
    for (final h in _Handle.values) {
      final corner = Offset(
        boxRect.left + h.hx * boxRect.width,
        boxRect.top + h.hy * boxRect.height,
      );
      final isActive = h == activeHandle;
      final isHovered = h == hoveredHandle;
      final r = isActive || isHovered
          ? _CropOverlayState._handleVisualRadius + 2
          : _CropOverlayState._handleVisualRadius;
      // 外圈白底 + 内圈主色，保证在深色与浅色背景上都看得见
      canvas.drawCircle(corner, r + 1.6, Paint()..color = Colors.white);
      canvas.drawCircle(
        corner,
        r,
        Paint()
          ..color = isActive
              ? AppTokens.primaryPressed
              : isHovered
                  ? AppTokens.primaryHover
                  : AppTokens.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_CropMaskPainter old) =>
      old.boxRect != boxRect ||
      old.imageRect != imageRect ||
      old.activeHandle != activeHandle ||
      old.hoveredHandle != hoveredHandle ||
      old.showHandles != showHandles;
}

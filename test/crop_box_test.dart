import 'package:flutter_test/flutter_test.dart';
import 'package:picpro/src/settings.dart';

/// 取景框几何的纯逻辑测试。
///
/// 这一段是本轮改动的核心：取景框必须**始终锁定目标规格的像素宽高比**，
/// 否则内核按框裁剪后再缩放到规格像素就会产生拉伸变形。
/// 归一化坐标下宽高比会随原图比例失真，因此这里的断言一律用
/// 「实际像素宽高比」而不是归一化宽高比。
void main() {
  /// 归一化矩形在某张图上的实际像素宽高比
  double pixelAspect(CropBox b, int w, int h) => (b.width * w) / (b.height * h);

  group('CropBox.fitted', () {
    test('宽图裁 3:4 时高度占满且水平居中', () {
      // 1200×900（宽图），目标 3:4 比原图更瘦长 → 高度受限
      final b = CropBox.fitted(imageWidth: 1200, imageHeight: 900, aspect: 3 / 4);
      expect(pixelAspect(b, 1200, 900), closeTo(0.75, 1e-6));
      expect(b.height, closeTo(1.0, 1e-6));
      expect(b.width, lessThan(1.0));
      // 水平居中
      expect(b.x, closeTo((1 - b.width) / 2, 1e-6));
      expect(b.y, 0);
    });

    test('高图裁 3:4 时宽度占满且纵向贴顶', () {
      // 必须用**比目标比例更瘦长**的原图（600/1200 = 0.5 < 0.75），
      // 纵向才有自由度；若原图恰好是 3:4，裁剪框铺满全图，纵向无任何余量
      final b = CropBox.fitted(imageWidth: 600, imageHeight: 1200, aspect: 3 / 4);
      expect(pixelAspect(b, 600, 1200), closeTo(0.75, 1e-6));
      expect(b.width, closeTo(1.0, 1e-6));
      expect(b.height, lessThan(1.0));
      // 贴顶：人像头部通常在画面上部，居中容易多留无关的下半部分
      expect(b.y, 0);
    });

    test('原图比例与目标一致时取景框铺满全图', () {
      final b = CropBox.fitted(imageWidth: 900, imageHeight: 1200, aspect: 3 / 4);
      expect(b.x, closeTo(0, 1e-6));
      expect(b.y, closeTo(0, 1e-6));
      expect(b.width, closeTo(1, 1e-6));
      expect(b.height, closeTo(1, 1e-6));
    });

    test('极端窄长图也不越界', () {
      final b = CropBox.fitted(imageWidth: 200, imageHeight: 4000, aspect: 295 / 413);
      expect(pixelAspect(b, 200, 4000), closeTo(295 / 413, 1e-4));
      expect(b.x, greaterThanOrEqualTo(0));
      expect(b.y, greaterThanOrEqualTo(0));
      expect(b.x + b.width, lessThanOrEqualTo(1.0001));
      expect(b.y + b.height, lessThanOrEqualTo(1.0001));
    });
  });

  group('CropBox.resizedWidth', () {
    final base = CropBox.fitted(imageWidth: 900, imageHeight: 1200, aspect: 3 / 4);

    test('缩小后比例不变', () {
      final b = base.resizedWidth(
        newWidth: base.width * 0.5,
        imageWidth: 900,
        imageHeight: 1200,
        aspect: 3 / 4,
      );
      expect(pixelAspect(b, 900, 1200), closeTo(0.75, 1e-6));
      expect(b.width, closeTo(base.width * 0.5, 1e-6));
    });

    test('超过画面时以边界为准同时保持比例', () {
      final b = base.resizedWidth(
        newWidth: 5.0,
        imageWidth: 900,
        imageHeight: 1200,
        aspect: 3 / 4,
      );
      expect(b.width, lessThanOrEqualTo(1.0001));
      expect(b.height, lessThanOrEqualTo(1.0001));
      expect(pixelAspect(b, 900, 1200), closeTo(0.75, 1e-6));
    });

    test('锚点在对角：拖右下角时左上角不动', () {
      // 把框挪到画面中间，才有观察锚点的余量
      final moved = CropBox(x: 0.2, y: 0.2, width: 0.5, height: 0.5 * 900 / (3 / 4) / 1200);
      final b = moved.resizedWidth(
        newWidth: moved.width * 0.6,
        imageWidth: 900,
        imageHeight: 1200,
        aspect: 3 / 4,
        anchorX: 0,
        anchorY: 0,
      );
      expect(b.x, closeTo(moved.x, 1e-6));
      expect(b.y, closeTo(moved.y, 1e-6));
      expect(pixelAspect(b, 900, 1200), closeTo(0.75, 1e-6));
    });

    test('极小宽度被夹到至少 1 像素', () {
      final b = base.resizedWidth(
        newWidth: 0.0000001,
        imageWidth: 900,
        imageHeight: 1200,
        aspect: 3 / 4,
      );
      expect(b.width * 900, greaterThanOrEqualTo(0.9));
    });
  });

  group('CropBox.scaledBy', () {
    test('以中心为锚点缩放', () {
      final base = CropBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4);
      final b = base.scaledBy(
        0.5,
        imageWidth: 1000,
        imageHeight: 1000,
        aspect: 1,
      );
      // 中心保持不动
      expect(b.x + b.width / 2, closeTo(base.x + base.width / 2, 1e-6));
      expect(b.y + b.height / 2, closeTo(base.y + base.height / 2, 1e-6));
      expect(pixelAspect(b, 1000, 1000), closeTo(1.0, 1e-6));
    });
  });

  group('CropBox.withAspect', () {
    test('切换规格后比例更新且仍在画面内', () {
      final base = CropBox.fitted(imageWidth: 1200, imageHeight: 900, aspect: 1);
      final b = base.withAspect(aspect: 295 / 413, imageWidth: 1200, imageHeight: 900);
      expect(pixelAspect(b, 1200, 900), closeTo(295 / 413, 1e-4));
      expect(b.x, greaterThanOrEqualTo(0));
      expect(b.y, greaterThanOrEqualTo(0));
      expect(b.x + b.width, lessThanOrEqualTo(1.0001));
      expect(b.y + b.height, lessThanOrEqualTo(1.0001));
    });
  });

  group('CropBox.movedBy', () {
    test('平移不越出画面', () {
      final b = const CropBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5);
      final right = b.movedBy(10, 10);
      expect(right.x + right.width, lessThanOrEqualTo(1.0001));
      expect(right.y + right.height, lessThanOrEqualTo(1.0001));
      final left = b.movedBy(-10, -10);
      expect(left.x, 0);
      expect(left.y, 0);
      // 尺寸不因平移而改变
      expect(right.width, b.width);
      expect(right.height, b.height);
    });
  });

  group('ProcessSettings', () {
    test('裁剪关闭时不产出裁剪参数', () {
      final s = ProcessSettings();
      final dto = s.toDto(cropBox: null);
      expect(dto.crop, isNull);
    });

    test('自定义模式必须同时给出取景框与目标像素', () {
      final s = ProcessSettings()
        ..cropMode = CropMode.custom
        ..customWidth = 600
        ..customHeight = 800;
      // 没有取景框时内核无事可做，因此这里不应产出裁剪参数
      expect(s.toDto(cropBox: null).crop, isNull);

      final dto = s.toDto(
        cropBox: const CropBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
      );
      expect(dto.crop, isNotNull);
      expect(dto.crop!.outWidth, 600);
      expect(dto.crop!.outHeight, 800);
      expect(dto.crop!.rect!.x, 0.1);
    });

    test('预设模式带取景框时输出规格像素', () {
      final s = ProcessSettings()
        ..cropMode = CropMode.preset
        ..presetId = 'size_1cun';
      final dto = s.toDto(
        cropBox: const CropBox(x: 0, y: 0, width: 1, height: 1),
        presetWidthPx: 295,
        presetHeightPx: 413,
      );
      expect(dto.crop!.presetId, 'size_1cun');
      expect(dto.crop!.outWidth, 295);
      expect(dto.crop!.outHeight, 413);
      expect(dto.crop!.rect, isNotNull);
    });
  });
}

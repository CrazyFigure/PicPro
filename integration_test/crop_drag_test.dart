import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:picpro/src/app.dart';
import 'package:picpro/src/rust/frb_generated.dart';
import 'package:picpro/src/settings.dart';
import 'package:picpro/src/state/app_state.dart';
import 'package:picpro/src/ui/crop_overlay.dart';
import 'package:picpro/src/ui/home_page.dart';

/// 回归测试：证件照取景框必须真的能拖动、能等比缩放。
///
/// 原缺陷是「改成品证照后没办法拖动选择框」——界面上根本没有可拖的框，
/// 只能通过一个语义含糊的「纵向位置」滑杆间接影响构图，且在多数照片上
/// 该滑杆的取值范围被夹紧成 0，表现为「调了没反应」。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  Uint8List asset(String name) => File('build/test_assets/$name').readAsBytesSync();

  /// 组装真实界面并开启一寸规格
  Future<AppState> setup(WidgetTester tester, String file) async {
    final state = AppState();
    state.init();
    await state.addBytes(file, asset(file));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();
    state.selectPreset('size_1cun');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    return state;
  }

  /// 取景框在屏幕上的矩形；依赖叠加层的实际渲染位置，避免手算布局产生偏差
  Rect boxOnScreen(WidgetTester tester, AppState state) {
    final overlayRect = tester.getRect(find.byType(CropOverlay));
    final info = state.selectedJob!.info!;
    final box = state.selectedJob!.cropBox!;
    // 复用叠加层自己的几何计算，避免测试另写一份产生系统性偏差
    final img = CropOverlay.imageRectFor(
      overlayRect.size,
      Size(info.width.toDouble(), info.height.toDouble()),
    );
    return Rect.fromLTWH(
      overlayRect.left + img.left + box.x * img.width,
      overlayRect.top + img.top + box.y * img.height,
      box.width * img.width,
      box.height * img.height,
    );
  }

  /// 像素宽高比：断言必须走这个口径，归一化宽高比会随原图比例失真
  double pixelAspect(AppState state) {
    final info = state.selectedJob!.info!;
    final b = state.selectedJob!.cropBox!;
    return (b.width * info.width) / (b.height * info.height);
  }

  testWidgets('开启规格后自动进入构图页并出现可拖动的取景框', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    // 裁剪刚开启时自动切到「构图」，否则用户不知道框在哪里
    expect(find.byType(CropOverlay), findsOneWidget);
    expect(state.selectedJob!.cropBox, isNotNull);
    expect(pixelAspect(state), closeTo(295 / 413, 1e-3));
  });

  testWidgets('拖动框内可以平移取景位置', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    final before = state.selectedJob!.cropBox!;

    // 先缩小一点，保证纵向有平移余量（框铺满高度时纵向天然无处可去）
    state.updateCropBox(
      before.scaledBy(
        0.8,
        imageWidth: state.selectedJob!.info!.width,
        imageHeight: state.selectedJob!.info!.height,
        aspect: 295 / 413,
      ),
      live: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final start = state.selectedJob!.cropBox!;
    final movable = boxOnScreen(tester, state).center;

    await tester.dragFrom(movable, const Offset(24, 30));
    await tester.pump(const Duration(milliseconds: 500));

    final after = state.selectedJob!.cropBox!;
    expect(
      after.x > start.x || after.y > start.y,
      isTrue,
      reason: '向右下拖动后取景框应发生位移（前 $start，后 $after）',
    );
    // 平移不改变尺寸
    expect(after.width, closeTo(start.width, 1e-6));
    expect(after.height, closeTo(start.height, 1e-6));
    // 比例必须始终锁定
    expect(pixelAspect(state), closeTo(295 / 413, 1e-3));
    // 不能越出画面
    expect(after.x, greaterThanOrEqualTo(0));
    expect(after.y, greaterThanOrEqualTo(0));
    expect(after.x + after.width, lessThanOrEqualTo(1.0001));
    expect(after.y + after.height, lessThanOrEqualTo(1.0001));
  });

  testWidgets('拖角点可以等比缩放且比例不失真', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    final before = state.selectedJob!.cropBox!;
    final rect = boxOnScreen(tester, state);

    // 从右下角往左上拖 → 框变小
    final corner = rect.bottomRight;
    final gesture = await tester.startGesture(corner);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(const Offset(-60, -60));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    final after = state.selectedJob!.cropBox!;
    expect(
      after.width,
      lessThan(before.width),
      reason: '向左上拖右下角应缩小取景框（前 ${before.width}，后 ${after.width}）',
    );
    // 关键：缩放后比例仍严格等于规格，缩放不会让成品被拉伸变形
    expect(pixelAspect(state), closeTo(295 / 413, 1e-3));
  });

  testWidgets('放大到超出画面时自动夹紧而不越界', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    final info = state.selectedJob!.info!;

    state.updateCropBox(
      state.selectedJob!.cropBox!.resizedWidth(
        // 故意给一个远超画面的宽度
        newWidth: 4.0,
        imageWidth: info.width,
        imageHeight: info.height,
        aspect: 295 / 413,
      ),
      live: false,
    );
    await tester.pump(const Duration(milliseconds: 500));

    final b = state.selectedJob!.cropBox!;
    expect(b.width, lessThanOrEqualTo(1.0001));
    expect(b.height, lessThanOrEqualTo(1.0001));
    expect(b.x, greaterThanOrEqualTo(0));
    expect(b.y, greaterThanOrEqualTo(0));
    expect(pixelAspect(state), closeTo(295 / 413, 1e-3));
  });

  testWidgets('恢复默认取景会重新铺满可用区域', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    final info = state.selectedJob!.info!;
    // 先缩到很小
    state.updateCropBox(
      state.selectedJob!.cropBox!.scaledBy(
        0.3,
        imageWidth: info.width,
        imageHeight: info.height,
        aspect: 295 / 413,
      ),
      live: false,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final small = state.selectedJob!.cropBox!;

    state.resetCropBox();
    await tester.pump(const Duration(milliseconds: 500));
    final reset = state.selectedJob!.cropBox!;

    expect(reset.width, greaterThan(small.width));
    expect(pixelAspect(state), closeTo(295 / 413, 1e-3));
  });

  testWidgets('切换到自定义尺寸后比例跟随自定义值', (tester) async {
    final state = await setup(tester, 'portrait_600x800.png');
    state.cropModeChanged(CropMode.custom);
    await tester.pump(const Duration(milliseconds: 500));
    state.setCustomSize(width: 600, height: 600);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CropOverlay), findsOneWidget);
    expect(pixelAspect(state), closeTo(1.0, 1e-3));
  });
}

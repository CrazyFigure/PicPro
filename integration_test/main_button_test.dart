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
import 'package:picpro/src/ui/home_page.dart';

/// 回归测试：主操作按钮在任何情况下都必须保持可点。
///
/// 「处理过一次之后就无法再处理第二次」是本项目实际收到过的反馈。
/// 这里用**真实界面 + 真实内核**把这条路径钉死，覆盖两点：
///   1. 处理结束后 `processing` 必须复位、按钮必须重新可点；
///   2. 12MP 级别的大图也要走完同一条路径，不能因耗时过长而卡死界面。
/// 顺带记录了各阶段耗时，便于日后回看是否出现性能退化。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  Uint8List asset(String name) =>
      File('build/test_assets/$name').readAsBytesSync();

  Future<void> pumpUntilIdle(WidgetTester tester, AppState state) async {
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!state.processing) break;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  FilledButton primary(WidgetTester tester) => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('开始处理'),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets('12MP 照片：预览与处理的耗时，以及按钮是否仍然可点', (tester) async {
    final state = AppState();
    state.init();

    final swLoad = Stopwatch()..start();
    await state.addBytes('photo.png', asset('photo_3000x4000.png'));
    swLoad.stop();
    debugPrint('[耗时] 导入 12MP 图耗时 ${swLoad.elapsedMilliseconds}ms');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    final s = state.settings;
    s.cropMode = CropMode.preset;
    s.presetId = 'size_1cun';
    s.backgroundEnabled = true;
    s.sizeLimitMode = SizeLimitMode.targetSize;
    s.targetKb = 200;
    s.outputFormat = 'jpg';

    // 参数变更 -> 防抖 280ms -> 同步跑一次全分辨率预览
    final swPreview = Stopwatch()..start();
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    swPreview.stop();
    debugPrint('[耗时] 参数变更到预览完成耗时 ${swPreview.elapsedMilliseconds}ms');
    debugPrint('[耗时] 预览字节数 ${state.jobs.single.previewBytes?.length}');

    expect(primary(tester).onPressed, isNotNull, reason: '首次处理前按钮应可用');

    // 第一次处理
    final swProc = Stopwatch()..start();
    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    swProc.stop();
    debugPrint('[耗时] 第一次处理耗时 ${swProc.elapsedMilliseconds}ms '
        '状态=${state.jobs.single.status} 错误=${state.jobs.single.error}');
    debugPrint('[耗时] 处理结束后 processing=${state.processing} '
        '按钮可用=${primary(tester).onPressed != null}');

    expect(
      state.processing,
      isFalse,
      reason: '处理结束后资源必须复位',
    );
    expect(
      primary(tester).onPressed,
      isNotNull,
      reason: '处理后主按钮必须仍然可点，否则用户无法处理第二次',
    );

    // 第二次处理：改参数
    s.targetKb = 30;
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      primary(tester).onPressed,
      isNotNull,
      reason: '参数变更后主按钮必须可用',
    );

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    debugPrint('[耗时] 第二次处理结束后 status=${state.jobs.single.status} '
        'error=${state.jobs.single.error} lastError=${state.lastError}');
    expect(state.jobs.single.status.name, 'done');
    expect(state.processing, isFalse);
  });

  testWidgets('真实入口 PicProApp：按钮在两次处理之间保持可用', (tester) async {
    // 走与 lib/main.dart 一致的构建方式（provider create 而非 value）
    final state = AppState();
    state.init();
    await state.addBytes('photo.png', asset('portrait_600x800.png'));

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    final s = state.settings;
    s.cropMode = CropMode.preset;
    s.presetId = 'size_1cun';
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(primary(tester).onPressed, isNotNull);

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(primary(tester).onPressed, isNotNull);
    expect(state.lastError, isNull);
  });
}

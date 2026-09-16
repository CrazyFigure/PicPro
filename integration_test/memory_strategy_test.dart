import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:picpro/src/app.dart';
import 'package:picpro/src/models.dart';
import 'package:picpro/src/rust/frb_generated.dart';
import 'package:picpro/src/settings.dart';
import 'package:picpro/src/state/app_state.dart';
import 'package:picpro/src/ui/home_page.dart';

/// 内存策略回归测试：原生端导入后必须释放原始字节，且后续功能不受影响。
///
/// 背景：界面原先对每张图都常驻持有原始字节，一批 20 张 12MP 照片
/// 就是上百 MB 的常驻占用。现在的策略是「导入时生成缩略图 → 释放原始字节 →
/// 预览/处理时按路径读回，用完即弃」。
///
/// 这里要钉住的是：**省内存不能以牺牲功能为代价**。释放之后预览、处理、
/// 列表缩略图都必须照常工作，否则这个优化就是不可接受的。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  Uint8List asset(String name) =>
      File('build/test_assets/$name').readAsBytesSync();

  /// 清理临时目录。
  ///
  /// Windows 上刚读完的文件可能仍被句柄占用，删除会直接抛
  /// PathAccessException。临时目录清不掉不属于被测行为，
  /// 因此这里吞掉异常——不要让它把一个通过的测试判成失败。
  Future<void> cleanupTemp(Directory dir) async {
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // 交给操作系统的临时目录清理机制
    }
  }

  Future<void> pumpUntilIdle(WidgetTester tester, AppState state) async {
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!state.processing) break;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('释放原始字节后，缩略图 / 预览 / 处理全部照常可用', (tester) async {
    // 拷到临时目录，模拟真实导入（f.path 是真实存在的文件路径）
    final tmp = await Directory.systemTemp.createTemp('picpro_mem_test');
    addTearDown(() => cleanupTemp(tmp));
    final src = File('${tmp.path}/portrait.png');
    await src.writeAsBytes(asset('portrait_600x800.png'));

    final state = AppState();
    state.init();
    await state.addBytes('portrait.png', src.readAsBytesSync(), path: src.path);

    final job = state.jobs.single;

    // ---------- 1. 内存策略本身 ----------
    expect(
      job.hasBytesInMemory,
      isFalse,
      reason: '有文件路径时导入后必须释放原始字节',
    );
    expect(state.residentInputBytes, 0, reason: '常驻的原始字节应为 0');
    expect(
      state.totalInputBytes,
      greaterThan(0),
      reason: '源体积仍需保留，否则列表与压缩率都算不出来',
    );
    expect(
      job.thumbnailBytes,
      isNotNull,
      reason: '必须生成列表缩略图，否则列表只能退回去解码整张原图',
    );

    // ---------- 2. 界面照常渲染 ----------
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();
    expect(find.text('portrait.png'), findsOneWidget);

    // ---------- 3. 预览可用（内部会按路径读回原图） ----------
    state.selectPreset('size_1cun');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(job.previewBytes, isNotNull, reason: '释放字节后预览仍必须能生成');

    // ---------- 4. 处理可用 ----------
    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(job.status, JobStatus.done, reason: '错误：${job.error}');
    expect(job.result!.width, 295);
    expect(job.result!.height, 413);

    // ---------- 5. 第二次处理仍然可用 ----------
    state.settings.sizeLimitMode = SizeLimitMode.targetSize;
    state.settings.targetKb = 60;
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(job.status, JobStatus.done, reason: '错误：${job.error}');
    expect(state.processing, isFalse);
  });

  testWidgets('原图被外部删除后给出可读提示而不是崩溃', (tester) async {
    final tmp = await Directory.systemTemp.createTemp('picpro_mem_gone');
    addTearDown(() => cleanupTemp(tmp));
    final src = File('${tmp.path}/gone.png');
    await src.writeAsBytes(asset('portrait_600x800.png'));

    final state = AppState();
    state.init();
    await state.addBytes('gone.png', src.readAsBytesSync(), path: src.path);
    await src.delete();

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

    // 必须给出明确文案，而不是抛异常穿透到界面
    expect(state.lastError, isNotNull);
    expect(state.lastError!.contains('不可读') || state.lastError!.contains('预览失败'), isTrue,
        reason: '实际提示：${state.lastError}');

    // 处理时也应逐项失败并给出可读原因，而不是整批崩溃
    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(state.processing, isFalse, reason: '单张失败不能让处理状态卡住');
    expect(state.jobs.single.status, JobStatus.failed);
    expect(state.jobs.single.error, isNotNull);
  });
}

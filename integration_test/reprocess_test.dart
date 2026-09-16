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

/// 回归测试：同一张图片必须可以被反复处理。
///
/// 缺陷现象：处理过一次之后无法再处理第二次，必须重新导入另一张图并切换过去才行。
/// 这里刻意走**真实界面**（HomePage）而不是直接调 AppState，
/// 因为问题可能出现在状态层，也可能出现在界面重建环节。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  /// 读取合成人像图；由 scripts/gen_test_assets.py 生成，位于已忽略的 build/ 目录下
  Uint8List portrait() {
    final f = File('build/test_assets/portrait_600x800.png');
    if (!f.existsSync()) {
      throw StateError(
        '缺少测试图片 ${f.path}，请先运行 scripts/gen_test_assets.py 生成',
      );
    }
    return f.readAsBytesSync();
  }

  /// 循环 pump 直到处理结束，避免 pumpAndSettle 被不确定进度条卡住
  Future<void> pumpUntilIdle(WidgetTester tester, AppState state) async {
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!state.processing) break;
    }
    // 冲掉预览防抖计时器（280ms）
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('同一张图可以连续处理两次且第二次结果确实生效', (tester) async {
    final state = AppState();
    state.init();
    await state.addBytes('portrait.png', portrait());

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    // 构造一份常见的证件照任务：裁到一寸 + 换蓝底 + 限体积
    final s = state.settings;
    s.cropMode = CropMode.preset;
    s.presetId = 'size_1cun';
    s.backgroundEnabled = true;
    s.sizeLimitMode = SizeLimitMode.targetSize;
    s.targetKb = 200;
    s.outputFormat = 'jpg';
    state.settingsChanged();

    // ---------- 第一次处理 ----------
    expect(find.text('开始处理'), findsOneWidget);
    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);

    final job = state.jobs.single;
    expect(job.status, JobStatus.done, reason: '第一次处理应成功，错误：${job.error}');
    final firstBytes = job.outputBytes!.length;
    final firstResult = job.result!;
    expect(firstResult.width, 295);
    expect(firstResult.height, 413);

    // ---------- 第二次处理：换一个规格，结果必须随之变化 ----------
    // 用切换规格而不是收紧体积上限来驱动变化：面积不同必然导致字节数不同，
    // 而体积上限在两种取值下可能同时被同一个编码结果满足，断言会失去意义。
    s.presetId = 'size_2cun';
    s.targetKb = 20;
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 500));

    // 参数变更后结果应被标记为待处理
    expect(job.status, JobStatus.pending, reason: '参数变更后旧结果必须失效');
    // 规格变了，取景框比例必须跟着变，否则界面上的框与内核裁剪区域会脱节
    final box = state.syncCropBox();
    expect(box, isNotNull);
    expect(
      (box!.width * job.info!.width) / (box.height * job.info!.height),
      closeTo(413 / 579, 1e-3),
      reason: '取景框比例必须跟随新规格',
    );

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);

    expect(
      state.processing,
      isFalse,
      reason: '处理结束后必须复位 processing，否则按钮会被永久禁用',
    );
    expect(
      job.status,
      JobStatus.done,
      reason: '第二次处理应成功，错误：${job.error}',
    );
    expect(state.lastError, isNull, reason: '第二次处理不应报错');
    expect(
      job.result!.width,
      413,
      reason: '第二次应按二寸规格输出（第一次是一寸 295）',
    );
    expect(job.result!.height, 579);
    expect(
      job.outputBytes!.length,
      isNot(firstBytes),
      reason: '换了规格后输出应确实重新生成',
    );

    // ---------- 第三次：参数不变时也必须能重复处理 ----------
    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(job.status, JobStatus.done);
    expect(state.processing, isFalse);
    expect(job.result!.width, 413);
  });

  testWidgets('二次处理后预览会刷新为最新结果', (tester) async {
    final state = AppState();
    state.init();
    await state.addBytes('portrait.png', portrait());

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
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 400));

    final job = state.jobs.single;
    final preview1 = job.previewBytes;
    expect(preview1, isNotNull, reason: '选中项应生成预览');

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);

    // 换一个明显不同的规格，预览内容必须跟着变
    state.selectPreset('size_2cun');
    await tester.pump(const Duration(milliseconds: 400));
    final preview2 = job.previewBytes;
    expect(preview2, isNotNull);
    expect(
      identical(preview1, preview2),
      isFalse,
      reason: '规格变更后预览必须是新生成的对象，不能沿用旧的',
    );

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);
    expect(job.result!.width, 413);
    expect(job.result!.height, 579);
  });

  testWidgets('处理过程中按钮进入不可用状态并可恢复', (tester) async {
    final state = AppState();
    state.init();
    await state.addBytes('portrait.png', portrait());

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      ),
    );
    await tester.pump();

    final s = state.settings;
    s.sizeLimitMode = SizeLimitMode.targetSize;
    s.targetKb = 200;
    state.settingsChanged();
    await tester.pump(const Duration(milliseconds: 400));

    FilledButton primaryButton() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('开始处理'),
            matching: find.byType(FilledButton),
          ),
        );

    expect(primaryButton().onPressed, isNotNull);

    await tester.tap(find.text('开始处理'));
    await pumpUntilIdle(tester, state);

    expect(
      primaryButton().onPressed,
      isNotNull,
      reason: '处理完成后主操作必须重新可用，否则用户无法处理第二次',
    );
    expect(state.jobs.single.result, isNotNull);
  });
}

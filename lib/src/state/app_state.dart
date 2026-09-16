import 'dart:async';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../rust/api/dto.dart';
import '../rust/api/image_api.dart';
import '../services/file_io.dart';
import '../settings.dart';

/// 应用唯一状态源。
///
/// 设计要点：
/// - 所有字段变更后调用 `notifyListeners()`，界面通过 Provider 订阅；
/// - 参数变更会使已处理结果失效（`markResultsStale`），避免界面展示
///   与当前参数不符的旧结果；
/// - 预览生成做了防抖，参数连续变化时只在停顿后跑一次内核。
class AppState extends ChangeNotifier {
  /// 待处理与已处理的图片项
  final List<ImageJob> jobs = [];

  /// 当前处理参数
  final ProcessSettings settings = ProcessSettings();

  /// 证件照规格预设（启动时从内核加载）
  List<PresetDto> presets = const [];

  /// 标准底色候选
  List<BackgroundChoiceDto> backgrounds = const [];

  /// 原生端的输出目录；Web 端恒为 null
  String? outputDirectory;

  /// 输出文件名后缀，便于区分原图
  String outputSuffix = '_picpro';

  /// 是否正在批量处理
  bool processing = false;

  /// 批量处理进度 0~1
  double progress = 0;

  /// 状态栏文案
  String statusText = '';

  /// 最近一次处理的错误提示
  String? lastError;

  /// 当前选中的项（用于预览）
  String? selectedJobId;

  /// 预估总输入体积，用于内存提示
  int get totalInputBytes =>
      jobs.fold(0, (sum, j) => sum + j.bytes.length);

  /// 已成功处理的项
  List<ImageJob> get completedJobs =>
      jobs.where((j) => j.status == JobStatus.done && j.outputBytes != null).toList();

  /// 当前选中项
  ImageJob? get selectedJob {
    final id = selectedJobId;
    if (id == null) return null;
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// 已导入且可处理的项
  bool get hasJobs => jobs.isNotEmpty;

  Timer? _previewDebounce;

  /// 初始化：加载内核侧提供的预设与底色。
  ///
  /// 内核接口是同步的，因此本方法也同步执行——预设列表规模很小，
  /// 不会造成可感知的卡顿。
  void init() {
    try {
      presets = listPresets();
      backgrounds = standardBackgrounds();
      statusText = '已就绪';
    } catch (e) {
      lastError = '内核初始化失败：$e';
      statusText = '初始化失败';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- 导入

  /// 选择并导入图片。
  Future<void> importFiles() async {
    lastError = null;
    try {
      final picked = await pickImageFiles();
      if (picked.isEmpty) return;

      var added = 0;
      for (final f in picked) {
        final bytes = await f.readAsBytes();
        final job = ImageJob(
          // 用「时间戳 + 序号」做标识：文件名可能重复，不能作为唯一键
          id: '${DateTime.now().microsecondsSinceEpoch}_${jobs.length}',
          name: f.name,
          bytes: bytes,
          sourcePath: isWebPlatform ? null : f.path,
        );
        // 探测失败不阻断导入，仅让该项缺少尺寸信息，
        // 真正的失败会在处理阶段以明确文案抛出。
        // 注意：内核接口是同步的（为兼容非 HTTPS 部署而关闭了 FRB 异步），
        // 因此这里不写 await。
        try {
          job.info = probeImage(bytes: bytes, filename: f.name);
        } catch (_) {
          job.info = null;
        }
        jobs.add(job);
        added++;
      }
      selectedJobId ??= jobs.isNotEmpty ? jobs.first.id : null;
      statusText = '已导入 $added 张图片';
      schedulePreview();
    } catch (e) {
      lastError = '导入失败：$e';
    }
    notifyListeners();
  }

  /// 添加预先读好的字节（供拖拽导入使用）。
  Future<void> addBytes(String name, Uint8List bytes, {String? path}) async {
    final job = ImageJob(
      id: '${DateTime.now().microsecondsSinceEpoch}_${jobs.length}',
      name: name,
      bytes: bytes,
      sourcePath: path,
    );
    try {
      // 内核接口为同步调用，无需 await
      job.info = probeImage(bytes: bytes, filename: name);
    } catch (_) {
      job.info = null;
    }
    jobs.add(job);
    selectedJobId ??= job.id;
    schedulePreview();
    notifyListeners();
  }

  void removeJob(String id) {
    jobs.removeWhere((j) => j.id == id);
    if (selectedJobId == id) {
      selectedJobId = jobs.isEmpty ? null : jobs.first.id;
    }
    schedulePreview();
    notifyListeners();
  }

  void clearJobs() {
    jobs.clear();
    selectedJobId = null;
    progress = 0;
    statusText = '';
    notifyListeners();
  }

  void selectJob(String id) {
    if (selectedJobId == id) return;
    selectedJobId = id;
    schedulePreview();
    notifyListeners();
  }

  // ------------------------------------------------------------ 参数变更

  /// 参数变更后的统一收口。
  ///
  /// 已处理的结果在新参数下不再有效，必须标记为待处理，
  /// 否则界面会展示「旧结果 + 新参数」的错配组合。
  void markResultsStale() {
    for (final j in jobs) {
      if (j.status != JobStatus.pending) {
        j.resetResult();
      }
      j.previewBytes = null;
    }
    statusText = '参数已变更，需重新处理';
    notifyListeners();
  }

  /// 设置变更 + 立即刷新预览（供界面滑杆等高频操作调用）。
  void settingsChanged() {
    markResultsStale();
    schedulePreview();
  }

  /// 选择证件照规格预设。
  void selectPreset(String? presetId) {
    settings.cropMode = presetId == null ? CropMode.none : CropMode.preset;
    settings.presetId = presetId;
    settingsChanged();
  }

  /// 选择标准底色。
  void selectBackgroundColor(int red, int green, int blue) {
    settings.backgroundColor =
        Color.fromARGB(255, red.clamp(0, 255), green.clamp(0, 255), blue.clamp(0, 255));
    settingsChanged();
  }

  // ---------------------------------------------------------------- 预览

  /// 防抖生成预览。
  ///
  /// 滑杆拖动会触发大量变更事件，逐次调用内核会造成明显卡顿，
  /// 因此等待短暂停顿后再生成一次。
  void schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(
      const Duration(milliseconds: 280),
      () => refreshPreview(),
    );
  }

  /// 为选中项生成预览图。
  ///
  /// 内核调用是同步的，因此本方法也同步执行。预览图很小（长边 900px），
  /// 单次耗时通常在几十毫秒量级，可以直接在事件回调里完成。
  void refreshPreview() {
    final job = selectedJob;
    if (job == null) return;
    if (!settings.isEffective) {
      // 没有任何处理动作时直接展示原图，省去一次内核调用
      job.previewBytes = null;
      notifyListeners();
      return;
    }

    job.previewLoading = true;
    notifyListeners();
    try {
      job.previewBytes = makePreview(
        bytes: job.bytes,
        filename: job.name,
        options: settings.toDto(),
        maxSide: 900,
      );
    } catch (e) {
      job.previewBytes = null;
      lastError = '预览失败：$e';
    } finally {
      job.previewLoading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ 批量处理

  /// 处理全部待处理项。
  ///
  /// 内核接口是同步的（为兼容非 HTTPS 部署而关闭了 FRB 异步），
  /// 因此这里逐张串行调用。**每张之间必须让出事件循环**——
  /// 同步调用会占用主线程，不让出的话整个批次期间界面完全无法重绘，
  /// 用户会以为程序卡死。
  ///
  /// 每张独立捕获异常：单张失败不影响其余项，与前一批量实现语义一致。
  Future<void> processAll() async {
    if (processing || jobs.isEmpty) return;
    if (!settings.isEffective) {
      lastError = '请先选择至少一项处理方式（裁剪、换背景或限制体积）';
      notifyListeners();
      return;
    }

    processing = true;
    progress = 0;
    lastError = null;
    final targets = List<ImageJob>.from(jobs);
    for (final j in targets) {
      j.status = JobStatus.processing;
      j.error = null;
    }
    notifyListeners();

    var finished = 0;
    var ok = 0;
    var failed = 0;
    final options = settings.toDto();

    try {
      for (final job in targets) {
        try {
          final r = processImage(
            bytes: job.bytes,
            filename: job.name,
            options: options,
          );
          job.outputBytes = r.bytes;
          job.outputName = _outputNameFor(job, r);
          job.result = r;
          job.status = JobStatus.done;
          ok++;
        } catch (e) {
          job.error = '$e';
          job.status = JobStatus.failed;
          failed++;
        }
        finished++;
        progress = finished / targets.length;
        notifyListeners();
        // 让出事件循环，使进度条与列表状态能真正刷新出来
        await Future.delayed(Duration.zero);
      }
      statusText = failed == 0
          ? '处理完成，共 $ok 张'
          : '处理完成：成功 $ok 张，失败 $failed 张';
    } catch (e) {
      lastError = '批量处理中断：$e';
      for (final j in targets) {
        if (j.status == JobStatus.processing) {
          j.status = JobStatus.failed;
          j.error = '$e';
        }
      }
    } finally {
      processing = false;
      notifyListeners();
    }
  }

  /// 计算输出文件名。
  ///
  /// 规则：原文件名（去扩展名）+ 用户后缀 + 输出格式扩展名。
  /// 后缀为空时直接追加扩展名，保持与原图可区分（格式不变时加后缀避免覆盖）。
  String _outputNameFor(ImageJob job, ProcessResultDto result) {
    final dot = job.name.lastIndexOf('.');
    final stem = dot > 0 ? job.name.substring(0, dot) : job.name;
    final suffix = sanitizeFileName(outputSuffix.trim());
    return sanitizeFileName('$stem$suffix.${result.format}');
  }

  // ---------------------------------------------------------------- 导出

  /// 选择输出目录（仅原生端）。
  Future<void> chooseOutputDir() async {
    if (!canChooseOutputDirectory) return;
    final dir = await chooseOutputDirectory();
    if (dir != null) {
      outputDirectory = dir;
      statusText = '输出目录：$dir';
      notifyListeners();
    }
  }

  /// 导出全部已处理结果。
  ///
  /// 逐项独立保存：单项失败不影响其余项，最后汇总成功与失败数量，
  /// 避免一个文件名非法就导致整批导出失败。
  Future<void> exportAll() async {
    final done = completedJobs;
    if (done.isEmpty) {
      lastError = '还没有可导出的处理结果';
      notifyListeners();
      return;
    }

    var ok = 0;
    final failures = <String>[];
    for (final job in done) {
      try {
        await saveOutputBytes(
          bytes: job.outputBytes!,
          filename: job.outputName ?? '${job.name}.out',
          mimeType: mimeTypeOf(job.outputName ?? job.name),
          directory: outputDirectory,
        );
        ok++;
      } catch (e) {
        failures.add('${job.name}：$e');
      }
    }

    if (failures.isEmpty) {
      statusText = '已导出 $ok 张';
      lastError = null;
    } else {
      statusText = '已导出 $ok 张，失败 ${failures.length} 张';
      lastError = failures.take(3).join('\n');
    }
    notifyListeners();
  }

  /// 导出单项。
  Future<void> exportOne(ImageJob job) async {
    if (job.outputBytes == null) return;
    try {
      await saveOutputBytes(
        bytes: job.outputBytes!,
        filename: job.outputName ?? '${job.name}.out',
        mimeType: mimeTypeOf(job.outputName ?? job.name),
        directory: outputDirectory,
      );
      statusText = '已导出 ${job.outputName}';
      lastError = null;
    } catch (e) {
      lastError = '导出失败：$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }
}

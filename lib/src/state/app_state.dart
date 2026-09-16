import 'dart:async';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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

  /// 已完成的张数（用于「处理中 3/10」这类文案）
  int processedCount = 0;

  /// 本批次总张数
  int batchTotal = 0;

  /// 状态栏文案
  String statusText = '';

  /// 最近一次处理的错误提示
  String? lastError;

  /// 当前选中的项（用于预览）
  String? selectedJobId;

  /// 预估总输入体积，用于内存提示
  int get totalInputBytes => jobs.fold(0, (sum, j) => sum + j.byteSize);

  /// 当前仍在内存中持有的原始字节总量。
  ///
  /// 原生端导入后会释放原始字节，因此这个值通常远小于 [totalInputBytes]；
  /// 两者的差值就是「按路径按需读取」省下来的常驻内存。
  int get residentInputBytes =>
      jobs.fold(0, (sum, j) => sum + (j.hasBytesInMemory ? j.byteSize : 0));

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

  /// 当前选中的证件照规格
  PresetDto? get selectedPreset {
    final id = settings.presetId;
    if (id == null) return null;
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 规格规定的输出宽度（未选规格时为 null）
  int? get presetWidthPx => selectedPreset?.widthPx;

  /// 规格规定的输出高度（未选规格时为 null）
  int? get presetHeightPx => selectedPreset?.heightPx;

  /// 已导入且可处理的项
  bool get hasJobs => jobs.isNotEmpty;

  /// 主操作「开始处理」是否可点。
  ///
  /// 单独抽成 getter 而不是在界面里写布尔表达式：处理状态一旦异常残留，
  /// 用户会彻底失去重新处理的能力，因此这个判断必须只有一处定义、便于审查。
  bool get canProcess => hasJobs && !processing;

  /// 处理中的进度文案，如「处理中 3/10」。
  String get progressLabel =>
      batchTotal == 0 ? '处理中' : '处理中 $processedCount/$batchTotal';

  Timer? _previewDebounce;

  /// 预览请求序号。
  ///
  /// 预览是异步的（先让出一帧把加载态画出来，再同步跑内核），
  /// 因此可能出现「上一次还没算完，参数又变了」。用序号丢弃过期结果，
  /// 避免界面被旧预览覆盖。
  int _previewToken = 0;

  /// 预览防抖时长。
  ///
  /// 滑杆拖动期间会持续触发参数变更，逐次跑内核会造成明显卡顿；
  /// 等待短暂停顿后再生成一次即可。拖动手感对延迟敏感，因此取值偏短。
  static const Duration _previewDebounceDelay = Duration(milliseconds: 220);

  /// 列表缩略图的长边。够清晰即可，重点是足够小以常驻内存。
  static const int _thumbnailLongSide = 160;

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
        await _registerJob(
          ImageJob(
            // 用「时间戳 + 序号」做标识：文件名可能重复，不能作为唯一键
            id: '${DateTime.now().microsecondsSinceEpoch}_${jobs.length}',
            name: f.name,
            byteSize: bytes.length,
            bytes: bytes,
            sourcePath: isWebPlatform ? null : f.path,
          ),
          bytes,
        );
        added++;
      }
      statusText = '已导入 $added 张图片';
      syncCropBox();
      schedulePreview();
    } catch (e) {
      lastError = '导入失败：${_readableError(e)}';
    }
    notifyListeners();
  }

  /// 添加预先读好的字节（供拖拽导入使用）。
  Future<void> addBytes(String name, Uint8List bytes, {String? path}) async {
    await _registerJob(
      ImageJob(
        id: '${DateTime.now().microsecondsSinceEpoch}_${jobs.length}',
        name: name,
        byteSize: bytes.length,
        bytes: bytes,
        sourcePath: path,
      ),
      bytes,
    );
    statusText = '已导入 1 张图片';
    syncCropBox();
    schedulePreview();
    notifyListeners();
  }

  /// 登记一项：探测基础信息 + 生成列表缩略图，随后在原生端释放原始字节。
  ///
  /// **这是本应用最大的一处内存节省**。原因有二：
  /// 1. 原始字节是最大的常驻占用项（一批 20 张 12MP 照片可达上百 MB）；
  /// 2. 列表若要显示缩略图，原先必须把整张原图交给解码器再缩到 46px，
  ///    每个可见项都会临时分配几十 MB，滚动时反复发生。
  ///
  /// 探测或缩略图失败都不阻断导入：前者只是缺少尺寸信息，
  /// 后者的界面有占位图标，都不该让用户导不进图片。
  ///
  /// 注意：内核接口是同步的（为兼容非 HTTPS 部署而关闭了 FRB 异步），
  /// 因此这里不写 await。
  Future<void> _registerJob(ImageJob job, Uint8List bytes) async {
    try {
      job.info = probeImage(bytes: bytes, filename: job.name);
    } catch (_) {
      job.info = null;
    }
    job.thumbnailBytes = _makeThumbnail(bytes, job.name);
    // 原生端从这里开始不再持有原始字节，需要时按路径读回
    job.releaseBytes();
    jobs.add(job);
    selectedJobId ??= job.id;
  }

  /// 生成列表缩略图（长边约 160px 的 JPEG）。
  ///
  /// 复用内核的预览能力而不是另写一套缩放逻辑，保证与成品同源。
  /// 失败返回 null，界面回退到占位图标。
  Uint8List? _makeThumbnail(Uint8List bytes, String filename) {
    try {
      return makePreview(
        bytes: bytes,
        filename: filename,
        options: const ProcessOptionsDto(),
        maxSide: _thumbnailLongSide,
      );
    } catch (_) {
      return null;
    }
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
    processedCount = 0;
    batchTotal = 0;
    statusText = '';
    lastError = null;
    notifyListeners();
  }

  void selectJob(String id) {
    if (selectedJobId == id) return;
    selectedJobId = id;
    // 换图后取景框比例可能与当前规格不一致，需要同步一次
    syncCropBox();
    schedulePreview();
    notifyListeners();
  }

  /// 关闭错误提示条。
  ///
  /// 单次失败不该长期占据界面顶部——错误条会挤压可用高度，
  /// 而且会让用户以为问题一直存在。
  void clearLastError() {
    if (lastError == null) return;
    lastError = null;
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
    }
    statusText = '参数已变更，需重新处理';
    notifyListeners();
  }

  /// 设置变更 + 立即刷新预览（供界面滑杆等高频操作调用）。
  void settingsChanged() {
    markResultsStale();
    syncCropBox();
    schedulePreview();
  }

  /// 切换证件照规格 / 裁剪模式。
  ///
  /// 单独收口是因为这两处会让**取景框比例**失效：先同步比例再刷新，
  /// 否则界面上的框与内核实际裁剪的区域会短暂不一致。
  void cropModeChanged(CropMode mode) {
    settings.cropMode = mode;
    settingsChanged();
  }

  /// 选择证件照规格预设。
  void selectPreset(String? presetId) {
    settings.cropMode = presetId == null ? CropMode.none : CropMode.preset;
    settings.presetId = presetId;
    settingsChanged();
  }

  /// 设置自定义输出像素。
  void setCustomSize({int? width, int? height}) {
    if (width != null && width > 0) settings.customWidth = width;
    if (height != null && height > 0) settings.customHeight = height;
    settingsChanged();
  }

  /// 选择标准底色。
  void selectBackgroundColor(int red, int green, int blue) {
    settings.backgroundColor =
        Color.fromARGB(255, red.clamp(0, 255), green.clamp(0, 255), blue.clamp(0, 255));
    settingsChanged();
  }

  // ------------------------------------------------------------ 裁剪取景

  /// 当前生效的裁剪框，必要时按最新规格比例重建。
  ///
  /// 用「框体实际像素宽高比」判断是否需要重建，而不是依赖调用方在每个
  /// 变更入口都记得重建——漏掉任何一条路径，界面上的框与内核实际裁剪的
  /// 区域就会脱节。返回 null 表示当前不需要裁剪（或缺少图片尺寸信息，
  /// 此时交给内核按规格比例自动构图）。
  CropBox? syncCropBox({bool refit = false}) {
    final job = selectedJob;
    if (job == null) return null;
    final aspect = settings.outputAspect(presetWidthPx, presetHeightPx);
    if (aspect == null) return null;
    final info = job.info;
    if (info == null || info.width == 0 || info.height == 0) return null;

    final box = job.cropBox;
    if (refit || box == null) {
      job.cropBox = CropBox.fitted(
        imageWidth: info.width,
        imageHeight: info.height,
        aspect: aspect,
      );
      return job.cropBox;
    }
    final actual = (box.width * info.width) / (box.height * info.height);
    if ((actual - aspect).abs() > 1e-3) {
      job.cropBox = box.withAspect(
        aspect: aspect,
        imageWidth: info.width,
        imageHeight: info.height,
      );
    }
    return job.cropBox;
  }

  /// 恢复默认取景：重新取「能放下的最大居中框」。
  void resetCropBox() {
    syncCropBox(refit: true);
    settingsChanged();
  }

  /// 更新选中图片的取景框。
  ///
  /// [live] 为 true 时表示拖动过程中高频调用，只刷新预览；
  /// 为 false（拖动结束）时把已处理结果标记为失效，提示用户需要重新处理。
  void updateCropBox(CropBox box, {bool live = false}) {
    final job = selectedJob;
    if (job == null) return;
    job.cropBox = box;
    if (live) {
      schedulePreview();
      notifyListeners();
    } else {
      settingsChanged();
    }
  }

  /// 拖动结束时的收口。
  ///
  /// **刻意不接收取景框参数**：拖动过程中每一次移动都已经通过
  /// [updateCropBox] 写入了最新值，若在这里再传一个调用方在 build 期捕获的框，
  /// 就会把用户最后一次调整覆盖回旧值——表现是「松手后框自己跳回原处」，
  /// 这是必须从源头避免的一类竞态，因此把接口设计成拿不到旧值。
  void commitCropBox() => settingsChanged();

  // ---------------------------------------------------------------- 预览

  /// 防抖生成预览。
  void schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(_previewDebounceDelay, () {
      unawaited(refreshPreview());
    });
  }

  /// 为选中项生成预览图。
  ///
  /// 内核调用是同步的，会一路占满主线程，因此这里先让出一帧把加载态画出来，
  /// 再执行计算——否则用户只感觉到一次无反馈的卡顿，看不到任何进度提示。
  /// 预览图很小（长边 900px），且内核会先降采样再抠图，单次耗时在百毫秒量级。
  Future<void> refreshPreview() async {
    _previewDebounce?.cancel();
    final token = ++_previewToken;
    // 批量处理期间不做预览：两者都是同步计算，互相抢占主线程只会都变慢。
    // 批处理结束时（processAll 的 finally）会重新安排一次预览。
    if (processing) return;
    final job = selectedJob;
    if (job == null) return;
    if (!settings.isEffective) {
      // 没有任何处理动作时直接展示原图，省去一次内核调用
      job.previewBytes = null;
      job.previewRevision++;
      job.previewLoading = false;
      notifyListeners();
      return;
    }

    final box = syncCropBox();
    final options = settings.toDto(
      cropBox: box,
      presetWidthPx: presetWidthPx,
      presetHeightPx: presetHeightPx,
    );

    job.previewLoading = true;
    notifyListeners();
    await SchedulerBinding.instance.endOfFrame;
    // 让出期间可能又有新的预览请求，此时本次结果已经过期，直接放弃
    if (token != _previewToken) return;

    try {
      // 原生端原始字节不在内存里，按路径读回；读完即用即弃，不回填缓存
      final source = await job.loadBytes();
      if (token != _previewToken) return;
      job.previewBytes = makePreview(
        bytes: source,
        filename: job.name,
        options: options,
        maxSide: 900,
      );
      lastError = null;
    } catch (e) {
      job.previewBytes = null;
      lastError = '预览失败：${_readableError(e)}';
    } finally {
      // 版本号自增，强制界面重建图像组件，避免字节数相同导致画面不刷新
      job.previewRevision++;
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
  /// 这里的 `try/finally` 是**语义上的硬约束**：`processing` 一旦没有复位，
  /// 主操作按钮会被永久禁用，用户就再也处理不了任何图片。
  /// 因此所有可能抛异常的准备工作（含参数转换）都必须落在 try 之内。
  Future<void> processAll() async {
    if (processing || jobs.isEmpty) return;
    if (!settings.isEffective) {
      lastError = '请先选择至少一项处理方式（裁剪、换背景或限制体积）';
      notifyListeners();
      return;
    }

    var targets = const <ImageJob>[];
    var finished = 0;
    var ok = 0;
    var failed = 0;

    // 注意：`processing = true` 也放在 try 之内。
    // 它一旦为 true 而没有被复位，主操作按钮会被永久禁用，用户再也处理不了任何图片；
    // 因此从置位那一刻起的所有步骤（含列表复制、参数转换）都必须受 finally 保护。
    try {
      processing = true;
      progress = 0;
      processedCount = 0;
      lastError = null;
      targets = List<ImageJob>.from(jobs);
      batchTotal = targets.length;
      for (final j in targets) {
        j.status = JobStatus.processing;
        j.error = null;
      }
      notifyListeners();

      // 裁剪框是每张图各自的，因此参数需要逐张构造，不能整批共用一个
      final presetW = presetWidthPx;
      final presetH = presetHeightPx;
      final aspect = settings.outputAspect(presetW, presetH);

      for (final job in targets) {
        try {
          // 原生端原始字节不在内存里：逐张按路径读回，处理完即释放。
          // 这样峰值内存只与单张图片同量级，而不是与整批同量级。
          final source = await job.loadBytes();
          final info = job.info;
          final box = job.cropBox ??
              CropBox.fitted(
                imageWidth: info?.width ?? 0,
                imageHeight: info?.height ?? 0,
                aspect: aspect ?? 1,
              );
          final r = processImage(
            bytes: source,
            filename: job.name,
            options: settings.toDto(
              cropBox: settings.cropMode == CropMode.none ? null : box,
              presetWidthPx: presetW,
              presetHeightPx: presetH,
            ),
          );
          job.outputBytes = r.bytes;
          job.outputName = _outputNameFor(job, r);
          job.result = r;
          job.status = JobStatus.done;
          ok++;
        } catch (e) {
          job.error = _readableError(e);
          job.status = JobStatus.failed;
          failed++;
        }
        finished++;
        processedCount = finished;
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
          j.error = _readableError(e);
        }
      }
    } finally {
      processing = false;
      notifyListeners();
      // 处理结束后把预览对齐到最新结果：否则界面仍停留在处理前的画面，
      // 用户会误以为「点了没反应」
      schedulePreview();
    }
  }

  /// 把内核抛出的异常转成可读文案。
  ///
  /// FRB 会把 `PicProError` 映射为带类型信息的 Dart 异常，
  /// 直接 toString 会把内部结构暴露给用户，因此做一次收敛。
  String _readableError(Object e) {
    final s = e.toString();
    // 去掉 "PicProError(" 之类的前缀包装，保留真正可读的说明
    final idx = s.indexOf(':');
    return idx > 0 && idx < 40 ? s.substring(idx + 1).trim() : s;
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

    // 原生端未选目录时先问一次，而不是每张都弹一次对话框——
    // 批量导出时反复弹窗会让用户以为程序失控
    if (canChooseOutputDirectory && outputDirectory == null) {
      await chooseOutputDir();
      if (outputDirectory == null) {
        lastError = '未选择输出目录，已取消导出';
        notifyListeners();
        return;
      }
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
        failures.add('${job.name}：${_readableError(e)}');
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
      lastError = '导出失败：${_readableError(e)}';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }
}

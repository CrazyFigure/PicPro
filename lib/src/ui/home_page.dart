import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../services/file_io.dart';
import '../state/app_state.dart';
import 'job_list.dart';
import 'param_panel.dart';
import 'preview_pane.dart';
import 'widgets.dart';

/// 主工作台。
///
/// 宽屏为三栏（列表 / 预览 / 参数），窄屏（手机与窄窗口）改为顶部切换，
/// 保证在不同窗口尺寸下都可用，而不是把三栏硬挤在一起。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 窄屏下的当前页签：0 图片 1 预览 2 参数
  int _narrowTab = 0;

  static const double _wideBreakpoint = 1000;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: Row(
          children: [
            const _BrandMark(),
            const SizedBox(width: 10),
            const Text('PicPro', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '批量压缩 · 换背景 · 转格式 · 证件照裁剪',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (canChooseOutputDirectory)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: OutlinedButton.icon(
                onPressed: state.chooseOutputDir,
                icon: const Icon(Icons.folder_outlined, size: 16),
                label: Text(
                  state.outputDirectory == null ? '输出目录' : '已选目录',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              style: appTonalButtonStyle(),
              onPressed: state.processing ? null : state.importFiles,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('导入图片', style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          if (state.lastError != null)
            _ErrorBar(
              text: state.lastError!,
              onDismiss: state.clearLastError,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                return wide ? _wideLayout() : _narrowLayout();
              },
            ),
          ),
          const _ActionBar(),
        ],
      ),
    );
  }

  /// 宽屏三栏布局。
  Widget _wideLayout() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 30, child: JobList()),
          SizedBox(width: 12),
          Expanded(flex: 42, child: PreviewPane()),
          SizedBox(width: 12),
          SizedBox(width: 336, child: ParamPanel()),
        ],
      ),
    );
  }

  /// 窄屏：页签切换，避免三栏互相挤压。
  Widget _narrowLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppSegmented(
                  options: const ['图片', '预览', '参数'],
                  index: _narrowTab,
                  compact: false,
                  onChanged: (v) => setState(() => _narrowTab = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: switch (_narrowTab) {
              0 => const JobList(),
              1 => const PreviewPane(),
              _ => const ParamPanel(),
            },
          ),
        ],
      ),
    );
  }
}

/// 应用标识：一个渐变小方块，替代默认的纯文字标题。
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTokens.primaryHover, AppTokens.primaryPressed],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(Icons.auto_awesome_mosaic, size: 14, color: Colors.white),
    );
  }
}

/// 错误条：展示最近一次失败原因，并提供关闭入口。
///
/// 错误若不显示，用户只会看到「点了没反应」；若不能关闭，
/// 一次偶发失败会长期占据界面顶部。两者都必须处理好。
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.text, required this.onDismiss});

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTokens.danger.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: AppTokens.danger.withValues(alpha: 0.2)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: AppTokens.danger, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            iconSize: 15,
            tooltip: '关闭提示',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// 底部操作栏：进度 + 状态 + 主操作。
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final done = state.completedJobs.length;

    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        border: Border(top: BorderSide(color: AppTokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(child: _StatusArea(state: state, theme: theme)),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: (!state.hasJobs || state.processing || done == 0)
                ? null
                : state.exportAll,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: Text(
              done == 0 ? '导出' : '导出 $done 张',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          BusyFilledButton(
            label: '开始处理',
            busyLabel: state.progressLabel,
            busy: state.processing,
            icon: Icons.play_arrow_rounded,
            onPressed: state.canProcess ? state.processAll : null,
          ),
        ],
      ),
    );
  }
}

/// 左侧状态区：处理中显示进度条，否则显示状态文案。
class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.state, required this.theme});

  final AppState state;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (state.processing) {
      return Row(
        children: [
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                // 进度为 0 时用不确定态，避免长时间停在 0% 看起来像卡死
                value: state.progress == 0 ? null : state.progress,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(state.progress * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    final text = state.statusText.isEmpty
        ? (state.hasJobs ? '待处理 ${state.jobs.length} 张' : '先导入图片')
        : state.statusText;

    return Row(
      children: [
        _StatusDot(text: text, hasJobs: state.hasJobs, done: state.completedJobs.length),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 状态圆点：把「就绪 / 待处理 / 已完成」这类状态用颜色先表达出来。
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.text, required this.hasJobs, required this.done});

  final String text;
  final bool hasJobs;
  final int done;

  @override
  Widget build(BuildContext context) {
    final color = !hasJobs
        ? AppTokens.textTertiary
        : text.contains('失败')
            ? AppTokens.danger
            : done > 0
                ? AppTokens.success
                : AppTokens.warning;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

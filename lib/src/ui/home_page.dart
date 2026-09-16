import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../services/file_io.dart';
import '../state/app_state.dart';
import 'job_list.dart';
import 'param_panel.dart';
import 'preview_pane.dart';

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
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('PicPro', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            Text(
              '批量压缩 · 换背景 · 转格式 · 证件照裁剪',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (canChooseOutputDirectory)
            TextButton.icon(
              onPressed: state.chooseOutputDir,
              icon: const Icon(Icons.folder_outlined, size: 17),
              label: Text(
                state.outputDirectory == null ? '输出目录' : '已选目录',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            onPressed: state.processing ? null : state.importFiles,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
            label: const Text('导入图片', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          if (state.lastError != null) _ErrorBar(text: state.lastError!),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideBreakpoint;
                return wide ? _wideLayout() : _narrowLayout();
              },
            ),
          ),
          _ActionBar(),
        ],      ),
    );
  }

  /// 宽屏三栏布局。
  Widget _wideLayout() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 30, child: JobList()),
          SizedBox(width: 12),
          Expanded(flex: 42, child: PreviewPane()),
          SizedBox(width: 12),
          SizedBox(width: 330, child: ParamPanel()),
        ],
      ),
    );
  }

  /// 窄屏：页签切换，避免三栏互相挤压。
  Widget _narrowLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('图片', style: TextStyle(fontSize: 13))),
                ButtonSegment(value: 1, label: Text('预览', style: TextStyle(fontSize: 13))),
                ButtonSegment(value: 2, label: Text('参数', style: TextStyle(fontSize: 13))),
              ],
              selected: {_narrowTab},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _narrowTab = v.first),
            ),
          ),
          const SizedBox(height: 8),
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

/// 错误条：展示最近一次失败原因。
class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTokens.danger.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: AppTokens.danger),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (state.processing) ...[
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: state.progress == 0 ? null : state.progress,
                  minHeight: 5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${(state.progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
          ] else
            Expanded(
              child: Text(
                state.statusText.isEmpty
                    ? (state.hasJobs ? '待处理 ${state.jobs.length} 张' : '先导入图片')
                    : state.statusText,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (state.processing) const Spacer(),
          const SizedBox(width: 12),
          TextButton(
            onPressed: (!state.hasJobs || state.processing || done == 0)
                ? null
                : state.exportAll,
            child: Text(done == 0 ? '导出' : '导出 $done 张'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: (!state.hasJobs || state.processing) ? null : state.processAll,
            child: const Text('开始处理'),
          ),
        ],
      ),
    );
  }
}

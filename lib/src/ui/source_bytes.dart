import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';

/// 按需载入原图字节的构建器。
///
/// **为什么需要它**：原生端导入时会释放原始字节以降低常驻内存
/// （一批 20 张 12MP 照片可达上百 MB），因此「原图」「构图」这类
/// 确实需要全分辨率像素的视图，不能假设字节一直在手边，必须用时读回。
///
/// **生命周期是自动的**：字节只存活在本组件内，切换到别的页签时组件被销毁，
/// 字节随之成为垃圾回收的对象，不需要调用方显式释放——
/// 显式释放很容易漏掉某条退出路径，反而造成「以为省了其实没省」。
class SourceBytesBuilder extends StatefulWidget {
  const SourceBytesBuilder({
    super.key,
    required this.job,
    required this.builder,
  });

  final ImageJob job;

  /// 字节就绪后构建真正的视图
  final Widget Function(BuildContext context, Uint8List bytes) builder;

  @override
  State<SourceBytesBuilder> createState() => _SourceBytesBuilderState();
}

class _SourceBytesBuilderState extends State<SourceBytesBuilder> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SourceBytesBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了图片就必须重新载入，否则会把上一张的像素画到这一张上
    if (oldWidget.job.id != widget.job.id) {
      _bytes = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await widget.job.loadBytes();
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is StateError ? e.message : '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) return widget.builder(context, bytes);
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF3),
        borderRadius: BorderRadius.circular(AppTokens.radiusSmall),
        border: Border.all(color: AppTokens.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.image_not_supported_outlined,
                  size: 26, color: AppTokens.danger),
              const SizedBox(height: 8),
              Text(
                _error ?? '无法读取原图',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('重试', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

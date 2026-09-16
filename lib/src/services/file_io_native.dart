import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'filename.dart';

// 原生端（Windows / Android）文件读写实现。

/// 文件选择器的过滤条件。
///
/// 同时给 extensions 与 mimeTypes：桌面端主要依赖 extensions，
/// Android 走 SAF 时部分机型更依赖 mimeTypes，两者都给兼容性最好。
XTypeGroup get _imageGroup => XTypeGroup(
      label: '图片',
      extensions: const [
        'png',
        'jpg',
        'jpeg',
        'gif',
        'svg',
        'webp',
        'bmp',
        'tif',
        'tiff',
      ],
      mimeTypes: const [
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/svg+xml',
        'image/webp',
        'image/bmp',
        'image/tiff',
      ],
    );

Future<List<XFile>> pickImageFiles() async {
  final files = await openFiles(acceptedTypeGroups: [_imageGroup]);
  return files;
}

bool get canChooseOutputDirectory => true;

Future<String?> chooseOutputDirectory() =>
    getDirectoryPath(confirmButtonText: '选择输出目录');

Future<String> saveOutputBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? directory,
}) async {
  // 未指定目录时当场询问，避免把字节写到一个用户不知道的位置
  final dir = directory ?? await chooseOutputDirectory();
  if (dir == null) {
    throw StateError('未选择输出目录');
  }
  final target = File(p.join(dir, sanitizeFileName(filename)));
  // 目录可能已被外部删除，递归创建以保证写入成功
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

/// 按路径读回文件字节；读取失败返回 null 而不是抛异常。
///
/// 不抛异常是刻意的：调用方（预览 / 处理）会在拿不到字节时给出
/// 明确文案，比起让一个底层 IO 异常穿透到界面更可控。
Future<Uint8List?> readFileBytes(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    // 文件被删除、移动，或 Android 上路径不再可用（SAF 临时副本被清理）
    return null;
  }
}

/// 原生端可以从磁盘读回文件，因此导入后允许释放原始字节。
bool get canReloadFromDisk => true;

bool get isWebPlatform => false;

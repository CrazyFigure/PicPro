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

bool get isWebPlatform => false;

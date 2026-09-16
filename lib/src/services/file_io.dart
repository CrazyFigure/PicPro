import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

// 三端文件读写门面。
//
// 平台差异集中在两个实现文件里，业务代码只依赖本文件：
// - 原生端（Windows/Android）：可选择输出目录，批量写入本地文件；
// - Web 端：浏览器不允许指定目录，只能逐个触发下载。
import 'file_io_native.dart' if (dart.library.js_interop) 'file_io_web.dart' as impl;

/// 文件名清理工具，供上层拼装输出文件名时复用。
export 'filename.dart' show sanitizeFileName;

/// 支持的输入扩展名。与 Rust 内核的格式识别能力保持一致。
const List<String> kSupportedExtensions = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'svg',
  'webp',
  'bmp',
  'tif',
  'tiff',
];

/// 弹出文件选择器，支持多选。
Future<List<XFile>> pickImageFiles() => impl.pickImageFiles();

/// 当前平台是否支持让用户指定输出目录。
///
/// Web 端恒为 false，界面据此隐藏「输出目录」相关控件，
/// 而不是展示一个点了没反应的按钮。
bool get canChooseOutputDirectory => impl.canChooseOutputDirectory;

/// 让用户选择输出目录，取消返回 null。
Future<String?> chooseOutputDirectory() => impl.chooseOutputDirectory();

/// 保存输出字节。
///
/// 原生端写入 `directory/filename` 并返回完整路径；
/// Web 端触发浏览器下载并返回文件名。
/// `directory` 在 Web 端被忽略。
Future<String> saveOutputBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? directory,
}) =>
    impl.saveOutputBytes(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      directory: directory,
    );

/// 是否运行在 Web 端。
bool get isWebPlatform => impl.isWebPlatform;

/// 根据扩展名推断 MIME 类型，供 Web 端 Blob 与下载使用。
String mimeTypeOf(String filename) {
  final dot = filename.lastIndexOf('.');
  final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'tif':
    case 'tiff':
      return 'image/tiff';
    case 'svg':
      return 'image/svg+xml';
    default:
      // 未知类型交给浏览器嗅探，不猜测错误的具体类型
      return 'application/octet-stream';
  }
}

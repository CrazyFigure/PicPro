import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

// Web 端文件读写实现。
//
// 浏览器不允许网页指定本地输出目录，因此：
// - 选文件走标准的 <input type="file">（由 file_selector 封装）；
// - 保存只能逐个触发下载，无法批量写入某个文件夹。
// 这一限制通过 canChooseOutputDirectory 暴露给界面，避免展示无效控件。

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

Future<List<XFile>> pickImageFiles() => openFiles(acceptedTypeGroups: [_imageGroup]);

bool get canChooseOutputDirectory => false;

/// Web 端无法选择输出目录，恒返回 null。
Future<String?> chooseOutputDirectory() async => null;

Future<String> saveOutputBytes({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? directory,
}) async {
  // XFile.saveTo 在 Web 端会创建一个临时 <a download> 并触发下载，
  // 因此这里传入的 filename 就是浏览器另存为的默认文件名。
  final file = XFile.fromData(bytes, name: filename, mimeType: mimeType);
  await file.saveTo(filename);
  return filename;
}

bool get isWebPlatform => true;

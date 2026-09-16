import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpro/src/models.dart';

/// 原始字节的生命周期测试。
///
/// 这一层是**常驻内存的主要来源**：一张 12MP 照片在解码前就有数 MB，
/// 原生端一批 20 张可达上百 MB。因此「导入后释放、需要时按路径读回」
/// 这条规则的每个边界都必须被钉住——一旦某条路径漏了释放，
/// 省内存就名存实亡，而且从界面上完全看不出来。
void main() {
  group('ImageJob 字节生命周期', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('picpro_job_test');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('原生端：释放后能按路径原样读回', () async {
      final f = File('${dir.path}/a.bin');
      await f.writeAsBytes([1, 2, 3, 4]);
      final job = ImageJob(
        id: 'x',
        name: 'a.png',
        byteSize: 4,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        sourcePath: f.path,
      );

      expect(job.hasBytesInMemory, isTrue);
      job.releaseBytes();
      expect(job.hasBytesInMemory, isFalse, reason: '有路径时释放必须真的丢掉字节');

      expect(await job.loadBytes(), [1, 2, 3, 4]);
    });

    test('读回后不回填缓存，否则省内存名存实亡', () async {
      final f = File('${dir.path}/b.bin');
      await f.writeAsBytes([7, 7, 7]);
      final job = ImageJob(
        id: 'y',
        name: 'b.png',
        byteSize: 3,
        sourcePath: f.path,
      );

      await job.loadBytes();
      expect(
        job.hasBytesInMemory,
        isFalse,
        reason: '按需读回的字节用完应可回收，不能被缓存住',
      );
    });

    test('Web 端语义：没有路径时释放是空操作', () {
      final job = ImageJob(
        id: 'z',
        name: 'c.png',
        byteSize: 2,
        bytes: Uint8List.fromList([9, 9]),
      );
      job.releaseBytes();
      expect(
        job.hasBytesInMemory,
        isTrue,
        reason: 'Web 端没有可访问的路径，释放后无法恢复，因此必须保留',
      );
    });

    test('既无内存字节也无路径时给出可读错误而非崩溃', () async {
      final job = ImageJob(id: 'w', name: 'd.png', byteSize: 0);
      await expectLater(job.loadBytes(), throwsA(isA<StateError>()));
    });

    test('文件已被删除时给出可读错误', () async {
      final job = ImageJob(
        id: 'v',
        name: 'e.png',
        byteSize: 0,
        sourcePath: '${dir.path}/not-there.png',
      );
      await expectLater(job.loadBytes(), throwsA(isA<StateError>()));
    });

    test('源体积不依赖字节是否还在内存里', () {
      final job = ImageJob(id: 'u', name: 'f.png', byteSize: 12345);
      job.releaseBytes();
      expect(job.sourceSize, 12345);
      expect(job.sourceSizeLabel, '12.1 KB');
    });
  });

  group('ImageJob 结果重置', () {
    test('重置只清结果，不动源信息与取景框', () {
      final job = ImageJob(id: 'r', name: 'g.png', byteSize: 10);
      job.status = JobStatus.done;
      job.outputBytes = Uint8List.fromList([1]);
      job.outputName = 'g_picpro.jpg';
      job.error = '旧错误';

      job.resetResult();

      expect(job.status, JobStatus.pending);
      expect(job.outputBytes, isNull);
      expect(job.outputName, isNull);
      expect(job.error, isNull);
      expect(job.sourceSize, 10, reason: '源体积是导入时记录的事实，不应被清掉');
    });
  });
}

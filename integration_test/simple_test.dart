import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picpro/main.dart';
import 'package:picpro/src/rust/api/image_api.dart';
import 'package:picpro/src/rust/frb_generated.dart';

/// 集成测试：验证 FFI 内核已正确加载且界面可正常渲染。
///
/// 这类测试必须跑在真实设备/桌面上——内核是动态库，纯 Dart 单元测试
/// 环境无法加载它，因此放在 integration_test 而不是 test 目录。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('内核可调用并返回版本号', (tester) async {
    final version = coreVersion();
    expect(version.isNotEmpty, isTrue);
  });

  testWidgets('内核提供证件照规格预设', (tester) async {
    final presets = listPresets();
    // 一寸是最常用规格，必须存在且像素与权威规格一致
    final one = presets.firstWhere((p) => p.id == 'size_1cun');
    expect(one.widthPx, 295);
    expect(one.heightPx, 413);
  });

  testWidgets('应用可启动并渲染主界面', (tester) async {
    await tester.pumpWidget(const PicProApp());
    await tester.pumpAndSettle();
    expect(find.text('PicPro'), findsOneWidget);
    expect(find.text('开始处理'), findsOneWidget);
  });
}

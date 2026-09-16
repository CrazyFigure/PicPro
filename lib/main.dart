import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/app.dart';
import 'src/rust/frb_generated.dart';
import 'src/state/app_state.dart';
import 'src/ui/home_page.dart';

/// 应用入口。
///
/// 先初始化 FFI 运行时再启动界面：内核初始化即加载动态库，
/// 若放到首帧之后，用户会先看到一个不可用的界面再突然可用。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const PicProApp());
}

/// 应用根组件。
class PicProApp extends StatelessWidget {
  const PicProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      // 预设与底色列表由内核提供，初始化是异步的，界面可先渲染骨架
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'PicPro',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomePage(),
      ),
    );
  }
}

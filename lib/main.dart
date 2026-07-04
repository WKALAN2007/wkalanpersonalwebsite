import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/photos_provider.dart';
import 'screens/main_screen.dart';

void main() {
  // 确保 Flutter 绑定已初始化（在 runApp 之前调用插件时需要）
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickDeleteApp());
}

/// 应用根组件
/// 使用 Provider 在全局注入照片状态管理
class QuickDeleteApp extends StatelessWidget {
  const QuickDeleteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PhotosProvider(),
      child: MaterialApp(
        title: '快速清理相册',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.blue,
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF1E1E1E),
          ),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

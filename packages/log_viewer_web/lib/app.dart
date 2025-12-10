import 'package:flutter/material.dart';
import 'widgets/log_viewer_content.dart';

/// 日志查看器 Web 应用
class LogViewerWebApp extends StatelessWidget {
  const LogViewerWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Log Viewer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const LogViewerContent(),
      debugShowCheckedModeBanner: false,
    );
  }
}


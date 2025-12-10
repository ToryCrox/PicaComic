import 'package:logger/logger.dart';
import 'package:log_viewer_server/log_viewer_server.dart';
import 'app.dart';

/// 日志查看器输出适配器
/// 
/// 实时将日志事件推送到 Web 服务器
class LogViewerOutput extends LogOutput {
  
  LogViewerOutput();
  
  @override
  void output(OutputEvent event) {
    // 实时推送日志事件到服务器
    LogViewerIntegration._server?.addLogFromOutputEvent(event);
  }
}

/// 日志查看器集成
/// 
/// 将日志输出到 Web 页面
class LogViewerIntegration {
  static LogViewerServer? _server;
  
  /// 初始化日志查看器服务器
  /// 
  /// 仅在桌面平台启动
  static Future<void> init() async {
    if (!App.isDesktop) {
      return; // 仅在桌面平台启动
    }
    
    try {
      _server = LogViewerServer();
      await _server!.start(port: 8080);
      
      
      // ignore: avoid_print
      print('日志查看器已启动: ${_server!.address}');
    } catch (e) {
      // ignore: avoid_print
      print('启动日志查看器失败: $e');
    }
  }
  
  /// 停止日志查看器
  static Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
  
  /// 获取服务器地址
  static String? get serverAddress => _server?.address;
}


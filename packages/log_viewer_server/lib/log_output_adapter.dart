import 'package:logger/logger.dart';
import 'log_viewer_server.dart';

/// 日志输出适配器
/// 
/// 将 logger 包的 OutputEvent 转换为 LogViewerServer 的日志条目
class LogOutputAdapter extends LogOutput {
  final LogViewerServer server;
  
  LogOutputAdapter(this.server);
  
  @override
  void output(OutputEvent event) {
    server.addLogFromOutputEvent(event);
  }
}



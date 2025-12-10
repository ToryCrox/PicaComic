import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:log_viewer_shared/log_viewer_shared.dart';
import 'api_handler.dart';
import 'log_stream.dart';
import 'web_handler.dart';

/// 日志查看器服务器
/// 
/// 管理 HTTP 服务器和日志流
class LogViewerServer {
  HttpServer? _server;
  final LogStream _logStream = LogStream();
  late final ApiHandler _apiHandler;
  late final WebHandler _webHandler;
  
  /// 服务器端口
  int _port = 8080;
  
  /// 是否正在运行
  bool get isRunning => _server != null;
  
  /// 当前端口
  int get port => _port;
  
  /// 服务器地址
  String? get address {
    if (_server == null) return null;
    return 'http://localhost:$_port';
  }
  
  LogViewerServer() {
    _apiHandler = ApiHandler(_logStream);
    _webHandler = WebHandler();
  }
  
  /// 启动服务器
  /// 
  /// [port] 指定端口号，默认为 8080
  /// 如果端口被占用，会自动尝试下一个可用端口
  Future<void> start({int port = 8080}) async {
    if (_server != null) {
      throw StateError('Server is already running');
    }
    
    _port = port;
    
    // 尝试绑定端口，如果失败则尝试下一个端口
    while (_port < 65535) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          _port,
        );
        break;
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 10048 || // Windows: Address already in use
            e.osError?.errorCode == 98) {    // Linux: Address already in use
          _port++;
          continue;
        }
        rethrow;
      }
    }
    
    if (_server == null) {
      throw StateError('Failed to bind to any port');
    }
    
    // 监听请求
    _server!.listen(_handleRequest, onError: (error) {
      print('Server error: $error');
    });
    
    // ignore: avoid_print
    print('Log Viewer Server started at http://localhost:$_port');
  }
  
  /// 停止服务器
  Future<void> stop() async {
    if (_server == null) return;
    
    _logStream.close();
    await _server!.close(force: true);
    _server = null;
    
    // ignore: avoid_print
    print('Log Viewer Server stopped');
  }
  
  /// 处理 HTTP 请求
  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    
    // 路由分发
    if (path.startsWith(ApiProtocol.apiPrefix)) {
      // API 请求
      _apiHandler.handle(request);
    } else {
      // 静态资源请求
      _webHandler.handle(request);
    }
  }
  
  /// 添加日志条目
  /// 
  /// 从 logger 包的 OutputEvent 创建日志条目
  void addLogFromOutputEvent(OutputEvent event) {
    final level = _convertLevel(event.level);
    final message = event.lines.join('\n');
    
    final entry = LogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      error: event.origin.error?.toString(),
      stackTrace: event.origin.stackTrace?.toString(),
    );
    
    _logStream.addLog(entry);
  }
  
  /// 转换 logger 包的 Level 到 LogLevel
  LogLevel _convertLevel(Level level) {
    if (level == Level.trace) return LogLevel.trace;
    if (level == Level.debug) return LogLevel.debug;
    if (level == Level.info) return LogLevel.info;
    if (level == Level.warning) return LogLevel.warning;
    if (level == Level.error) return LogLevel.error;
    if (level == Level.fatal) return LogLevel.fatal;
    return LogLevel.unknown;
  }
}


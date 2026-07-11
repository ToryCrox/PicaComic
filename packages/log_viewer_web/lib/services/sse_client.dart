import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:log_viewer_shared/log_viewer_shared.dart';

/// SSE 客户端
///
/// 在浏览器中连接 SSE 流
class SSEClient {
  html.EventSource? _eventSource;
  final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  /// 日志流
  Stream<LogEntry> get logStream => _logController.stream;

  /// 错误流
  Stream<String> get errorStream => _errorController.stream;

  /// 是否已连接
  bool get isConnected =>
      _eventSource != null &&
      _eventSource!.readyState == 1; // EventSource.OPEN = 1

  /// 连接状态
  int? get readyState => _eventSource?.readyState;

  /// 连接到服务器
  ///
  /// [baseUrl] 服务器基础 URL，例如 'http://localhost:8080'
  void connect(String baseUrl) {
    if (_eventSource != null) {
      disconnect();
    }

    final url = '$baseUrl${ApiProtocol.logsStreamPath}';

    try {
      _eventSource = html.EventSource(url);

      _eventSource!.onOpen.listen((_) {
        print('SSE connection opened');
      });

      _eventSource!.onMessage.listen((event) {
        try {
          final data = jsonDecode(event.data as String) as Map<String, dynamic>;
          final entry = LogEntry.fromJson(data);
          _logController.add(entry);
        } catch (e) {
          _errorController.add('Failed to parse log entry: $e');
        }
      });

      _eventSource!.onError.listen((error) {
        _errorController.add('SSE error: $error');
      });
    } catch (e) {
      _errorController.add('Failed to connect: $e');
    }
  }

  /// 断开连接
  void disconnect() {
    _eventSource?.close();
    _eventSource = null;
  }

  /// 关闭客户端
  void close() {
    disconnect();
    _logController.close();
    _errorController.close();
  }
}

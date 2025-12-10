import 'dart:convert';
import 'dart:io';
import 'package:log_viewer_shared/log_viewer_shared.dart';
import 'log_stream.dart';

/// API 路由处理器
/// 
/// 处理所有 API 请求
class ApiHandler {
  final LogStream _logStream;
  
  ApiHandler(this._logStream);
  
  /// 处理 HTTP 请求
  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    
    try {
      if (path == ApiProtocol.logsStreamPath) {
        await _handleLogsStream(request);
      } else if (path == ApiProtocol.logsHistoryPath) {
        await _handleLogsHistory(request);
      } else if (path == ApiProtocol.logsClearPath && request.method == 'POST') {
        await _handleLogsClear(request);
      } else if (path == ApiProtocol.statusPath) {
        await _handleStatus(request);
      } else {
        _sendError(request.response, HttpStatus.notFound, 'Not Found');
      }
    } catch (e) {
      _sendError(
        request.response,
        HttpStatus.internalServerError,
        'Internal Server Error: $e',
      );
    }
  }
  
  /// 处理 SSE 日志流请求
  Future<void> _handleLogsStream(HttpRequest request) async {
    final response = request.response;
    
    // 设置 SSE 响应头
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'text/event-stream')
      ..headers.set('Cache-Control', 'no-cache')
      ..headers.set('Connection', 'keep-alive')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..headers.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // 处理 CORS 预检请求
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    
    // 添加连接
    _logStream.addConnection(response);
    
    // 保持连接打开
    // 连接关闭时会自动从列表中移除
  }
  
  /// 处理历史日志请求
  Future<void> _handleLogsHistory(HttpRequest request) async {
    final response = request.response;
    final history = _logStream.getHistory();
    
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..headers.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // 处理 CORS 预检请求
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    
    final json = jsonEncode(
      history.map<Map<String, dynamic>>((LogEntry e) => e.toJson()).toList(),
    );
    
    response.write(json);
    await response.close();
  }
  
  /// 处理清空日志请求
  Future<void> _handleLogsClear(HttpRequest request) async {
    final response = request.response;
    
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS')
      ..headers.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // 处理 CORS 预检请求
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    
    _logStream.clear();
    
    response.write(jsonEncode({'success': true, 'message': 'Logs cleared'}));
    await response.close();
  }
  
  /// 处理状态请求
  Future<void> _handleStatus(HttpRequest request) async {
    final response = request.response;
    
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS')
      ..headers.set('Access-Control-Allow-Headers', 'Content-Type');
    
    // 处理 CORS 预检请求
    if (request.method == 'OPTIONS') {
      await response.close();
      return;
    }
    
    final status = {
      'status': 'running',
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    response.write(jsonEncode(status));
    await response.close();
  }
  
  /// 发送错误响应
  void _sendError(HttpResponse response, int statusCode, String message) {
    response
      ..statusCode = statusCode
      ..headers.set('Content-Type', 'application/json')
      ..headers.set('Access-Control-Allow-Origin', '*');
    
    response.write(jsonEncode({
      'error': message,
      'statusCode': statusCode,
    }));
    
    response.close();
  }
}


import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:log_viewer_shared/log_viewer_shared.dart';

/// 日志流管理器
/// 
/// 管理日志缓冲区和 SSE 连接
class LogStream {
  /// 日志缓冲区（最大保留数量）
  static const int maxBufferSize = 1000;
  
  /// 当前日志缓冲区
  final List<LogEntry> _buffer = [];
  
  /// SSE 连接列表
  final List<HttpResponse> _connections = [];
  
  /// 日志流控制器
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();
  
  /// 日志流
  Stream<LogEntry> get stream => _logController.stream;
  
  /// 获取历史日志
  List<LogEntry> getHistory() {
    return List.unmodifiable(_buffer);
  }
  
  /// 添加日志条目
  void addLog(LogEntry entry) {
    _buffer.add(entry);
    
    // 限制缓冲区大小
    if (_buffer.length > maxBufferSize) {
      _buffer.removeAt(0);
    }
    
    // 广播到所有连接
    _broadcastLog(entry);
    
    // 通知流控制器
    _logController.add(entry);
  }
  
  /// 清空日志
  void clear() {
    _buffer.clear();
  }
  
  /// 添加 SSE 连接
  void addConnection(HttpResponse response) {
    _connections.add(response);
    
    // 发送连接确认
    _sendSSEMessage(
      response,
      ApiProtocol.eventTypeConnected,
      jsonEncode({'message': 'Connected to log stream'}),
    );
    
    // 发送历史日志
    for (final entry in _buffer) {
      _sendSSEMessage(
        response,
        ApiProtocol.eventTypeLog,
        jsonEncode(entry.toJson()),
      );
    }
  }
  
  /// 移除 SSE 连接
  void removeConnection(HttpResponse response) {
    _connections.remove(response);
    try {
      response.close();
    } catch (e) {
      // 忽略关闭错误
    }
  }
  
  /// 广播日志到所有连接
  void _broadcastLog(LogEntry entry) {
    final message = jsonEncode(entry.toJson());
    final connectionsToRemove = <HttpResponse>[];
    
    for (final connection in _connections) {
      try {
        _sendSSEMessage(connection, ApiProtocol.eventTypeLog, message);
      } catch (e) {
        // 连接已关闭，标记为移除
        connectionsToRemove.add(connection);
      }
    }
    
    // 移除已关闭的连接
    for (final connection in connectionsToRemove) {
      _connections.remove(connection);
    }
  }
  
  /// 发送 SSE 消息
  void _sendSSEMessage(HttpResponse response, String eventType, String data) {
    try {
      response
        ..write('event: $eventType\n')
        ..write('data: $data\n\n');
      response.flush();
    } catch (e) {
      // 连接已关闭，忽略错误
    }
  }
  
  /// 关闭所有连接
  void close() {
    for (final connection in _connections) {
      try {
        connection.close();
      } catch (e) {
        // 忽略关闭错误
      }
    }
    _connections.clear();
    _logController.close();
  }
}


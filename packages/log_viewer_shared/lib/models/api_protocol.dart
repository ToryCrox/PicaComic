/// API 协议定义
/// 
/// 定义 Server 和 Web 之间的通信协议
class ApiProtocol {
  /// API 路径前缀
  static const String apiPrefix = '/api';
  
  /// SSE 日志流路径
  static const String logsStreamPath = '$apiPrefix/logs/stream';
  
  /// 历史日志路径
  static const String logsHistoryPath = '$apiPrefix/logs/history';
  
  /// 清空日志路径
  static const String logsClearPath = '$apiPrefix/logs/clear';
  
  /// 服务器状态路径
  static const String statusPath = '$apiPrefix/status';
  
  /// SSE 事件类型：新日志
  static const String eventTypeLog = 'log';
  
  /// SSE 事件类型：连接确认
  static const String eventTypeConnected = 'connected';
  
  /// SSE 事件类型：错误
  static const String eventTypeError = 'error';
}


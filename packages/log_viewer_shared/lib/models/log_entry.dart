import 'log_level.dart';

/// 日志条目模型
/// 
/// Server 和 Web 都使用这个模型进行数据交换
class LogEntry {
  /// 日志级别
  final LogLevel level;
  
  /// 日志消息
  final String message;
  
  /// 时间戳
  final DateTime timestamp;
  
  /// 可选的错误信息
  final String? error;
  
  /// 可选的堆栈跟踪
  final String? stackTrace;

  /// 构造函数
  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  /// 从 JSON 创建
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      level: LogLevel.fromString(json['level'] as String? ?? 'unknown'),
      message: json['message'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'level': level.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (error != null) 'error': error,
      if (stackTrace != null) 'stackTrace': stackTrace,
    };
  }

  @override
  String toString() {
    return '[$level] ${timestamp.toIso8601String()}: $message';
  }
}




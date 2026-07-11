/// 日志级别枚举
///
/// 与 logger 包的 Level 对应
enum LogLevel {
  /// 调试级别
  debug,

  /// 信息级别
  info,

  /// 警告级别
  warning,

  /// 错误级别
  error,

  /// 致命错误级别
  fatal,

  /// 其他级别
  trace,

  /// 未知级别
  unknown;

  /// 从字符串创建
  static LogLevel fromString(String name) {
    return LogLevel.values.firstWhere(
      (e) => e.name == name.toLowerCase(),
      orElse: () => LogLevel.unknown,
    );
  }
}

import 'dart:async';
import 'dart:math';
import 'package:pica_comic/foundation/log.dart';

/// 下载错误类型
enum DownloadErrorType {
  /// 网络错误
  network,
  
  /// 文件系统错误
  fileSystem,
  
  /// 权限错误
  permission,
  
  /// 用户取消
  canceled,
  
  /// 超时
  timeout,
  
  /// 未知错误
  unknown,
}

/// 下载错误
class DownloadError {
  /// 错误类型
  final DownloadErrorType type;

  /// 错误消息
  final String message;

  /// 原始错误对象
  final Object? originalError;

  /// 堆栈跟踪
  final StackTrace? stackTrace;

  /// 是否可重试
  final bool canRetry;

  /// 创建时间
  final DateTime createdAt;

  DownloadError({
    required this.type,
    required this.message,
    this.originalError,
    this.stackTrace,
    this.canRetry = true,
  }) : createdAt = DateTime.now();

  /// 从异常创建错误
  factory DownloadError.fromException(Object error, [StackTrace? stackTrace]) {
    final type = _analyzeError(error);
    final canRetry = type != DownloadErrorType.canceled && 
                     type != DownloadErrorType.permission;

    return DownloadError(
      type: type,
      message: error.toString(),
      originalError: error,
      stackTrace: stackTrace,
      canRetry: canRetry,
    );
  }

  /// 分析错误类型
  static DownloadErrorType _analyzeError(Object error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('cancel')) {
      return DownloadErrorType.canceled;
    }
    
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return DownloadErrorType.timeout;
    }

    if (errorStr.contains('permission') || errorStr.contains('access denied')) {
      return DownloadErrorType.permission;
    }

    if (errorStr.contains('network') || 
        errorStr.contains('socket') || 
        errorStr.contains('connection') ||
        errorStr.contains('http')) {
      return DownloadErrorType.network;
    }

    if (errorStr.contains('file') || 
        errorStr.contains('directory') || 
        errorStr.contains('path') ||
        errorStr.contains('i/o')) {
      return DownloadErrorType.fileSystem;
    }

    return DownloadErrorType.unknown;
  }

  @override
  String toString() {
    return 'DownloadError(type: $type, message: $message)';
  }
}

/// 重试策略配置
class RetryStrategyConfig {
  /// 最大重试次数
  final int maxRetries;

  /// 初始延迟（毫秒）
  final int initialDelayMs;

  /// 退避倍数
  final double backoffMultiplier;

  /// 最大延迟（毫秒）
  final int maxDelayMs;

  /// 是否使用随机抖动
  final bool useJitter;

  const RetryStrategyConfig({
    this.maxRetries = 5,
    this.initialDelayMs = 1000,
    this.backoffMultiplier = 2.0,
    this.maxDelayMs = 30000,
    this.useJitter = true,
  });

  /// 默认策略
  static const RetryStrategyConfig defaultStrategy = RetryStrategyConfig();

  /// 网络错误策略（更多重试）
  static const RetryStrategyConfig networkStrategy = RetryStrategyConfig(
    maxRetries: 10,
    initialDelayMs: 2000,
    backoffMultiplier: 1.5,
    maxDelayMs: 60000,
  );

  /// 文件系统错误策略（少量重试，快速失败）
  static const RetryStrategyConfig fileSystemStrategy = RetryStrategyConfig(
    maxRetries: 3,
    initialDelayMs: 500,
    backoffMultiplier: 1.5,
    maxDelayMs: 5000,
  );
}

/// 重试策略
class RetryStrategy {
  final RetryStrategyConfig config;
  final Random _random = Random();

  RetryStrategy({RetryStrategyConfig? config})
      : config = config ?? RetryStrategyConfig.defaultStrategy;

  /// 根据错误类型获取合适的策略
  factory RetryStrategy.forErrorType(DownloadErrorType errorType) {
    switch (errorType) {
      case DownloadErrorType.network:
      case DownloadErrorType.timeout:
        return RetryStrategy(config: RetryStrategyConfig.networkStrategy);
      
      case DownloadErrorType.fileSystem:
        return RetryStrategy(config: RetryStrategyConfig.fileSystemStrategy);
      
      case DownloadErrorType.canceled:
      case DownloadErrorType.permission:
        // 这些错误不应重试
        return RetryStrategy(config: const RetryStrategyConfig(maxRetries: 0));
      
      default:
        return RetryStrategy();
    }
  }

  /// 计算下次重试延迟
  Duration getNextDelay(int retryCount) {
    if (retryCount <= 0) {
      return Duration(milliseconds: config.initialDelayMs);
    }

    // 指数退避
    final delayMs = (config.initialDelayMs * 
        pow(config.backoffMultiplier, retryCount - 1)).toInt();

    // 限制最大延迟
    final cappedDelay = min(delayMs, config.maxDelayMs);

    // 添加随机抖动（避免惊群效应）
    if (config.useJitter) {
      final jitter = _random.nextInt((cappedDelay * 0.3).toInt());
      return Duration(milliseconds: cappedDelay + jitter);
    }

    return Duration(milliseconds: cappedDelay);
  }

  /// 是否应该重试
  bool shouldRetry(DownloadError error, int retryCount) {
    // 检查是否超过最大重试次数
    if (retryCount >= config.maxRetries) {
      return false;
    }

    // 检查错误是否可重试
    return error.canRetry;
  }
}

/// 错误处理器
class DownloadErrorHandler {
  /// 处理错误并决定是否重试
  /// 
  /// 返回 true 表示已处理并会重试，false 表示不重试
  Future<bool> handleError({
    required DownloadError error,
    required int retryCount,
    required Future<void> Function() retryAction,
    void Function(DownloadError error)? onFinalFailure,
  }) async {
    Log.e('DownloadErrorHandler: ${error.type} error - ${error.message}');

    // 获取合适的重试策略
    final strategy = RetryStrategy.forErrorType(error.type);

    // 检查是否应该重试
    if (!strategy.shouldRetry(error, retryCount)) {
      Log.e('DownloadErrorHandler: Max retries reached or error not retryable (type: ${error.type}, retries: $retryCount)');
      onFinalFailure?.call(error);
      return false;
    }

    // 计算延迟
    final delay = strategy.getNextDelay(retryCount);
    Log.i('DownloadErrorHandler: Retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/${strategy.config.maxRetries})');

    // 延迟后重试
    await Future.delayed(delay);

    try {
      await retryAction();
      Log.i('DownloadErrorHandler: Retry successful');
      return true;
    } catch (e, s) {
      // 重试失败，创建新的错误并递归处理
      final newError = DownloadError.fromException(e, s);
      return await handleError(
        error: newError,
        retryCount: retryCount + 1,
        retryAction: retryAction,
        onFinalFailure: onFinalFailure,
      );
    }
  }

  /// 批量处理多个错误（用于收集错误统计）
  Map<DownloadErrorType, int> analyzeErrors(List<DownloadError> errors) {
    final errorCounts = <DownloadErrorType, int>{};

    for (var error in errors) {
      errorCounts[error.type] = (errorCounts[error.type] ?? 0) + 1;
    }

    return errorCounts;
  }

  /// 生成错误报告
  String generateErrorReport(List<DownloadError> errors) {
    if (errors.isEmpty) {
      return 'No errors';
    }

    final errorCounts = analyzeErrors(errors);
    final buffer = StringBuffer();
    buffer.writeln('Error Summary:');
    
    for (var entry in errorCounts.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value} occurrence(s)');
    }

    buffer.writeln('\nDetailed Errors:');
    for (var i = 0; i < errors.length && i < 10; i++) {
      final error = errors[i];
      buffer.writeln('  ${i + 1}. [${error.type}] ${error.message}');
    }

    if (errors.length > 10) {
      buffer.writeln('  ... and ${errors.length - 10} more');
    }

    return buffer.toString();
  }
}

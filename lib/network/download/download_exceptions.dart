/// 下载流程中需要立即停止重试的异常。
///
/// 这类异常通常表示继续请求不会改变结果，例如服务端要求用户补充
/// 配额或积分。下载队列会保留已完成的内容，并将异常交给上层处理。
abstract class DownloadNonRetryableException implements Exception {
  const DownloadNonRetryableException();

  /// 面向日志和错误处理器的稳定错误信息。
  String get message;

  @override
  String toString() => message;
}

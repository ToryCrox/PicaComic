import '../download/download_exceptions.dart';

/// EH 原图下载需要 GP，但当前账号 GP 不足。
class EhOriginalGpRequiredException extends DownloadNonRetryableException {
  const EhOriginalGpRequiredException();

  /// EH 返回的正文可能包含 HTML 标签和不规则空白，因此统一规范化后匹配。
  static bool matchesResponseText(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final originalFilesError =
        normalized.contains('original files') &&
        normalized.contains('requires gp') &&
        normalized.contains('do not have enough');
    final imageLimitError =
        normalized.contains('you have reached the image limit') &&
        normalized.contains('do not have sufficient gp') &&
        normalized.contains('buy a download quota');
    return originalFilesError || imageLimitError;
  }

  /// 检查异常自身或其字符串描述中是否包含 EH GP 错误。
  static bool matchesError(Object? error) {
    if (error is EhOriginalGpRequiredException) return true;
    if (error == null) return false;
    return matchesResponseText(error.toString());
  }

  @override
  String get message =>
      'Downloading original files of this gallery during peak hours '
      'requires GP, and you do not have enough.';
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/download/download_error_handler.dart';
import 'package:pica_comic/network/eh_network/eh_errors.dart';

void main() {
  test('能从 HTML 正文识别 EH GP 不足错误', () {
    const html = '''
      <html><body>
        Downloading original files of this gallery during peak hours
        requires GP, and you do not have enough.
      </body></html>
    ''';

    expect(EhOriginalGpRequiredException.matchesResponseText(html), isTrue);

    final error = DownloadError.fromException(
      const EhOriginalGpRequiredException(),
      StackTrace.current,
    );
    expect(error.type, DownloadErrorType.nonRetryable);
    expect(error.canRetry, isFalse);
  });

  test('普通 HTML 错误页不会被误判为 GP 错误', () {
    const html = '<html><body>Cloudflare challenge</body></html>';

    expect(EhOriginalGpRequiredException.matchesResponseText(html), isFalse);
  });
}

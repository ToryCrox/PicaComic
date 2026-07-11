import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/image_download_queue.dart';

void main() {
  group('ImageDownloadQueue', () {
    test('最后一项失败时会等待退避重试，不会提前完成', () async {
      var attempts = 0;
      final queue = ImageDownloadQueue(
        maxConcurrentDownloads: 1,
        downloadFunction: (_) async {
          attempts++;
          if (attempts == 1) {
            throw Exception('temporary error');
          }
        },
      );
      queue.addImage(_createItem());

      final downloadFuture = queue.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(queue.isRunning, isTrue);
      expect(queue.retryingCount, 1);
      expect(queue.totalCount, 1);

      await downloadFuture;

      expect(attempts, 2);
      expect(queue.completedCount, 1);
      expect(queue.failedCount, 0);
      expect(queue.isAllCompleted, isTrue);
    });

    test('空队列不能被视为成功完成', () async {
      final queue = ImageDownloadQueue(downloadFunction: (_) async {});

      await queue.start();

      expect(queue.totalCount, 0);
      expect(queue.isAllCompleted, isFalse);
    });

    test('流式下载分块事件不会提前标记完成', () {
      const chunk = DownloadProgress(100, 101, 'url', 'path');
      const completed = DownloadProgress(100, 100, 'url', 'path');

      expect(chunk.finished, isFalse);
      expect(completed.finished, isTrue);
    });
  });
}

ImageDownloadQueueItem _createItem() {
  return ImageDownloadQueueItem(
    url: 'https://example.com/0.webp',
    episodeIndex: 0,
    imageIndex: 0,
    savePath: 'test',
    fileBaseName: '0',
  );
}

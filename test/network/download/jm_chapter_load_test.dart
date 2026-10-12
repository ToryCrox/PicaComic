import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/download/download_error_handler.dart';
import 'package:pica_comic/network/jm_network/jm_chapter_loader.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/res.dart';

void main() {
  test('JM 章节返回空数据时只请求三次并停止任务级重试', () async {
    var requests = 0;
    final delays = <Duration>[];

    try {
      await fetchJmChapterImages(89, '1481413', (chapterId) async {
        expect(chapterId, '1481413');
        requests++;
        return const Res<List<String>>.error('Exception: Empty data');
      }, waitBeforeRetry: (delay) async => delays.add(delay));
      fail('空响应必须使章节下载失败');
    } on JmChapterLoadException catch (error) {
      expect(error.episodeIndex, 89);
      expect(error.chapterId, '1481413');
      expect(DownloadError.fromException(error).canRetry, isFalse);
    }

    expect(requests, 3);
    expect(delays, [const Duration(seconds: 3), const Duration(seconds: 3)]);
  });

  test('JM 章节重试成功后保留图片链接，空图片列表仍视为失败', () async {
    var requests = 0;
    final images = await fetchJmChapterImages(2, 'chapter-2', (_) async {
      requests++;
      if (requests == 1) return const Res<List<String>>.error('timeout');
      return const Res<List<String>>(['image-url']);
    }, waitBeforeRetry: (_) async {});
    expect(images, ['image-url']);
    expect(requests, 2);

    await expectLater(
      fetchJmChapterImages(
        3,
        'chapter-3',
        (_) async => const Res<List<String>>([]),
        waitBeforeRetry: (_) async {},
      ),
      throwsA(isA<JmChapterLoadException>()),
    );
  });

  test('普通网络错误仍交由任务级重试处理', () async {
    var requests = 0;
    await expectLater(
      fetchJmChapterImages(4, 'chapter-4', (_) async {
        requests++;
        return const Res<List<String>>.error('Network timeout');
      }, waitBeforeRetry: (_) async {}),
      throwsA(isNot(isA<JmChapterLoadException>())),
    );
    expect(requests, 3);
  });

  test('未取得链接的 JM 章节仍出现在进度列表，并可单独取消', () {
    final task = JmDownloadingTask(
      const JmComicInfo(series: {1: 'chapter-1', 2: 'chapter-2'}),
      [0, 1],
      null,
      null,
      null,
      'jm-test',
    );
    task.links = {
      1: ['image-url'],
      2: [],
    };

    expect(task.unresolvedEpisodeCount, 1);
    expect(task.episodeProgress[2], (downloaded: 0, total: 0));

    task.cancelEpisode(2);
    expect(task.unresolvedEpisodeCount, 0);
    expect(task.episodeProgress.containsKey(2), isFalse);
  });
}

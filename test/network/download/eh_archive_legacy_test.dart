import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';

void main() {
  group('旧 E-Hentai 压缩包任务兼容', () {
    final gallery = Gallery(
      title: '标题',
      type: 'Manga',
      time: 'now',
      uploader: '作者',
      stars: 4.5,
      rating: '4.5',
      coverPath: 'https://ehgt.org/cover.jpg',
      tags: const {},
      comments: const [],
      auth: const {},
      favorite: false,
      link: 'https://e-hentai.org/g/1/token/',
      maxPage: '2',
      pageSize: 2,
      thumbnails: const [],
      ext: 'jpg',
      width: 100,
    );

    EhDownloadingTask restore(int savedType) {
      return EhDownloadingTask.fromMap(
        {
          'type': DownloadType.ehentai.index,
          'id': '1',
          'gallery': gallery.toJson(),
          'downloadType': savedType,
          'directory': 'eh-1',
        },
        () {},
        () {},
        () async {},
        '1',
      );
    }

    test('旧压缩包任务保留在队列中并标为不可继续', () {
      final task = restore(2);

      expect(task.archiveDownloadRemoved, isTrue);
      expect(task.userPaused, isTrue);
      expect(task.pauseReason, DownloadPauseReason.ehArchiveDownloadRemoved);
      expect(task.pauseReason!.messageKey, 'E-Hentai 压缩包下载已移除，无法继续');
      expect(task.toMap()['downloadType'], 2);
      expect(
        task.toMap()['pauseReason'],
        DownloadPauseReason.ehArchiveDownloadRemoved.name,
      );
    });

    test('旧普通逐页任务仍按普通任务恢复', () {
      final task = restore(0);

      expect(task.archiveDownloadRemoved, isFalse);
      expect(task.userPaused, isFalse);
      expect(task.pauseReason, isNull);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/comic_source/built_in/hiperdex.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloaded_item.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloading_task.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/pages/hiperdex/hiperdex_reading_data.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/image_download_queue.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';
import 'package:pica_comic/pages/hiperdex/hiperdex_adapter.dart';

/// 检查真实章号目录、旧下载迁移及章节重排后的本地定位。
void main() {
  const chapters = {'156|1006': 'Chapter 156', '155|1005': 'Chapter 155'};
  const info = ComicInfoData(
    title: 'Sample',
    sourceKey: 'hiperdex',
    comicId: 'sample',
    chapters: chapters,
  );
  HiperdexDownloadedItem legacyItem() => HiperdexDownloadedItem.fromJson({
    'comic': info.toJson(),
    'downloadedEps': [0, 1],
    'id': 'hiperdex-sample',
    'sourceName': 'HiperDEX',
  });

  test('独立类型追加在枚举末尾，旧类型序号保持不变', () {
    expect(DownloadType.other.index, 6);
    expect(DownloadType.favorite.index, 7);
    expect(DownloadType.local.index, 8);
    expect(DownloadType.hiperdex.index, 9);
    expect(DownloadType.hiperdex.toComicType(), hiperdex.key);
    expect(legacyItem(), isNot(isA<CustomDownloadedItem>()));
    expect(legacyItem().type, DownloadType.hiperdex);
    expect(legacyItem().toJson()['modelVersion'], 1);
  });

  test('旧 Custom 任务恢复为独立任务，并保留暂停、目录、链接和旧目录迁移状态', () {
    final old =
        CustomDownloadingTask(
            info,
            [0],
            () {},
            () {},
            () async {},
            'hiperdex-sample',
          )
          ..directory = 'existing-comic'
          ..userPaused = true
          ..overwriteExistingFiles = true
          ..links = {
            1: ['https://example.com/existing.webp'],
          };
    final restored = downloadingItemFromMap(
      old.toMap(),
      () {},
      () {},
      () async {},
    );
    expect(restored, isA<HiperdexDownloadingTask>());
    expect(restored, isNot(isA<CustomDownloadingTask>()));
    expect(restored.type, DownloadType.hiperdex);
    expect(restored.directory, 'existing-comic');
    expect(restored.userPaused, isTrue);
    expect(restored.overwriteExistingFiles, isTrue);
    expect(restored.links, old.links);
    expect(restored.toMap()['legacyDirectories'], isTrue);
    final second = downloadingItemFromMap(
      restored.toMap(),
      () {},
      () {},
      () async {},
    );
    expect(second.toMap()['legacyDirectories'], isTrue);
  });

  test('阅读入口和详情适配器使用独立实现', () {
    final reader = ReadingData.fromSource(
      'sample',
      'Sample',
      hiperdex,
      chapters,
    );
    expect(reader, isA<HiperdexReadingData>());
    expect(reader, isNot(isA<CustomReadingData>()));
    expect(reader.type, hiperdex.key);
    expect(reader.downloadId, 'hiperdex-sample');
    expect(reader.favoriteType.key, hiperdex.intKey);
    expect(HiperdexAdapter().dataFromDownloadedItem(legacyItem()), info);
  });

  test('倒序目录的翻章方向正确，章节和下载索引保持不变', () {
    final reader = HiperdexReadingData('sample', 'Sample', chapters)
      ..onDownloadedItemLoaded(legacyItem());
    expect(reader.eps, chapters);
    expect(reader.chapterStep, -1);
    expect(reader.adjacentEpisode(2, 1), 1);
    expect(reader.adjacentEpisode(1, -1), 2);
    expect(reader.adjacentEpisode(1, 1), isNull);
    expect(reader.adjacentEpisode(2, -1), isNull);
    expect(reader.localEpisode(1), 1);
    expect(reader.localEpisode(2), 2);

    final ascending = HiperdexReadingData('sample', 'Sample', {
      '12.5|101': 'Special',
      '12.50|102': 'Revised',
      '13|103': 'Chapter 13',
    });
    expect(ascending.chapterStep, 1);
    expect(ascending.adjacentEpisode(2, 1), 3);
    expect(ascending.adjacentEpisode(2, -1), 1);
  });

  test('独立下载类型继续找到原 other 封面文件', () async {
    final root = await Directory.systemTemp.createTemp('hiperdex-cover-');
    addTearDown(() => root.delete(recursive: true));
    final manager = DownloadManager();
    final previousPath = manager.path;
    manager.path = root.path;
    addTearDown(() => manager.path = previousPath);
    final legacy = manager.getCoverPath('hiperdex-sample', DownloadType.other)!;
    final file = File(legacy);
    await file.parent.create(recursive: true);
    await file.writeAsString('cover');
    expect(
      manager.getCoverPath('hiperdex-sample', DownloadType.hiperdex),
      legacy,
    );
  });

  test('下载队列使用真实章号而非章节位置，并能恢复任务', () async {
    final manager = DownloadManager();
    final previousPath = manager.path;
    manager.path = Directory.systemTemp.path;
    addTearDown(() => manager.path = previousPath);
    final task =
        HiperdexDownloadingTask(
            info,
            [0, 1],
            () {},
            () {},
            () async {},
            'hiperdex-sample',
          )
          ..directory = 'sample'
          ..links = {
            1: ['https://example.com/a'],
            2: ['https://example.com/b'],
          };
    manager.bindTask(task);
    final queue = _RecordingQueue();
    await task.loadImages(queue);
    expect(queue.items.map((item) => path.basename(item.savePath)), [
      'Chapter 156',
      'Chapter 155',
    ]);
    final restored = downloadingItemFromMap(
      jsonDecode(jsonEncode(task.toMap())),
      () {},
      () {},
      () async {},
    );
    expect(restored.getEpisodeDirectoryName(1), 'Chapter 156');
    expect(restored.getEpisodeDirectoryName(2), 'Chapter 155');
  });

  test('小数章号与同章号不同版本保留独立目录', () {
    const duplicate = {'12.5|101': 'Special', '12.50|102': 'Revised'};
    expect(
      hiperdexChapterDirectoryName(duplicate, '12.5|101'),
      'Chapter 12.5 - 101',
    );
    expect(
      hiperdexChapterDirectoryName(duplicate, '12.50|102'),
      'Chapter 12.5 - 102',
    );
    expect(
      hiperdexChapterDirectoryName({'156.0|103': 'Chapter 156'}, '156.0|103'),
      'Chapter 156',
    );
  });

  test('旧数字目录迁移保留图片内容，序列化后仍能定位且可重复执行', () async {
    final root = await Directory.systemTemp.createTemp('hiperdex-chapters-');
    addTearDown(() => root.delete(recursive: true));
    for (var i = 1; i <= 2; i++) {
      await Directory(path.join(root.path, '$i')).create();
      await File(path.join(root.path, '$i', '0.jpg')).writeAsString('image-$i');
    }
    final item = legacyItem();
    expect(await item.migrateChapterDirectories(root.path), isTrue);
    final restored = HiperdexDownloadedItem.fromJson(
      jsonDecode(jsonEncode(item.toJson())),
    );
    expect(restored.getEpisodeDirectoryName(1), 'Chapter 156');
    expect(
      await File(
        path.join(root.path, restored.getEpisodeDirectoryName(1), '0.jpg'),
      ).readAsString(),
      'image-1',
    );
    expect(
      await File(
        path.join(root.path, restored.getEpisodeDirectoryName(2), '0.jpg'),
      ).readAsString(),
      'image-2',
    );
    expect(await Directory(path.join(root.path, '1')).exists(), isFalse);
    expect(await restored.migrateChapterDirectories(root.path), isFalse);
  });

  test('迁移目标已有内容时不覆盖，并继续定位旧目录', () async {
    final root = await Directory.systemTemp.createTemp('hiperdex-collision-');
    addTearDown(() => root.delete(recursive: true));
    for (final name in ['1', 'Chapter 156']) {
      await Directory(path.join(root.path, name)).create();
      await File(path.join(root.path, name, '0.jpg')).writeAsString(name);
    }
    final item = legacyItem();
    await item.migrateChapterDirectories(root.path);
    expect(item.getEpisodeDirectoryName(1), '1');
    expect(await File(path.join(root.path, '1', '0.jpg')).readAsString(), '1');
    expect(
      await File(path.join(root.path, 'Chapter 156', '0.jpg')).readAsString(),
      'Chapter 156',
    );
  });

  test('新增章节后按章节 ID 重映射下载状态、目录和在线阅读索引', () {
    final item = legacyItem();
    final updated = info.copyWith(
      chapters: {'157|1007': 'Chapter 157', ...chapters},
    );
    final merged = item.withComicInfo(updated);
    expect(merged.downloadedEps, [1, 2]);
    expect(merged.getEpisodeDirectoryName(2), '1');
    expect(merged.getEpisodeDirectoryName(3), '2');
    final reader = HiperdexReadingData('sample', 'Sample', updated.chapters)
      ..downloadedEps = item.downloadedEps
      ..onDownloadedItemLoaded(item);
    expect(reader.checkEpDownloaded(1), isFalse);
    expect(reader.checkEpDownloaded(2), isTrue);
    expect(reader.localEpisode(2), 1);
    expect(reader.localEpisode(3), 2);
  });
}

/// 仅记录实际入队路径，避免测试访问站点或真实下载库。
class _RecordingQueue extends ImageDownloadQueue {
  _RecordingQueue() : super(downloadFunction: (_) async {});
  final List<ImageDownloadQueueItem> items = [];

  @override
  void addImage(ImageDownloadQueueItem item) => items.add(item);
}

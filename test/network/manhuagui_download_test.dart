import 'dart:convert';
import 'dart:io';

import '../fixtures/manhuagui/sample.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/comic_source/built_in/manhuagui.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloaded_item.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloading_task.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_reading_data.dart';
import 'package:pica_comic/pages/reader/continuous_reader_data.dart';
import 'package:pica_comic/network/res.dart';

/// 下载与阅读共用的离线测试管理器，不访问应用数据库。
class _OfflineManager extends DownloadManager {
  _OfflineManager(this.item, this.root);
  final ManhuaguiDownloadedItem item;
  final Directory root;
  @override
  Future<DownloadedItem?> getComicOrNull(String id) async => item;
  @override
  Future<String> getImageDirectory(String id, int ep) async =>
      '${root.path}/${item.getEpisodeDirectoryName(ep)}';
  @override
  Future<List<String>> getAllImageFileList(String id, int ep) async {
    final directory = Directory(await getImageDirectory(id, ep));
    return directory
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .toList();
  }
}

/// 离线测试中网络入口一旦被调用就失败。
class _NoNetworkServices implements ComicSourceServices {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('离线阅读不应调用网络服务');
}

class _NoSourceCallbacks implements ComicSourceCallbackRunner {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('离线阅读不应调用来源请求');
}

/// 注入失败响应以验证空章节会触发重试。
class _EmptyNetwork extends ManhuaguiNetwork {
  _EmptyNetwork() : super(Dio(), cacheEnabled: false);
  var calls = 0;
  @override
  Future<Res<List<String>>> pages(String id, String chapterId) async {
    calls++;
    return const Res([]);
  }
}

class _NetworkManager extends DownloadManager {
  _NetworkManager(this.network);
  final ManhuaguiNetwork network;
  @override
  T readProvider<T>(ProviderListenable<T> provider) => network as T;
}

void main() {
  test('来源的下载标识可从数字漫画 ID 生成', () {
    final old = ComicSource.sources;
    ComicSource.sources = [manhuagui];
    addTearDown(() => ComicSource.sources = old);
    expect(DownloadManager().generateId('manhuagui', '4125'), 'manhuagui-4125');
  });

  test('目录变化后从磁盘读取正确章节且不访问网络', () async {
    final root = await Directory.systemTemp.createTemp('manhuagui-offline-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/chapter-20');
    await directory.create();
    final image = File('${directory.path}/0.jpg');
    await image.writeAsBytes([255, 216, 255, 217]);
    final item = ManhuaguiDownloadedItem(
      4,
      [2],
      'manhuagui-4125',
      sample,
      '漫画柜',
      chapterDirectories: {'20': 'chapter-20'},
    );
    final reader = ManhuaguiReadingData(
      sample.copyWith(chapters: {'9': '新增', ...sample.chapters!}),
    )..history = History.fromModel(model: sample, ep: 3, page: 1);
    reader.bindDependencies(
      downloadManager: _OfflineManager(item, root),
      sourceServices: _NoNetworkServices(),
      sourceCallbacks: _NoSourceCallbacks(),
    );
    final result = await reader.loadEp(4).last;
    expect(
      await FileSystemEntity.identical(
        result.data.single.substring(7),
        image.path,
      ),
      isTrue,
    );
    expect(reader.localEpisode(4), 3);
    expect(reader.history!.readChapterIds, {'20'});
  });

  test('空图片章节重试三次后失败，不能标记下载完成', () async {
    final network = _EmptyNetwork();
    final task = ManhuaguiDownloadingTask(
      sample,
      [0],
      () {},
      () {},
      () async {},
      'manhuagui-4125',
    );
    task.bindDownloadManager(_NetworkManager(network));
    await expectLater(task.getLinks(), throwsStateError);
    expect(network.calls, 3);
  });

  test('独立类型追加且任务恢复保留跨组选章、暂停和图片链接', () {
    expect(DownloadType.other.index, 6);
    expect(DownloadType.hiperdex.index, 9);
    expect(DownloadType.manhuagui.index, 10);
    final task =
        ManhuaguiDownloadingTask(
            sample,
            [0, 2, 4],
            () {},
            () {},
            () async {},
            'manhuagui-4125',
          )
          ..userPaused = true
          ..directory = 'sample'
          ..links = {
            1: ['old-signature'],
            3: ['other'],
            5: ['extra'],
          };
    final restored = downloadingItemFromMap(
      jsonDecode(jsonEncode(task.toMap())),
      () {},
      () {},
      () async {},
    );
    expect(restored, isA<ManhuaguiDownloadingTask>());
    expect(restored.type, DownloadType.manhuagui);
    expect(restored.userPaused, isTrue);
    expect(restored.links, task.links);
    expect(restored.getEpisodeDirectoryName(3), 'chapter-20');
    expect(
      (restored as ManhuaguiDownloadingTask).comic.chapterGroups,
      sample.chapterGroups,
    );
  });

  test('目录重排、新增及删除后保留已下载章节与真实目录', () {
    final original = ManhuaguiDownloadedItem(
      42,
      [1, 4],
      'manhuagui-4125',
      sample,
      '漫画柜',
      chapterDirectories: {'11': 'chapter-11', '30': 'chapter-30'},
    )..directory = 'keep-root';
    final updated = sample.copyWith(
      chapters: {
        '9': '新增卷',
        '10': '第01卷',
        '11': '第02卷',
        '20': '第01话',
        '21': '第02话',
      },
      chapterGroups: [
        sample.chapterGroups[0].copyWith(chapterIds: ['9', '10', '11']),
        sample.chapterGroups[1],
      ],
    );
    final merged = original.withComicInfo(updated);
    expect(
      merged.downloadedEps.map(
        (index) => merged.chapters!.keys.elementAt(index),
      ),
      ['11', '30'],
    );
    expect(merged.directory, 'keep-root');
    expect(merged.comic.chapterGroups.last.chapterIds, ['30']);
    final restored = ManhuaguiDownloadedItem.fromJson(
      jsonDecode(jsonEncode(merged.toJson())),
    );
    final reader = ManhuaguiReadingData(updated)
      ..onDownloadedItemLoaded(restored);
    expect(reader.localEpisode(3), 3);
    expect(restored.getEpisodeDirectoryName(3), 'chapter-11');
    expect(original.chapters, sample.chapters);
  });

  test('所有分组首尾均不跨组，手动选择另一组后在该组阅读', () {
    final reader = ManhuaguiReadingData(sample);
    expect(reader.adjacentEpisode(1, 1), 2);
    expect(reader.adjacentEpisode(2, 1), isNull);
    expect(reader.adjacentEpisode(3, -1), isNull);
    expect(reader.adjacentEpisode(3, 1), 4);
    expect(reader.adjacentEpisode(4, 1), isNull);
    expect(reader.adjacentEpisode(5, 1), isNull);
    expect(reader.adjacentEpisode(5, -1), isNull);
  });

  test('连续滚动和预加载也遵循同一分组边界', () {
    final reader = ManhuaguiReadingData(sample);
    final data = ContinuousReaderData(
      episodeCount: 5,
      loadEpisode: (ep) => Stream.value(Res(['page-$ep'])),
      onChanged: () {},
      canPrepend: () => true,
      adjacentEpisode: reader.adjacentEpisode,
    );
    addTearDown(data.dispose);
    data.seed(2, ['end-of-volume']);
    expect(data.nextEpisode, isNull);
    expect(data.items.any((item) => item.episode == 3), isFalse);
  });

  test('稳定历史序列化并在目录变化后定位，删除章节则回到第一章', () {
    final history = History.fromModel(model: sample, ep: 4, page: 3);
    final reader = ManhuaguiReadingData(sample)..history = history;
    reader.saveChapterPosition(4, 3);
    final restored = History.fromRecord(
      HistoryRecord.fromRow(history.toRecord().toRow()),
    );
    expect(restored.chapterId, '21');
    expect(restored.readChapterIds, {'21'});
    final updated = sample.copyWith(chapters: {'9': '新卷', ...sample.chapters!});
    expect(updated.episodeForHistory(restored), 5);
    expect(
      HistoryRecord.fromJson(jsonDecode(jsonEncode(restored.toMap()))),
      restored.toRecord(),
    );
    expect(
      sample.copyWith(chapters: {'10': '卷'}).episodeForHistory(restored),
      1,
    );
    expect(HistoryRecord.fromMap({'target': 'old'}).readChapterIds, isEmpty);
  });
}

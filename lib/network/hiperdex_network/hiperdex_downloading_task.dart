import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';

import 'hiperdex_downloaded_item.dart';
import 'hiperdex_main_network.dart';

/// HiperDEX 下载任务，使用稳定章节 ID 和真实章号目录，并兼容旧任务。
class HiperdexDownloadingTask extends DownloadingTask {
  HiperdexDownloadingTask(
    this.comic,
    List<int> downloadEps,
    super.onFinish,
    super.onError,
    super.updateInfo,
    super.id,
  ) : _downloadEps = List.of(downloadEps),
      super(type: DownloadType.hiperdex);

  HiperdexDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback onFinish,
    DownloadProgressCallback onError,
    DownloadProgressCallbackAsync updateInfo,
  ) : comic = ComicInfoData.fromJson(Map<String, dynamic>.from(map['comic'])),
      _downloadEps = List<int>.from(map['_downloadEps']),
      _legacyDirectories =
          map['legacyDirectories'] == true ||
          !map.containsKey('chapterDirectories'),
      super.fromMap(map, onFinish, onError, updateInfo) {
    // 旧 Custom 任务的 type 为 6，恢复后统一写为独立的 HiperDEX 类型。
    type = DownloadType.hiperdex;
    _chapterDirectories.addAll(
      Map<String, String>.from(map['chapterDirectories'] ?? {}),
    );
  }

  final ComicInfoData comic;
  final List<int> _downloadEps;
  final Map<String, String> _chapterDirectories = {};
  bool _legacyDirectories = false;

  @override
  String get title => comic.title;

  @override
  String get cover => comic.cover;

  @override
  Map<String, String> get headers => HiperdexNetwork.imageHeaders;

  @override
  bool get haveEps => true;

  @override
  String getEpisodeDirectoryName(int episodeIndex) {
    final key = comic.chapters!.keys.elementAt(episodeIndex - 1);
    return _chapterDirectories[key] ??
        hiperdexChapterDirectoryName(comic.chapters!, key);
  }

  @override
  String getEpisodeName(int episodeIndex) =>
      comic.chapters?.values.elementAtOrNull(episodeIndex - 1) ??
      super.getEpisodeName(episodeIndex);

  @override
  Future<void> onStart() async {
    await super.onStart();
    final previous = await downloadManager.getComicOrNull(id);
    if (previous is HiperdexDownloadedItem) {
      _chapterDirectories.addAll(previous.chapterDirectories);
    }
    if (_legacyDirectories) {
      await _migrateLegacyDirectories();
      _legacyDirectories = false;
    }
    for (final index in _downloadEps) {
      final key = comic.chapters!.keys.elementAt(index);
      _chapterDirectories.putIfAbsent(
        key,
        () => hiperdexChapterDirectoryName(comic.chapters!, key),
      );
    }
  }

  /// 恢复旧数字目录中的部分下载，保留已有图片以便继续下载。
  Future<void> _migrateLegacyDirectories() async {
    final legacy = HiperdexDownloadedItem(
      null,
      _downloadEps,
      id,
      comic,
      'HiperDEX',
      chapterDirectories: {
        for (final index in _downloadEps)
          comic.chapters!.keys.elementAt(index): '${index + 1}',
      },
    );
    await legacy.migrateChapterDirectories(path);
    _chapterDirectories.addAll(legacy.chapterDirectories);
    for (final index in _downloadEps) {
      final key = comic.chapters!.keys.elementAt(index);
      final oldName = _chapterDirectories[key]!;
      if (!await Directory(paths.join(path, oldName)).exists()) {
        _chapterDirectories[key] = hiperdexChapterDirectoryName(
          comic.chapters!,
          key,
        );
      }
    }
  }

  /// 获取一章的图片，接口失败或空章节不能记为下载成功。
  Future<void> _getOneEp(int index, Map<int, List<String>> result) async {
    if (result.containsKey(index + 1)) return;
    final key = comic.chapters!.keys.elementAt(index);
    for (var retry = 0; retry < 3; retry++) {
      final response = await HiperdexNetwork.instance.getChapterPages(
        comic.comicId,
        key,
      );
      if (response.success && response.data.isNotEmpty) {
        result[index + 1] = response.data;
        return;
      }
      if (retry == 2) {
        throw StateError(response.errorMessage ?? 'HiperDEX 章节没有可下载的图片');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  @override
  Future<Map<int, List<String>>> getLinks() async {
    final result = <int, List<String>>{};
    var pending = <Future<void>>[];
    for (final index in _downloadEps) {
      pending.add(_getOneEp(index, result));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (pending.length == 5) {
        await Future.wait(pending);
        pending = [];
      }
    }
    await Future.wait(pending);
    return result;
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) =>
      ImageManager().getImage(link, headers);

  @override
  Map<String, dynamic> toMap() => {
    ...super.toBaseMap(),
    'comic': comic.toJson(),
    '_downloadEps': _downloadEps,
    'chapterDirectories': _chapterDirectories,
    'legacyDirectories': _legacyDirectories,
  };

  @override
  Future<DownloadedItem> toDownloadedItem() =>
      _buildDownloadedItem(_downloadEps);

  @override
  Future<DownloadedItem?> toDownloadedItemPartial(
    List<int> completedEpisodes,
  ) => _buildDownloadedItem(completedEpisodes.map((ep) => ep - 1).toList());

  /// 按章节 ID 合并增量下载记录，保留原有目录、颜色和章节下载状态。
  Future<HiperdexDownloadedItem> _buildDownloadedItem(
    List<int> completed,
  ) async {
    final previous = await downloadManager.getComicOrNull(id);
    final item = previous is HiperdexDownloadedItem
        ? previous.withComicInfo(comic)
        : HiperdexDownloadedItem(null, [], id, comic, 'HiperDEX');
    final keys = item.chapters!.keys.toList();
    for (final index in completed) {
      final key = comic.chapters!.keys.elementAt(index);
      final mappedIndex = keys.indexOf(key);
      if (!item.downloadedEps.contains(mappedIndex)) {
        item.downloadedEps.add(mappedIndex);
      }
      item.chapterDirectories[key] = getEpisodeDirectoryName(index + 1);
    }
    item.downloadedEps.sort();
    item.comicSize = await getStorageSize();
    return item;
  }
}

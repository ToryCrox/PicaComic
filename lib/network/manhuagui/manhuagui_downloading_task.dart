import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';

import 'manhuagui_downloaded_item.dart';
import 'manhuagui_network.dart';

/// 漫画柜下载任务，使用稳定章节 ID 保存跨组选择和续传状态。
class ManhuaguiDownloadingTask extends DownloadingTask {
  ManhuaguiDownloadingTask(
    this.comic,
    List<int> downloadEps,
    super.onFinish,
    super.onError,
    super.updateInfo,
    super.id,
  ) : _downloadEps = List.of(downloadEps),
      super(type: DownloadType.manhuagui);

  ManhuaguiDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback onFinish,
    DownloadProgressCallback onError,
    DownloadProgressCallbackAsync updateInfo,
  ) : comic = ComicInfoData.fromJson(Map<String, dynamic>.from(map['comic'])),
      _downloadEps = List<int>.from(map['_downloadEps']),
      super.fromMap(map, onFinish, onError, updateInfo) {
    // 恢复任务时保持独立来源标识。
    type = DownloadType.manhuagui;
    _chapterDirectories.addAll(
      Map<String, String>.from(map['chapterDirectories'] ?? {}),
    );
  }

  final ComicInfoData comic;
  final List<int> _downloadEps;
  final Map<String, String> _chapterDirectories = {};

  @override
  String get title => comic.title;

  @override
  String get cover => comic.cover;

  @override
  Map<String, String> get headers => ManhuaguiNetwork.imageHeaders;

  @override
  bool get haveEps => true;

  @override
  String getEpisodeDirectoryName(int episodeIndex) {
    final key = comic.chapters!.keys.elementAt(episodeIndex - 1);
    return _chapterDirectories[key] ??
        manhuaguiChapterDirectoryName(comic.chapters!, key);
  }

  @override
  String getEpisodeName(int episodeIndex) =>
      comic.chapters?.values.elementAtOrNull(episodeIndex - 1) ??
      super.getEpisodeName(episodeIndex);

  @override
  Future<void> onStart() async {
    await super.onStart();
    final previous = await manager.getComicOrNull(id);
    if (previous is ManhuaguiDownloadedItem) {
      _chapterDirectories.addAll(previous.chapterDirectories);
    }
    for (final index in _downloadEps) {
      final key = comic.chapters!.keys.elementAt(index);
      _chapterDirectories.putIfAbsent(
        key,
        () => manhuaguiChapterDirectoryName(comic.chapters!, key),
      );
    }
  }

  /// 获取一章的图片，接口失败或空章节不能记为下载成功。
  Future<void> _getOneEp(int index, Map<int, List<String>> result) async {
    if (result.containsKey(index + 1)) return;
    final key = comic.chapters!.keys.elementAt(index);
    for (var retry = 0; retry < 3; retry++) {
      final network = manager.readProvider(manhuaguiNetworkProvider);
      final response = await network.pages(comic.comicId, key);
      if (response.success && response.data.isNotEmpty) {
        result[index + 1] = response.data;
        return;
      }
      if (retry == 2) {
        throw StateError(response.errorMessage ?? '漫画柜 章节没有可下载的图片');
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
  Stream<DownloadProgress> downloadImage(String link) async* {
    try {
      yield* ImageManager(manager).getImage(link, headers);
    } catch (_) {
      // 恢复暂停任务时旧签名可能过期；按原图片路径刷新所在章节。
      final path = Uri.parse(link).path;
      for (final entry in links?.entries ?? <MapEntry<int, List<String>>>[]) {
        final page = entry.value.indexWhere(
          (url) => Uri.parse(url).path == path,
        );
        if (page < 0) continue;
        final key = comic.chapters!.keys.elementAt(entry.key - 1);
        final result = await manager
            .readProvider(manhuaguiNetworkProvider)
            .pages(comic.comicId, key);
        if (result.error || result.data.length <= page) rethrow;
        final refreshed = result.data[page];
        entry.value[page] = refreshed;
        yield* ImageManager(manager).getImage(refreshed, headers);
        return;
      }
      rethrow;
    }
  }

  @override
  Map<String, dynamic> toMap() => {
    ...super.toBaseMap(),
    'comic': comic.toJson(),
    '_downloadEps': _downloadEps,
    'chapterDirectories': _chapterDirectories,
  };

  @override
  Future<DownloadedItem> toDownloadedItem() =>
      _buildDownloadedItem(_downloadEps);

  @override
  Future<DownloadedItem?> toDownloadedItemPartial(
    List<int> completedEpisodes,
  ) => _buildDownloadedItem(completedEpisodes.map((ep) => ep - 1).toList());

  /// 按章节 ID 合并增量下载记录，保留原有目录、颜色和章节下载状态。
  Future<ManhuaguiDownloadedItem> _buildDownloadedItem(
    List<int> completed,
  ) async {
    final previous = await manager.getComicOrNull(id);
    final item = previous is ManhuaguiDownloadedItem
        ? previous.withComicInfo(comic)
        : ManhuaguiDownloadedItem(null, [], id, comic, '漫画柜');
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

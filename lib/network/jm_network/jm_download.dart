import 'dart:async';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/image_download_queue.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';

import 'jm_chapter_loader.dart';
import 'jm_image.dart';
import 'jm_models.dart';
import 'jm_network.dart';

class DownloadedJmComic extends DownloadedItem {
  JmComicInfo comic;
  double? size;
  List<int> downloadedChapters;
  @override
  DownloadColorTag? color;

  DownloadedJmComic(
    this.comic,
    this.size,
    this.downloadedChapters, {
    this.color,
  });

  Map<String, dynamic> toMap() => {
    "comic": comic.toJson(),
    "size": size,
    "downloadedChapters": downloadedChapters,
    "color": color?.name,
  };

  DownloadedJmComic.fromMap(Map<String, dynamic> map)
    : comic = JmComicInfo.fromMap(map["comic"]),
      size = map["size"],
      color = DownloadColorTag.fromString(map["color"]),
      downloadedChapters = [] {
    if (map["downloadedChapters"] == null) {
      //旧版本中的数据不包含这一项
      for (int i = 0; i < comic.series.length; i++) {
        downloadedChapters.add(i);
      }
      if (downloadedChapters.isEmpty) {
        downloadedChapters.add(0);
      }
    } else {
      downloadedChapters = List<int>.from(map["downloadedChapters"]);
    }
  }

  @override
  DownloadType get type => DownloadType.jm;

  @override
  List<int> get downloadedEps => downloadedChapters;

  @override
  List<String> get eps => comic.epNames.isEmpty
      ? (List<String>.generate(
          comic.series.isEmpty ? 1 : comic.series.length,
          (index) => "第${index + 1}章",
        ))
      : comic.epNames;

  @override
  String get name => comic.name;

  @override
  String get id => "jm${comic.id}";

  @override
  String get subTitle => comic.author.elementAtOrNull(0) ?? "";

  @override
  double? get comicSize => size;

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  set comicSize(double? value) => size = value;

  @override
  List<String> get tags => comic.tags;
}

class JmDownloadingTask extends DownloadingTask {
  JmDownloadingTask(
    this.comic,
    this._downloadEps,
    super.whenFinish,
    super.whenError,
    super.updateInfo,
    super.id, {
    super.type = DownloadType.jm,
  });

  JmComicInfo comic;

  ///要下载的章节
  final List<int> _downloadEps;

  /// 尚未取得有效图片列表的已选章节数。
  int get unresolvedEpisodeCount => _downloadEps.toSet().where((index) {
    return links?[index + 1]?.isNotEmpty != true;
  }).length;

  @override
  Map<int, ({int downloaded, int total})> get episodeProgress {
    final progress = Map<int, ({int downloaded, int total})>.of(
      super.episodeProgress,
    );
    for (final index in _downloadEps) {
      progress.putIfAbsent(index + 1, () => (downloaded: 0, total: 0));
    }
    return progress;
  }

  @override
  String get cover => getJmCoverUrl(comic.id);

  @override
  String get title => comic.name;

  /// 获取指定章节的图片链接，并拒绝已缓存的空列表。
  Future<void> getOneEp(int key, Map<int, List<String>> res) async {
    if (res[key]?.isNotEmpty == true) return;
    res.remove(key);
    res[key] = await fetchJmChapterImages(
      key,
      comic.series[key] ?? '',
      (chapterId) =>
          manager.readProvider(jmNetworkProvider).getChapter(chapterId),
    );
  }

  @override
  Future<Map<int, List<String>>> getLinks() async {
    if (comic.series.isEmpty) {
      comic = comic.copyWith(series: {1: id.replaceFirst("jm", "")});
    }
    var res = <int, List<String>>{};
    var futures = <Future>[];
    for (var key in comic.series.keys.toList()) {
      if (!_downloadEps.contains(key - 1)) continue;
      futures.add(getOneEp(key, res));
      await Future.delayed(const Duration(milliseconds: 200));
      if (futures.length % 5 == 0) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    await Future.wait(futures);
    return res;
  }

  @override
  Future<void> loadImages(ImageDownloadQueue queue) async {
    // 1. 处理单章漫画的特殊情况
    if (comic.series.isEmpty) {
      comic = comic.copyWith(series: {1: id.replaceFirst("jm", "")});
    }

    links ??= {};

    // 2. 对要下载的章节进行排序，确保按顺序下载
    final sortedEps = _downloadEps.toList()..sort();

    // 3. 逐个章节获取并入队
    for (var i in sortedEps) {
      final key = i + 1;

      // 恢复下载时复用有效链接；缺失或空列表需要重新获取。
      if (links![key]?.isNotEmpty != true) {
        await getOneEp(key, links!);
      }

      final urls = links![key]!;

      // 4. 入队
      for (var j = 0; j < urls.length; j++) {
        // JM 根据是否有章节分目录
        // 参照 getLinks 的实现，其实没有写目录逻辑，但是 DownloadingTask 默认逻辑是：
        // var downloadTo = haveEps ? "$path/$ep" : path;
        // JM 的 haveEps 也是 true (based on type != ... list)
        // 只要不是 Hentai/Hitomi/HtManga/Nhentai

        var downloadTo = "$path/$key";
        var basename = j.toString();

        var item = ImageDownloadQueueItem(
          url: urls[j],
          episodeIndex: key,
          imageIndex: j,
          savePath: downloadTo,
          fileBaseName: basename,
        );

        queue.addImage(item);
      }
    }
  }

  /// 从图片链接中提取 bookId
  String _getBookIdFromLink(String link) {
    for (int i = link.length - 1; i >= 0; i--) {
      if (link[i] == '/') {
        return link.substring(i + 1, link.length - 5);
      }
    }
    return "";
  }

  /// 覆写此方法以使用线程安全的方式获取 epsId
  ///
  /// 从 [item.episodeIndex] 直接获取章节 ID，而不是依赖共享状态 [downloadingEp]
  /// 这在并发下载时能确保每张图片都使用正确的章节 ID 进行反混淆处理
  @override
  Stream<DownloadProgress> downloadImageWithContext(
    ImageDownloadQueueItem item,
  ) {
    final bookId = _getBookIdFromLink(item.url);
    // item.episodeIndex 就是 links 的 key，即章节编号
    // comic.series 是 {章节编号: 章节ID} 的映射
    final epsId = comic.series[item.episodeIndex] ?? comic.series.values.first;

    return ImageManager(manager).getJmImage(
      item.url,
      {},
      epsId: epsId,
      scrambleId: kJmScrambleId,
      bookId: bookId,
    );
  }

  @override
  @Deprecated('Use downloadImageWithContext instead for thread safety')
  Stream<DownloadProgress> downloadImage(String link) {
    // 保留此方法用于向后兼容，但新的队列系统会调用 downloadImageWithContext
    final bookId = _getBookIdFromLink(link);
    return ImageManager(manager).getJmImage(
      link,
      {},
      epsId: comic.series[links!.keys.toList()[downloadingEp]]!,
      scrambleId: kJmScrambleId,
      bookId: bookId,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    "comic": comic.toJson(),
    "_downloadEps": _downloadEps,
    ...super.toBaseMap(),
  };

  JmDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : comic = JmComicInfo.fromMap(map["comic"]),
      _downloadEps = List<int>.from(map["_downloadEps"]),
      super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  String getEpisodeName(int episodeIndex) {
    // episodeIndex 是 links 的 key（对于禁漫，与 comic.series 的 key 一致，从1开始）
    // comic.epNames 的索引是从0开始
    final index = episodeIndex - 1;
    if (comic.epNames.isNotEmpty &&
        index >= 0 &&
        index < comic.epNames.length) {
      return comic.epNames[index];
    }
    return "第$episodeIndex章";
  }

  @override
  void cancelEpisode(int episodeIndex) {
    super.cancelEpisode(episodeIndex);
    // 从 _downloadEps 中移除（_downloadEps 存储的是 0-based索引）
    _downloadEps.remove(episodeIndex - 1);
    if (lastError is JmChapterLoadException &&
        (lastError as JmChapterLoadException).episodeIndex == episodeIndex) {
      lastError = null;
    }
  }

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    var previous = <int>[];
    if (await manager.isExists(id)) {
      var comic = (await manager.getComicOrNull(id))! as DownloadedJmComic;
      previous = comic.downloadedEps;
    }
    var downloadEps = (_downloadEps + previous).toSet().toList();
    downloadEps.sort();
    return DownloadedJmComic(comic, await getStorageSize(), downloadEps);
  }

  @override
  FutureOr<DownloadedItem?> toDownloadedItemPartial(
    List<int> completedEpisodes,
  ) async {
    var previous = <int>[];
    if (await manager.isExists(id)) {
      var existingComic =
          (await manager.getComicOrNull(id))! as DownloadedJmComic;
      previous = existingComic.downloadedEps;
    }
    // completedEpisodes 是 links Map 的 key（章节编号，从1开始）
    // downloadedEps 存储的是从0开始的索引
    var downloadedEps =
        (completedEpisodes.map((e) => e - 1).toList() + previous)
            .toSet()
            .toList();
    downloadedEps.sort();
    return DownloadedJmComic(comic, await getStorageSize(), downloadedEps);
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'jm_image.dart';
import 'jm_models.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/image_download_queue.dart';
import 'dart:io';
import 'package:pica_comic/tools/io_tools.dart';
import 'jm_network.dart';

class DownloadedJmComic extends DownloadedItem {
  JmComicInfo comic;
  double? size;
  List<int> downloadedChapters;

  DownloadedJmComic(this.comic, this.size, this.downloadedChapters);

  Map<String, dynamic> toMap() => {
        "comic": comic.toJson(),
        "size": size,
        "downloadedChapters": downloadedChapters
      };

  DownloadedJmComic.fromMap(Map<String, dynamic> map)
      : comic = JmComicInfo.fromMap(map["comic"]),
        size = map["size"],
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
      ? (List<String>.generate(comic.series.isEmpty ? 1 : comic.series.length,
          (index) => "第${index + 1}章"))
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
  JmDownloadingTask(this.comic, this._downloadEps, super.whenFinish,
      super.whenError, super.updateInfo, super.id,
      {super.type = DownloadType.jm});

  JmComicInfo comic;

  ///要下载的章节
  final List<int> _downloadEps;

  @override
  String get cover => getJmCoverUrl(comic.id);

  @override
  String get title => comic.name;

  Future<void> getOneEp(int key, Map<int, List<String>> res) async {
    if (res[key] != null) return;

    int retry = 0;

    while (retry < 3) {
      try {
        res[key] = (await JmNetwork().getChapter(comic.series[key]!)).data;
        return;
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
        retry++;
      }
    }

    throw Exception("Failed to get chapter");
  }

  @override
  Future<Map<int, List<String>>> getLinks() async {
    if (comic.series.isEmpty) {
      comic.series[1] = id.replaceFirst("jm", "");
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
  Stream<DownloadProgress> downloadImageWithContext(ImageDownloadQueueItem item) {
    final bookId = _getBookIdFromLink(item.url);
    // item.episodeIndex 就是 links 的 key，即章节编号
    // comic.series 是 {章节编号: 章节ID} 的映射
    final epsId = comic.series[item.episodeIndex] ?? comic.series.values.first;
    
    return ImageManager().getJmImage(
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
    return ImageManager().getJmImage(
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
        ...super.toBaseMap()
      };

  JmDownloadingTask.fromMap(
      Map<String, dynamic> map,
      DownloadProgressCallback whenFinish,
      DownloadProgressCallback whenError,
      DownloadProgressCallbackAsync updateInfo,
      String id)
      : comic = JmComicInfo.fromMap(map["comic"]),
        _downloadEps = List<int>.from(map["_downloadEps"]),
        super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  String getEpisodeName(int episodeIndex) {
    // episodeIndex 是 links 的 key（对于禁漫，与 comic.series 的 key 一致，从1开始）
    // comic.epNames 的索引是从0开始
    final index = episodeIndex - 1;
    if (comic.epNames.isNotEmpty && index >= 0 && index < comic.epNames.length) {
      return comic.epNames[index];
    }
    return "第$episodeIndex章";
  }

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    var previous = <int>[];
    if (await DownloadManager().isExists(id)) {
      var comic =
          (await DownloadManager().getComicOrNull(id))! as DownloadedJmComic;
      previous = comic.downloadedEps;
    }
    var downloadEps = (_downloadEps + previous).toSet().toList();
    downloadEps.sort();
    return DownloadedJmComic(
        comic, await getFolderSize(Directory(path)), downloadEps);
  }

  @override
  FutureOr<DownloadedItem?> toDownloadedItemPartial(List<int> completedEpisodes) async {
    var previous = <int>[];
    if (await DownloadManager().isExists(id)) {
      var existingComic =
          (await DownloadManager().getComicOrNull(id))! as DownloadedJmComic;
      previous = existingComic.downloadedEps;
    }
    // completedEpisodes 是 links Map 的 key（章节编号，从1开始）
    // downloadedEps 存储的是从0开始的索引
    var downloadedEps = (completedEpisodes.map((e) => e - 1).toList() + previous)
        .toSet()
        .toList();
    downloadedEps.sort();
    return DownloadedJmComic(
        comic, await getFolderSize(Directory(path)), downloadedEps);
  }
}


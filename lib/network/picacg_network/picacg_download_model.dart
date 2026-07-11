import 'dart:async';
import '../download/models/download_color_tag.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/image_download_queue.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import '../download/download_manager.dart';
import 'methods.dart';
import 'dart:io';

class DownloadedComic extends DownloadedItem {
  ComicItem comicItem;
  List<String> chapters;
  List<int> downloadedChapters;
  double? size;
  @override
  DownloadColorTag? color;

  DownloadedComic(
    this.comicItem,
    this.chapters,
    this.size,
    this.downloadedChapters, {
    this.color,
  });

  @override
  Map<String, dynamic> toJson() => {
    "comicItem": comicItem.toJson(),
    "chapters": chapters,
    "size": size,
    "downloadedChapters": downloadedChapters,
    "color": color?.name,
  };

  DownloadedComic.fromJson(Map<String, dynamic> json)
    : comicItem = ComicItem.fromJson(json["comicItem"]),
      chapters = List<String>.from(json["chapters"]),
      size = json["size"],
      color = DownloadColorTag.fromString(json["color"]),
      downloadedChapters = [] {
    if (json["downloadedChapters"] == null) {
      //旧版本中的数据不包含这一项
      for (int i = 0; i < chapters.length; i++) {
        downloadedChapters.add(i);
      }
    } else {
      downloadedChapters = List<int>.from(json["downloadedChapters"]);
    }
  }

  @override
  DownloadType get type => DownloadType.picacg;

  @override
  List<int> get downloadedEps => downloadedChapters;

  @override
  List<String> get eps => chapters.getNoBlankList();

  @override
  String get name => comicItem.title;

  @override
  String get id => comicItem.id;

  @override
  String get subTitle => comicItem.author;

  @override
  double? get comicSize => size;

  @override
  set comicSize(double? value) => size = value;

  @override
  List<String> get tags => comicItem.tags;
}

///picacg的下载进程模型
class PicDownloadingTask extends DownloadingTask {
  PicDownloadingTask(
    this.comic,
    this._downloadEps,
    super.whenFinish,
    super.whenError,
    super.updateInfo,
    super.id, {
    super.type = DownloadType.picacg,
  });

  ///漫画模型
  final ComicItem comic;

  ///章节名称
  var _eps = <String>[];

  ///要下载的章节序号
  final List<int> _downloadEps;

  ///获取各章节名称
  List<String> get eps => _eps;

  @override
  get cover => getImageUrl(comic.thumbUrl);

  @override
  String get title => comic.title;

  @override
  Future<Map<int, List<String>>> getLinks() async {
    var res = <int, List<String>>{};
    _eps = (await network.getEps(id)).data;
    for (var i in _downloadEps) {
      res[i + 1] = (await network.getComicContent(id, i + 1)).data;
    }
    return res;
  }

  @override
  Future<void> loadImages(ImageDownloadQueue queue) async {
    // 1. 获取章节列表（如果尚未获取）
    if (_eps.isEmpty) {
      _eps = (await network.getEps(id)).data;
    }

    links ??= {};

    // 2. 对要下载的章节进行排序，确保按顺序下载
    final sortedEps = List<int>.from(_downloadEps)..sort();

    // 3. 逐个章节获取图片链接并加入队列（生产者模式）
    for (var i in sortedEps) {
      final epNum = i + 1;

      // 如果 links 中已经有了（可能是恢复下载），直接使用，否则请求网络
      List<String> urls;
      if (links!.containsKey(epNum)) {
        urls = links![epNum]!;
      } else {
        urls = (await network.getComicContent(id, epNum)).data;
        links![epNum] = urls;
      }

      // 将该章节的图片加入队列
      for (var j = 0; j < urls.length; j++) {
        // Picacg 始终有章节目录
        var downloadTo = "$path/$epNum";
        var basename = j.toString();

        var item = ImageDownloadQueueItem(
          url: urls[j],
          episodeIndex: epNum, // 1-based index
          imageIndex: j,
          savePath: downloadTo,
          fileBaseName: basename,
        );

        queue.addImage(item);
      }
    }
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager().getImage(getImageUrl(link));
  }

  @override
  Map<String, dynamic> toMap() => {
    "comic": comic.toJson(),
    "_eps": _eps,
    "_downloadEps": _downloadEps,
    ...super.toBaseMap(),
  };

  PicDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : comic = ComicItem.fromJson(map["comic"]),
      _eps = List<String>.from(map["_eps"]),
      _downloadEps = List<int>.from(map["_downloadEps"]),
      super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  String getEpisodeName(int episodeIndex) {
    // episodeIndex 是 links 的 key（从1开始），对应 _eps 的索引是 episodeIndex - 1
    final index = episodeIndex - 1;
    if (index >= 0 && index < _eps.length) {
      return _eps[index];
    }
    return super.getEpisodeName(episodeIndex);
  }

  @override
  void cancelEpisode(int episodeIndex) {
    super.cancelEpisode(episodeIndex);
    // 从 _downloadEps 中移除（_downloadEps 存储的是 0-based索引）
    _downloadEps.remove(episodeIndex - 1);
  }

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    var previous = <int>[];
    if (await downloadManager.isExists(id)) {
      var comic =
          (await downloadManager.getComicOrNull(id))! as DownloadedComic;
      previous = comic.downloadedEps;
    }
    var downloaded = (_downloadEps + previous).toSet().toList();
    downloaded.sort();
    return DownloadedComic(
      comic,
      eps,
      await getFolderSize(Directory(path)),
      downloaded,
    );
  }

  @override
  FutureOr<DownloadedItem?> toDownloadedItemPartial(
    List<int> completedEpisodes,
  ) async {
    var previous = <int>[];
    if (await downloadManager.isExists(id)) {
      var existingComic =
          (await downloadManager.getComicOrNull(id))! as DownloadedComic;
      previous = existingComic.downloadedEps;
    }
    // completedEpisodes 是 links Map 的 key（章节编号，从1开始）
    // downloadedEps 存储的是从0开始的索引
    var downloaded = (completedEpisodes.map((e) => e - 1).toList() + previous)
        .toSet()
        .toList();
    downloaded.sort();
    return DownloadedComic(
      comic,
      eps,
      await getFolderSize(Directory(path)),
      downloaded,
    );
  }
}

import 'dart:io';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';

import '../../tools/io_tools.dart';

import 'package:pica_comic/network/download/models/download_color_tag.dart';

class CustomDownloadedItem extends DownloadedItem {
  @override
  double? comicSize;

  @override
  final List<int> downloadedEps;

  final Map<String, String>? chapters;

  @override
  List<String> get eps => chapters?.values.toList() ?? ["EP 1"];

  final String comicId;

  @override
  final String id;

  @override
  final String name;

  @override
  final String subTitle;

  @override
  final List<String> tags;

  @override
  DownloadType get type => DownloadType.other;

  final String sourceKey;

  final String sourceName;

  final String cover;
  @override
  DownloadColorTag? color;

  CustomDownloadedItem(
      this.comicSize,
      this.downloadedEps,
      this.chapters,
      this.id,
      this.name,
      this.subTitle,
      this.tags,
      this.sourceKey,
      this.sourceName,
      this.cover,
      this.comicId,
      {this.color});

  @override
  Map<String, dynamic> toJson() => {
        "comicSize": comicSize,
        "downloadedEps": downloadedEps,
        "chapters": chapters,
        "id": id,
        "name": name,
        "subTitle": subTitle,
        "tags": tags,
        "sourceKey": sourceKey,
        "sourceName": sourceName,
        "cover": cover,
        "comicId": comicId,
        "color": color?.name,
      };

  CustomDownloadedItem.fromJson(Map<String, dynamic> json)
      : comicSize = json["comicSize"],
        downloadedEps = List<int>.from(json["downloadedEps"]),
        chapters = json["chapters"] != null
            ? Map<String, String>.from(json["chapters"])
            : null,
        id = json["id"],
        name = json["name"],
        subTitle = json["subTitle"],
        tags = List<String>.from(json["tags"]),
        sourceKey = json["sourceKey"],
        sourceName = json["sourceName"],
        cover = json["cover"],
        comicId = json["comicId"],
        color = DownloadColorTag.fromString(json["color"]);
}

class CustomDownloadingTask extends DownloadingTask {
  CustomDownloadingTask(this.comic, this._downloadEps, super.whenFinish,
      super.whenError, super.updateInfo, super.id,
      {super.type = DownloadType.other})
      : source = ComicSource.find(comic.sourceKey);

  final ComicInfoData comic;

  final List<int> _downloadEps;

  final ComicSource? source;

  @override
  String get cover => comic.cover;

  @override
  bool get haveEps => comic.chapters != null;

  Stream<DownloadProgress> _getImage(String url) {
    if (source?.getImageLoadingConfig != null) {
      int ep = (links?.keys.length ?? 0) > downloadingEp ? links!.keys.elementAt(downloadingEp) : 0;
      var config = source!.getImageLoadingConfig!(url, comic.comicId,
          comic.chapters?.keys.elementAtOrNull(ep - 1) ?? comic.comicId);
      return ImageManager()
          .getImage(config?.url ?? url, Map.from(config?.headers ?? {}));
    }
    return ImageManager().getImage(url);
  }

  @override
  Map<String, String> get headers => {
        "User-Agent": webUA,
      };

  Future<void> getOneEp(int i, Map<int, List<String>> links) async {
    if (links[i + 1] != null) return;

    int retry = 0;

    while (retry < 3) {
      try {
        links[i + 1] = (await source?.loadComicPages?.call(
                comic.comicId, comic.chapters!.keys.elementAt(i)))
            ?.data ?? [];
        return;
      } catch (e) {
        await Future.delayed(const Duration(seconds: 3));
        retry++;
      }
    }

    throw Exception("Failed to get chapters");
  }

  @override
  Future<Map<int, List<String>>> getLinks() async {
    var links = <int, List<String>>{};
    if (comic.chapters != null) {
      var futures = <Future>[];
      for (var i in _downloadEps) {
        futures.add(getOneEp(i, links));
        await Future.delayed(const Duration(milliseconds: 200));
        if (futures.length % 5 == 0) {
          await Future.wait(futures);
          futures.clear();
        }
      }
      await Future.wait(futures);
    } else {
      var res = await source?.loadComicPages?.call(comic.comicId, null);
      links[0] = res?.data ?? [];
    }
    return links;
  }

  @override
  String get title => comic.title;

  @override
  Map<String, dynamic> toMap() => {
        "comic": comic.toJson(),
        "_downloadEps": _downloadEps,
        ...super.toBaseMap()
      };

  CustomDownloadingTask.fromMap(
      Map<String, dynamic> map,
      DownloadProgressCallback whenFinish,
      DownloadProgressCallback whenError,
      DownloadProgressCallbackAsync updateInfo,
      String id)
      : comic = ComicInfoData.fromJson(map["comic"]),
        _downloadEps = List<int>.from(map["_downloadEps"]),
        source = ComicSource.find(ComicInfoData.fromJson(map["comic"]).sourceKey),
        super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  String getEpisodeName(int episodeIndex) {
    // episodeIndex 是 links 的 key（从1开始），对应 chapters 的索引是 episodeIndex - 1
    if (comic.chapters != null) {
      final index = episodeIndex - 1;
      final values = comic.chapters!.values.toList();
      if (index >= 0 && index < values.length) {
        return values[index];
      }
    }
    return super.getEpisodeName(episodeIndex);
  }

  @override
  Future<DownloadedItem> toDownloadedItem() async {
    var previous = <int>[];
    if (await downloadManager.isExists(id)) {
      var comic = await downloadManager.getComicOrNull(id);
      previous = comic!.downloadedEps;
    }
    var downloaded = (_downloadEps + previous).toSet().toList();
    downloaded.sort();
    var tags = <String>[];
    comic.tags.forEach((key, value) => tags.addAll(value));
    return CustomDownloadedItem(
      await getFolderSize(Directory(path)),
      downloaded,
      comic.chapters,
      id,
      comic.title,
      comic.subTitle ?? "",
      tags,
      comic.sourceKey,
      source?.name ?? "Unknown",
      comic.cover,
      comic.comicId,
    );
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return _getImage(link);
  }
}

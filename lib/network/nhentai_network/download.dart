import 'dart:async';
import 'dart:io';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/tools/translations.dart';
import '../../foundation/image_manager.dart';
import '../../tools/io_tools.dart';

import 'package:pica_comic/network/download/models/download_color_tag.dart';

class NhentaiDownloadedComic extends DownloadedItem {
  NhentaiDownloadedComic(this.comic, this.size, {this.color});

  NhentaiComic comic;

  double? size;
  @override
  DownloadColorTag? color;

  @override
  double? get comicSize => size;

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ["第一章".tl];

  @override
  String get id => "nhentai${comic.id}";

  @override
  String get name => comic.title;

  @override
  String get subTitle => comic.subTitle;

  @override
  DownloadType get type => DownloadType.nhentai;

  @override
  Map<String, dynamic> toJson() => {
    'comic': comic.toMap(),
    'size': size,
    'color': color?.name,
  };

  NhentaiDownloadedComic.fromJson(Map<String, dynamic> json)
    : comic = json['comic'] != null
          ? NhentaiComic.fromMap(Map<String, dynamic>.from(json['comic']))
          : NhentaiComic(
              (json['comicID'] as String).replaceFirst(RegExp(r'^nhentai'), ''),
              json['title'] ?? '',
              json['subTitle'] ?? '',
              json['cover'] ?? '',
              {
                if (json['tags'] != null)
                  'Tags': List<String>.from(json['tags']),
              },
              false,
              const [],
              const [],
              '',
            ),
      size = json["size"],
      color = DownloadColorTag.fromString(json["color"]);

  @override
  set comicSize(double? value) => size = value;

  @override
  List<String> get tags => comic.tags.values.expand((e) => e).toList();

  String get cover => comic.cover;

  String get title => comic.title;
}

class NhentaiDownloadingTask extends DownloadingTask {
  NhentaiDownloadingTask(
    this.comic,
    super.whenFinish,
    super.whenError,
    super.updateInfo,
    super.id, {
    super.type = DownloadType.nhentai,
  });

  final NhentaiComic comic;

  @override
  String get cover => comic.cover;

  @override
  Future<Map<int, List<String>>> getLinks() async {
    var res = await NhentaiNetwork().getImages(comic.id);
    return {0: res.data};
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager().getImage(link);
  }

  @override
  String get title => comic.title;

  @override
  Map<String, dynamic> toMap() => {
    "comic": comic.toMap(),
    ...super.toBaseMap(),
  };

  NhentaiDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : comic = NhentaiComic.fromMap(map["comic"]),
      super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    return NhentaiDownloadedComic(comic, await getFolderSize(Directory(path)));
  }
}

import 'dart:async';
import 'dart:io';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/tools/translations.dart';
import '../../foundation/image_manager.dart';
import '../../tools/io_tools.dart';

import 'package:pica_comic/network/download/models/download_color_tag.dart';

class NhentaiDownloadedComic extends DownloadedItem {
  NhentaiDownloadedComic(
      this.comicID, this.title, this.size, this.cover, this.tags, {this.color});

  final String comicID;

  final String title;

  final double? size;

  final String cover;
  @override
  DownloadColorTag? color;

  @override
  double? get comicSize => size;

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ["第一章".tl];

  @override
  String get id => comicID;

  @override
  String get name => title;

  @override
  String get subTitle => "";

  @override
  DownloadType get type => DownloadType.nhentai;

  @override
  Map<String, dynamic> toJson() =>
      {'comicID': comicID, 'title': title, 'size': size, 'cover': cover, 'color': color?.name};

  NhentaiDownloadedComic.fromJson(Map<String, dynamic> json)
      : comicID = json["comicID"],
        title = json["title"],
        size = json["size"],
        tags = List.from(json["tags"] ?? []),
        cover = json["cover"],
        color = DownloadColorTag.fromString(json["color"]);

  @override
  set comicSize(double? value) {}

  @override
  List<String> tags;
}

class NhentaiDownloadingTask extends DownloadingTask {
  NhentaiDownloadingTask(
      this.comic, super.whenFinish, super.whenError, super.updateInfo, super.id,
      {super.type = DownloadType.nhentai});

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
  Map<String, dynamic> toMap() =>
      {"comic": comic.toMap(), ...super.toBaseMap()};

  NhentaiDownloadingTask.fromMap(
      Map<String, dynamic> map,
      DownloadProgressCallback whenFinish,
      DownloadProgressCallback whenError,
      DownloadProgressCallbackAsync updateInfo,
      String id)
      : comic = NhentaiComic.fromMap(map["comic"]),
        super.fromMap(map, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    return NhentaiDownloadedComic(
      id,
      title,
      await getFolderSize(Directory(path)),
      comic.cover,
      comic.tags["tags"] ?? [],
    );
  }
}

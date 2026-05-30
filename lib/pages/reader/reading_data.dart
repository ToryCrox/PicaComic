import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

import '../../comic_source/comic_source.dart';
import '../../foundation/def.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/image_loader/file_image_loader.dart';
import '../../foundation/image_loader/stream_image_provider.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/local_history.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../network/htmanga_network/htmanga_main_network.dart';
import '../../network/jm_network/jm_image.dart';
import '../../network/jm_network/jm_models.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/nhentai_network/nhentai_main_network.dart';
import '../../network/picacg_network/methods.dart';
import '../../network/res.dart';
import '../../tools/type_util.dart';
import '../../base.dart';

abstract class ReadingData {
  ReadingData();

  bool isReversed = false;

  String get title;

  String get id;

  String get downloadId;

  ComicType get type;

  String get sourceKey => type.name;

  bool get hasEp;

  Map<String, String>? get eps;

  bool _isDownloaded = false;

  /// Whether the comic is downloaded locally.
  bool get isDownloaded => _isDownloaded;

  List<int> downloadedEps = [];

  String get dirPath => '';

  String get favoriteId => id;

  FavoriteType get favoriteType;

  History? history;

  bool checkEpDownloaded(int ep) {
    return !hasEp || downloadedEps.contains(ep-1);
  }

  Stream<Res<List<String>>> loadEp(int ep) async* {
    history ??= await HistoryManager().findSync(id);
    history?.addReadEpisode(ep);
    _isDownloaded = await downloadManager.isExists(downloadId);
    if(_isDownloaded && downloadedEps.isEmpty){
      downloadedEps = (await downloadManager.getComicOrNull(downloadId))!.downloadedEps;
    }
    if (dirPath.isNotEmpty) {
      final imageList = await downloadManager.getAllImagesByDir(dirPath);
      final imageFileUriList = imageList.map((e) => 'file://$e').toList();
      if (isReversed) {
        yield Res(imageFileUriList.reversed.toList());
      } else {
        yield Res(imageFileUriList);
      }
    } else if (_isDownloaded && checkEpDownloaded(ep)){
      final e = hasEp ? ep : 0;
      final downloadDir = await downloadManager.getImageDirectory(downloadId, e);
      final imageList = await downloadManager.getAllImageFileList(downloadId, e);
      final imageFileUriList = imageList.map((e) => 'file://$e').toList();
      debugPrint("loadEp $id $ep, imageFileUriList： ${imageList.map((e) => e.replaceFirst(downloadDir, '')).toList()}");
      yield Res(imageFileUriList);
      //yield Res(List.filled(length, ""));
    } else {
      final cacheKey = 'reading-data-${type.name}-$id-$ep';
      final cacheRes = await DiskCache.readModel(cacheKey,
          (e) => TypeUtil.parseStringList(e['data']));
      if (cacheRes != null && cacheRes.isNotEmpty) {
        yield Res(cacheRes);
      }
      final netRes = await loadEpNetwork(ep);
      if (netRes.success) {
        yield netRes;
        DiskCache.writeString('reading-data-${type.name}-$id-$ep',
            TypeUtil.parseString({'data': netRes.data}));
      } else {
        yield netRes;
      }
    }
  }




  /// Load image from local or network
  ///
  /// [page] starts from 0, [ep] starts from 1
  Stream<DownloadProgress> loadImage(int ep, int page, String url, {String? title}) async* {
    if (_isDownloaded && checkEpDownloaded(ep)) {
      final imageFile = await downloadManager.getImage(downloadId, hasEp ? ep : 0, page);
      yield DownloadProgress(
          1, 1, "", imageFile.path);
    } else {
      if (title != null) {
        final file = await downloadManager.getDownloadImageOrNull(title, ep, page);
        if (file != null) {
          yield DownloadProgress(1, 1, "", file.path);
        } else {
          yield* loadImageNetwork(ep, page, url);
        }
      } else {
        yield* loadImageNetwork(ep, page, url);
      }
    }
  }

  ImageProvider createImageProvider(int ep, int page, String url){
    // url如果是文件的uri
    if (url.startsWith("file://")) {
      return FileImage(File(url.substring(7)));
    } else if (_isDownloaded && checkEpDownloaded(ep)){
      return FileImageProvider(downloadId, hasEp ? ep : 0, page);
    } else {
      return StreamImageProvider(() => loadImage(ep, page, url, title: title), buildImageKey(ep, page, url));
    }
  }

  String buildImageKey(int ep, int page, String url) => url;

  Future<Res<List<String>>> loadEpNetwork(int ep);

  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url);
}

class PicacgReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  PicacgReadingData(this.title, this.id, List<String> epsList)
      : eps = {for (var e in epsList) e: e};

  @override
  final Map<String, String> eps;

  @override
  bool get hasEp => true;

  @override
  ComicType get type => ComicType.picacg;

  @override
  String get downloadId => id;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return PicacgNetwork().getComicContent(id, ep);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.picacg;
}

class EhReadingData extends ReadingData {
  final Gallery gallery;

  EhReadingData(this.gallery);

  @override
  bool get hasEp => eps != null;

  @override
  ComicType get type => ComicType.ehentai;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(int.parse(gallery.maxPage), "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getEhImageNew(gallery, page+1);
  }

  @override
  Map<String, String>? get eps => null;

  @override
  String get id => gallery.link;

  @override
  String get title => gallery.title;

  @override
  String buildImageKey(int ep, int page, String url) => "${gallery.link}$page";

  @override
  FavoriteType get favoriteType => FavoriteType.ehentai;
}

class JmReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  int? commentsLength;
  
  static Map<String, String> generateMap(List<String> epIds, List<String> epNames){
    if(epIds.length == epNames.length){
      return Map.fromIterables(epIds, epNames);
    } else {
      return Map.fromIterables(epIds, List.generate(epIds.length, (index) => "第${index+1}章"));
    }
  }

  JmReadingData(this.title, this.id, List<String> epIds, List<String> epNames)
      : eps = generateMap(epIds, epNames);

  @override
  bool get hasEp => true;

  @override
  ComicType get type => ComicType.jm;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async{
    var res = await JmNetwork().getChapter(eps.keys.elementAtOrNull(ep-1) ?? id);
    commentsLength = res.subData;
    return res;
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    var bookId = "";
    for (int i = url.length - 1; i >= 0; i--) {
      if (url[i] == '/') {
        bookId = url.substring(i + 1, url.length - 5);
        break;
      }
    }
    return ImageManager().getJmImage(url, null,
        epsId: eps.keys.elementAtOrNull(ep-1) ?? id,
        scrambleId: kJmScrambleId,
        bookId: bookId);
  }

  @override
  final Map<String, String> eps;

  @override
  String buildImageKey(int ep, int page, String url) => url.replaceAll(RegExp(r"\?.+"), "");

  @override
  FavoriteType get favoriteType => FavoriteType.jm;
}

class HitomiReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  final List<HitomiFile> images;

  final String link;

  HitomiReadingData(this.title, this.id, this.images, this.link);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  ComicType get type => ComicType.hitomi;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  String get favoriteId => link;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(images.length, "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getHitomiImage(images[page], id);
  }

  @override
  String buildImageKey(int ep, int page, String url) => images[page].hash;

  @override
  FavoriteType get favoriteType => FavoriteType.hitomi;
}

class HtReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  HtReadingData(this.title, this.id,);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  String get sourceKey => type.name;

  @override
  ComicType get type => ComicType.htmanga;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return HtmangaNetwork().getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.htmanga;
}

class NhentaiReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  NhentaiReadingData(this.title, this.id);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  ComicType get type => ComicType.nhentai;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return NhentaiNetwork().getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.nhentai;
}

class CustomReadingData extends ReadingData{
  CustomReadingData(this.id, this.title, this.source, this.eps);

  final ComicSource? source;

  @override
  String get downloadId => downloadManager.getDownloadIdFromComicId(type, id);

  @override
  final Map<String, String>? eps;

  @override
  bool get hasEp => eps != null;

  @override
  String id;

  @override
  final String title;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    if(source == null) {
      return Future.value(const Res.error("Unknown Comic Source"));
    }
    if(hasEp){
      return source!.loadComicPages!(id, eps!.keys.elementAtOrNull(ep-1) ?? id);
    } else {
      return source!.loadComicPages!(id, null);
    }
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager().getCustomImage(
        url,
        id,
        eps?.keys.elementAtOrNull(ep-1) ?? id,
        sourceKey
    );
  }

  @override
  String get sourceKey => source?.key.name ?? "";

  @override
  ComicType get type => ComicType.other;

  @override
  String buildImageKey(int ep, int page, String url) =>
      "$sourceKey$id${eps?.keys.elementAtOrNull(ep-1) ?? id}$url";

  @override
  FavoriteType get favoriteType => FavoriteType(source!.intKey);
}



class LocalReadingData extends ReadingData {

  String _dirPath;
  final String _title;
  final List<String> allDirPaths;
  final bool _isReversed;

  LocalReadingData(this._dirPath, this._title, {this.allDirPaths = const [], bool isReversed = false})
      : _isReversed = isReversed;

  @override
  bool get isReversed => _isReversed;

  void goNext() {
    final index = allDirPaths.indexOf(_dirPath);
    if (index >= 0 && index < allDirPaths.length - 1) {
      _dirPath = allDirPaths[index + 1];
    }
  }

  void goPrev() {
    final index = allDirPaths.indexOf(_dirPath);
    if (index > 0) {
      _dirPath = allDirPaths[index - 1];
    }
  }

  void goTo(int index) {
    _dirPath = allDirPaths[index];
  }

  @override
  String get dirPath => _dirPath;

  @override
  bool get hasEp => eps != null;

  @override
  String get sourceKey => type.name;

  @override
  ComicType get type => ComicType.local;

  @override
  String get downloadId => _title;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async {
    return const Res([]);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) async*{

  }

  @override
  Map<String, String>? get eps {
    if (allDirPaths.isNotEmpty) {
      return allDirPaths.groupFoldBy(
          (e) => e, (p, e) => path.basename(e));
    } else {
      return null;
    }
  }

  @override
  String get id => _dirPath;

  @override
  String get title => path.basename(_dirPath);

  @override
  String buildImageKey(int ep, int page, String url) => "$dirPath$page";

  @override
  FavoriteType get favoriteType => FavoriteType.ehentai;
}

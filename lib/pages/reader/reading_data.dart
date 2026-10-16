import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

import '../../comic_source/comic_source.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/image_loader/file_image_loader.dart';
import '../../foundation/image_loader/stream_image_provider.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/local_favorites.dart';
import '../../network/download/download_model.dart';
import '../../network/comic_source_services.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../network/jm_network/jm_image.dart';
import '../../network/res.dart';
import '../../tools/type_util.dart';
import '../../base.dart';
import '../hiperdex/hiperdex_reading_data.dart';
import '../manhuagui/manhuagui_reading_data.dart';

abstract class ReadingData {
  ReadingData();

  late DownloadManager _downloadManager;
  late ComicSourceServices _sourceServices;
  late ComicSourceCallbackRunner _sourceCallbacks;

  /// 由阅读器的 ConsumerState 注入 Provider 管理的运行时依赖。
  void bindDependencies({
    required DownloadManager downloadManager,
    required ComicSourceServices sourceServices,
    required ComicSourceCallbackRunner sourceCallbacks,
  }) {
    _downloadManager = downloadManager;
    _sourceServices = sourceServices;
    _sourceCallbacks = sourceCallbacks;
  }

  /// 获取已注入的漫画源服务，供专用阅读数据实现使用。
  ComicSourceServices get sourceServices => _sourceServices;

  ComicSourceCallbackRunner get sourceCallbacks => _sourceCallbacks;

  /// 获取阅读会话绑定的下载管理器。
  DownloadManager get downloadManager => _downloadManager;

  /// 根据实际漫画源创建阅读数据，内置源使用自己的实现。
  factory ReadingData.fromSource(
    String id,
    String title,
    ComicSource? source,
    Map<String, String>? eps, {
    List<ComicChapterGroup> chapterGroups = const [],
  }) {
    if (source?.key == ComicType.manhuagui) {
      return ManhuaguiReadingData(
        ComicInfoData(
          comicId: id,
          title: title,
          sourceKey: "manhuagui",
          chapters: eps,
          chapterGroups: chapterGroups,
        ),
      );
    }
    if (source?.key == ComicType.hiperdex) {
      return HiperdexReadingData(id, title, eps);
    }
    return CustomReadingData(id, title, source, eps);
  }

  bool isReversed = false;

  String get title;

  String get id;

  String get downloadId;

  ComicType get type;

  String get sourceKey => type.name;

  bool get hasEp;

  Map<String, String>? get eps;

  /// 下一章在目录中的索引方向，保留原有章节索引用于下载和历史。
  int get chapterStep => 1;

  /// 可选分组目录，未分组来源保持原有行为。
  List<ComicChapterGroup> get chapterGroups => const [];

  /// 带短期签名的来源每次从网站取得链接，不读取过期的章节链接缓存。
  bool get cacheChapterLinks => true;

  /// 当前页面确实可见时标记已读，预加载不调用此方法。
  void markEpisodeRead(int episode) => history?.addReadEpisode(episode);

  /// 写入来源特有的稳定阅读位置。
  void saveChapterPosition(int episode, int page) {}

  /// 按阅读方向获取相邻章节（一基），到达首尾时返回空值。
  int? adjacentEpisode(int episode, int direction) {
    if (!hasEp) return null;
    final adjacent = episode + direction * chapterStep;
    if (adjacent < 1 || adjacent > (eps?.length ?? 0)) return null;
    return adjacent;
  }

  bool _isDownloaded = false;

  /// Whether the comic is downloaded locally.
  bool get isDownloaded => _isDownloaded;

  List<int> downloadedEps = [];

  String get dirPath => '';

  /// 指定章节的目录，预加载不改变当前阅读位置。
  String directoryForEpisode(int ep) => dirPath;

  /// 目标图片所属漫画的标识和标题。
  String idForEpisode(int ep) => id;

  /// 返回指定章节所属漫画的标题。
  String titleForEpisode(int ep) => title;

  String get favoriteId => id;

  FavoriteType get favoriteType;

  History? history;

  /// 将在线章节索引映射到下载快照中的章节索引（一基）。
  int localEpisode(int ep) => ep;

  /// 加载下载记录后更新来源特有的章节映射。
  void onDownloadedItemLoaded(DownloadedItem item) {}

  bool checkEpDownloaded(int ep) {
    return !hasEp || downloadedEps.contains(localEpisode(ep) - 1);
  }

  /// 加载指定章节；预加载传入 markRead: false，不提前标记已读。
  Stream<Res<List<String>>> loadEp(int ep, {bool markRead = true}) async* {
    history ??= await HistoryManager().findSync(id);
    if (markRead) markEpisodeRead(ep);
    // 从同一份下载快照确定存在状态和章节映射，避免并发删除造成状态不一致。
    final item = await _downloadManager.getComicOrNull(downloadId);
    _isDownloaded = item != null;
    if (item != null) {
      downloadedEps = item.downloadedEps;
      onDownloadedItemLoaded(item);
    }
    final episodeDirectory = directoryForEpisode(ep);
    if (episodeDirectory.isNotEmpty) {
      final imageList = await _downloadManager.getAllImagesByDir(
        episodeDirectory,
      );
      final imageFileUriList = imageList.map((e) => 'file://$e').toList();
      if (isReversed) {
        yield Res(imageFileUriList.reversed.toList());
      } else {
        yield Res(imageFileUriList);
      }
    } else if (_isDownloaded && checkEpDownloaded(ep)) {
      final e = hasEp ? localEpisode(ep) : 0;
      final downloadDir = await _downloadManager.getImageDirectory(
        downloadId,
        e,
      );
      final imageList = await _downloadManager.getAllImageFileList(
        downloadId,
        e,
      );
      final imageFileUriList = imageList.map((e) => 'file://$e').toList();
      debugPrint(
        "loadEp $id $ep, imageFileUriList： ${imageList.map((e) => e.replaceFirst(downloadDir, '')).toList()}",
      );
      yield Res(imageFileUriList);
      //yield Res(List.filled(length, ""));
    } else {
      final cacheKey = 'reading-data-${type.name}-$id-$ep';
      final cacheRes = !cacheChapterLinks
          ? null
          : await DiskCache.readModel(
              cacheKey,
              (e) => TypeUtil.parseStringList(e['data']),
            );
      if (cacheRes != null && cacheRes.isNotEmpty) {
        yield Res(cacheRes);
      }
      final netRes = await loadEpNetwork(ep);
      if (netRes.success) {
        yield netRes;
        if (cacheChapterLinks) {
          DiskCache.writeString(
            'reading-data-${type.name}-$id-$ep',
            TypeUtil.parseString({'data': netRes.data}),
          );
        }
      } else {
        yield netRes;
      }
    }
  }

  /// Load image from local or network
  ///
  /// [page] starts from 0, [ep] starts from 1
  Stream<DownloadProgress> loadImage(
    int ep,
    int page,
    String url, {
    String? title,
  }) async* {
    if (url.startsWith('file://')) {
      yield DownloadProgress(1, 1, '', url.substring(7));
      return;
    }
    if (_isDownloaded && checkEpDownloaded(ep)) {
      final imageFile = await _downloadManager.getImage(
        downloadId,
        hasEp ? localEpisode(ep) : 0,
        page,
      );
      yield DownloadProgress(1, 1, "", imageFile.path);
    } else {
      if (title != null) {
        final file = await _downloadManager.getDownloadImageOrNull(
          title,
          ep,
          page,
        );
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

  ImageProvider createImageProvider(int ep, int page, String url) {
    // url如果是文件的uri
    if (url.startsWith("file://")) {
      return FileImage(File(url.substring(7)));
    } else if (_isDownloaded && checkEpDownloaded(ep)) {
      return FileImageProvider(
        _downloadManager,
        downloadId,
        hasEp ? localEpisode(ep) : 0,
        page,
      );
    } else {
      return StreamImageProvider(
        () => loadImage(ep, page, url, title: title),
        buildImageKey(ep, page, url),
      );
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
    return _sourceServices.picacg.getComicContent(id, ep);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getImage(url);
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
  String get downloadId => _downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(int.parse(gallery.maxPage), "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getEhImageNew(gallery, page + 1);
  }

  @override
  Map<String, String>? get eps => null;

  @override
  String get id => gallery.link;

  @override
  String get title => gallery.title;

  @override
  String buildImageKey(int ep, int page, String url) => buildEhImageCacheKey(
    gallery.link,
    page + 1,
    preferOriginal: appdata.getSetting(AppSettingKeys.ehPreferOriginal) == "1",
  );

  @override
  FavoriteType get favoriteType => FavoriteType.ehentai;
}

class JmReadingData extends ReadingData {
  @override
  final String title;

  @override
  final String id;

  final _commentsLengths = <int, int?>{};

  /// 评论数量按章节保存，预加载不会覆盖当前章的附属信息。
  int? commentsLengthForEpisode(int episode) => _commentsLengths[episode];

  static Map<String, String> generateMap(
    List<String> epIds,
    List<String> epNames,
  ) {
    if (epIds.length == epNames.length) {
      return Map.fromIterables(epIds, epNames);
    } else {
      return Map.fromIterables(
        epIds,
        List.generate(epIds.length, (index) => "第${index + 1}章"),
      );
    }
  }

  JmReadingData(this.title, this.id, List<String> epIds, List<String> epNames)
    : eps = generateMap(epIds, epNames);

  @override
  bool get hasEp => true;

  @override
  ComicType get type => ComicType.jm;

  @override
  String get downloadId => _downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async {
    var res = await _sourceServices.jm.getChapter(
      eps.keys.elementAtOrNull(ep - 1) ?? id,
    );
    _commentsLengths[ep] = res.subData;
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
    return ImageManager(_downloadManager).getJmImage(
      url,
      null,
      epsId: eps.keys.elementAtOrNull(ep - 1) ?? id,
      scrambleId: kJmScrambleId,
      bookId: bookId,
    );
  }

  @override
  final Map<String, String> eps;

  @override
  String buildImageKey(int ep, int page, String url) =>
      url.replaceAll(RegExp(r"\?.+"), "");

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
  String get downloadId => _downloadManager.getDownloadIdFromComicId(type, id);

  @override
  String get favoriteId => link;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return Future.value(Res(List.filled(images.length, "")));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getHitomiImage(images[page], id);
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

  HtReadingData(this.title, this.id);

  @override
  Map<String, String>? get eps => null;

  @override
  bool get hasEp => false;

  @override
  String get sourceKey => type.name;

  @override
  ComicType get type => ComicType.htmanga;

  @override
  String get downloadId => _downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return _sourceServices.htmanga.getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getImage(url);
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
  String get downloadId => _downloadManager.getDownloadIdFromComicId(type, id);

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    return _sourceServices.nhentai.getImages(id);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getImage(url);
  }

  @override
  FavoriteType get favoriteType => FavoriteType.nhentai;
}

class CustomReadingData extends ReadingData {
  CustomReadingData(this.id, this.title, this.source, this.eps);

  final ComicSource? source;

  @override
  String get downloadId {
    // 通用阅读器的 type 为 other，下载记录需要使用实际漫画源标识。
    if (source == null) return '';
    return _downloadManager.generateId(sourceKey, id);
  }

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
    if (source == null) {
      return Future.value(const Res.error("Unknown Comic Source"));
    }
    if (hasEp) {
      return _sourceCallbacks.loadComicPages(
        ComicPagesQuery(sourceKey, id, eps!.keys.elementAtOrNull(ep - 1) ?? id),
      );
    } else {
      return _sourceCallbacks.loadComicPages(
        ComicPagesQuery(sourceKey, id, null),
      );
    }
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    return ImageManager(_downloadManager).getCustomImage(
      url,
      id,
      eps?.keys.elementAtOrNull(ep - 1) ?? id,
      sourceKey,
    );
  }

  @override
  String get sourceKey => source?.key.name ?? "";

  @override
  ComicType get type => ComicType.other;

  @override
  String buildImageKey(int ep, int page, String url) =>
      "$sourceKey$id${eps?.keys.elementAtOrNull(ep - 1) ?? id}$url";

  @override
  FavoriteType get favoriteType => FavoriteType(source!.intKey);
}

class LocalReadingData extends ReadingData {
  String _dirPath;
  final String _title;
  final List<String> allDirPaths;
  final bool _isReversed;

  LocalReadingData(
    this._dirPath,
    this._title, {
    this.allDirPaths = const [],
    bool isReversed = false,
  }) : _isReversed = isReversed;

  @override
  bool get isReversed => _isReversed;

  /// 打开的目录在传入目录列表中的章节编号。
  int get initialEpisode {
    final index = allDirPaths.indexOf(_dirPath);
    return index < 0 ? 1 : index + 1;
  }

  @override
  String directoryForEpisode(int ep) {
    if (allDirPaths.isEmpty) return _dirPath;
    return allDirPaths.elementAtOrNull(ep - 1) ?? _dirPath;
  }

  @override
  String idForEpisode(int ep) => directoryForEpisode(ep);

  @override
  String titleForEpisode(int ep) => path.basename(directoryForEpisode(ep));

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
  Stream<DownloadProgress> loadImageNetwork(
    int ep,
    int page,
    String url,
  ) async* {}

  @override
  Map<String, String>? get eps {
    if (allDirPaths.isNotEmpty) {
      return allDirPaths.groupFoldBy((e) => e, (p, e) => path.basename(e));
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

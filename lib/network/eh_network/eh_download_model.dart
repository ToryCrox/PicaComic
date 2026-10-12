import 'dart:async';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/tools/type_util.dart';

class DownloadedGallery extends DownloadedItem {
  Gallery gallery;
  double? size;

  @override
  DownloadColorTag? color;

  DownloadedGallery(this.gallery, this.size, {this.color});

  @override
  Map<String, dynamic> toJson() => {
    "gallery": gallery.toJson(),
    "size": size,
    "color": color?.name,
  };

  DownloadedGallery.fromJson(Map<String, dynamic> map)
    : gallery = Gallery.fromJson(map["gallery"]),
      size = map["size"],
      color = DownloadColorTag.fromString(map["color"]);

  @override
  DownloadType get type => DownloadType.ehentai;

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ["EP 1"];

  @override
  String get name {
    if (manager.settingsSnapshot.enabled(
      AppSettingKeys.ehDownloadedUseSubtitle,
    )) {
      return gallery.subTitle ?? gallery.title;
    }
    return gallery.title;
  }

  @override
  String get id => getGalleryId(gallery.link);

  @override
  String get subTitle => gallery.uploader;

  @override
  double? get comicSize => size;

  @override
  set comicSize(double? value) {
    size = value;
  }

  @override
  List<String> get tags => [
    for (final values in gallery.tags.values) ...values,
  ];
}

/// E-Hentai 普通逐张图片下载任务。
class EhDownloadingTask extends DownloadingTask {
  EhDownloadingTask(
    this.gallery,
    super.whenFinish,
    super.onError,
    super.updateInfo,
    super.id, {
    super.type = DownloadType.ehentai,
    this.legacyArchiveDownloadType,
  });

  final Gallery gallery;

  /// 仅用于识别旧版本保存的压缩包任务；新任务不会设置此字段。
  final int? legacyArchiveDownloadType;

  EhNetwork get _network => manager.readProvider(ehNetworkProvider);

  bool get archiveDownloadRemoved => legacyArchiveDownloadType != null;

  @override
  Map<String, String> get headers => {
    "Cookie": _network.cookiesStr,
    "User-Agent": webUA,
    "Referer": _network.ehBaseUrl,
  };

  @override
  String get cover =>
      gallery.coverPath.replaceFirst('s.exhentai.org', 'ehgt.org');

  @override
  String get title => gallery.title;

  @override
  Future<Map<int, List<String>>> getLinks() async => {
    0: List.generate(int.parse(gallery.maxPage), (index) => '${index + 1}'),
  };

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return ImageManager(manager).getEhImageNew(
      gallery,
      int.parse(link),
      preferOriginal: manager.settingsSnapshot.enabled(
        AppSettingKeys.ehPreferOriginal,
      ),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    final galleryJson = gallery.toJson();
    if (galleryJson['auth'] != null) {
      final auth = <String, dynamic>{...TypeUtil.parseMap(galleryJson['auth'])};
      auth.remove('showKey');
      auth.remove('mpvKey');
      auth.remove('imgKey');
      galleryJson['auth'] = auth;
    }

    return {
      "gallery": galleryJson,
      // 保留旧字段，使旧归档任务在后续启动时仍可识别并显示为不可恢复。
      "downloadType": legacyArchiveDownloadType ?? 0,
      if (legacyArchiveDownloadType != null)
        "removedArchiveDownloadType": legacyArchiveDownloadType,
      ...super.toBaseMap(),
    };
  }

  @override
  Future<void> onStart() async {
    await super.onStart();
    gallery.auth.remove("showKey");
    gallery.auth.remove("mpvKey");
    gallery.auth.remove("imgKey");
    await CacheManager().deleteKeyword("exhentai.org");
    await CacheManager().deleteKeyword("e-hentai.org");
    Log.d(() => 'EhDownloadingTask: 已重置认证状态 id=$id');
  }

  @override
  void start() {
    if (archiveDownloadRemoved) {
      userPaused = true;
      pauseReason = DownloadPauseReason.ehArchiveDownloadRemoved;
      lastError = pauseReason!.messageKey;
      updateInfo?.call();
      return;
    }
    super.start();
  }

  EhDownloadingTask.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : gallery = Gallery.fromJson(map["gallery"]),
      legacyArchiveDownloadType = _legacyArchiveType(map),
      super.fromMap(map, whenFinish, whenError, updateInfo) {
    if (archiveDownloadRemoved) {
      userPaused = true;
      pauseReason = DownloadPauseReason.ehArchiveDownloadRemoved;
      lastError = pauseReason!.messageKey;
    }
  }

  static int? _legacyArchiveType(Map<String, dynamic> map) {
    final savedType = map['removedArchiveDownloadType'] ?? map['downloadType'];
    if (savedType is int && savedType > 0) return savedType;
    return null;
  }

  @override
  FutureOr<DownloadedItem> toDownloadedItem() async {
    final size = await getStorageSize();
    return DownloadedGallery(gallery, size);
  }
}

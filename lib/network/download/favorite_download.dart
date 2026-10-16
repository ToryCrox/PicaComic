import 'package:pica_comic/network/comic_source_services.dart';
import 'dart:async';

import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloading_task.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloading_task.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';

class FavoriteDownloadingTask extends DownloadingTask {
  FavoriteDownloadingTask(
    this.comic,
    super.whenFinish,
    super.onError,
    super.updateInfo,
    super.id, {
    super.type = DownloadType.favorite,
  });

  FavoriteItem comic;

  late DownloadingTask downloadLogic;

  @override
  void start() async {
    await onStart();
    downloadLogic.start();
  }

  @override
  Future<void> onStart() async {
    await super.onStart();
    try {
      switch (comic.type.key) {
        case 0:
          {
            var comicItem = await manager
                .readProvider(picacgNetworkProvider)
                .getComicInfo(comic.target);
            downloadLogic = PicDownloadingTask(
              comicItem.data,
              List.generate(comicItem.data.eps.length, (index) => index),
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        case 1:
          {
            var gallery = await manager
                .readProvider(ehNetworkProvider)
                .getGalleryInfo(comic.target);
            downloadLogic = EhDownloadingTask(
              gallery.data,
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        case 2:
          {
            var jmComic = await manager
                .readProvider(jmNetworkProvider)
                .getComicInfo(comic.target);
            var downloadedEp = List.generate(
              jmComic.data.epNames.length,
              (index) => index,
            );
            if (downloadedEp.isEmpty) {
              downloadedEp.add(0);
            }
            downloadLogic = JmDownloadingTask(
              jmComic.data,
              downloadedEp,
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        case 3:
          {
            var hitomiComic = await manager
                .readProvider(hitomiNetworkProvider)
                .getComicInfo(comic.target);
            downloadLogic = HitomiDownloadingTask(
              hitomiComic.data,
              comic.coverPath,
              comic.target,
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        case 4:
          {
            var htComic = await manager
                .readProvider(htMangaNetworkProvider)
                .getComicInfo(comic.target);
            downloadLogic = HtDownloadingTask(
              htComic.data,
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        case 6:
          {
            var nhComic = await manager
                .readProvider(nhentaiNetworkProvider)
                .getComicInfo(comic.target);
            downloadLogic = NhentaiDownloadingTask(
              nhComic.data,
              onFinish,
              onError,
              updateInfo,
              id,
            );
          }
        default:
          {
            var comicSource = comic.type.comicSource;
            if (comicSource == null) throw "Comic source not found";
            var comicInfoData = await manager.loadSourceComicInfo(
              comicSource.key.name,
              comic.target,
            );
            if (comicInfoData.error) {
              throw StateError(comicInfoData.errorMessageWithoutNull);
            }
            var downloadedEp = List.generate(
              comicInfoData.data.chapters?.length ?? 0,
              (index) => index,
            );
            if (comicSource.key == ComicType.manhuagui) {
              downloadLogic = ManhuaguiDownloadingTask(
                comicInfoData.data,
                downloadedEp,
                onFinish,
                onError,
                updateInfo,
                id,
              );
            } else if (comicSource.key == ComicType.hiperdex) {
              downloadLogic = HiperdexDownloadingTask(
                comicInfoData.data,
                downloadedEp,
                onFinish,
                onError,
                updateInfo,
                id,
              );
            } else {
              downloadLogic = CustomDownloadingTask(
                comicInfoData.data,
                downloadedEp,
                onFinish,
                onError,
                updateInfo,
                id,
              );
            }
          }
      }
    } catch (e, s) {
      Log.e("Download $e$s");
      onError?.call();
      return;
    }
    pause();
    manager.bindTask(downloadLogic);
    manager.downloading.removeFirst();
    manager.downloading.addFirst(downloadLogic);
    downloadLogic.start();
  }

  @override
  String get cover => comic.coverPath;

  @override
  Future<Map<int, List<String>>> getLinks() => downloadLogic.getLinks();

  @override
  String get title => comic.name;

  @override
  Map<String, dynamic> toMap() {
    return {"comic": comic.toJson(), ...toBaseMap()};
  }

  FavoriteDownloadingTask.fromMap(
    Map<String, dynamic> json,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  ) : comic = FavoriteItem.fromJson(json["comic"]),
      super.fromMap(json, whenFinish, whenError, updateInfo);

  @override
  FutureOr<DownloadedItem> toDownloadedItem() =>
      downloadLogic.toDownloadedItem();

  @override
  Stream<DownloadProgress> downloadImage(String link) {
    return downloadLogic.downloadImage(link);
  }
}

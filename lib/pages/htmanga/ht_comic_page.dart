import 'package:pica_comic/comic_source/built_in/ht_manga.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

import '../../foundation/disk_cache.dart';
import '../../network/htmanga_network/ht_download_model.dart';

class HtComicPage extends BaseComicPage<HtComicInfo> {
  const HtComicPage(this.id, {super.key, this.comicCover});

  @override
  final String id;

  final String? comicCover;

  @override
  void openFavoritePanel(ComicPageLogic<HtComicInfo> logic) {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: htManga.isLogin,
      needLoadFolderData: true,
      foldersLoader: () => HtmangaNetwork().getFolders(),
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (logic.favorite.value != b) {
          logic.favorite.value = b;
          logic.update();
        }
      },
      selectFolderCallback: (folder, page) async {
        final comicData = data;
        if (comicData == null) return Res.error("数据加载中".tl);
        if (page == 0) {
          return HtmangaNetwork().addFavorite(comicData.id, folder);
        } else {
          LocalFavoritesManager()
              .addComic(folder, FavoriteItem.fromHtcomic(comicData.toBrief()));
          return const Res(true);
        }
      },
      favoriteOnPlatformValue: false,
    ));
  }

  @override
  String? get cover => data?.cover ?? comicCover;

  @override
  void download(ComicPageLogic<HtComicInfo> logic) async {
    final comicData = data;
    if (comicData == null) return;
    final id = "Ht${comicData.id}";
    if (await downloadManager.isExists(id)) {
      showToast(message: "已下载".tl);
      return;
    }
    for (var i in downloadManager.downloading) {
      if (i.id == id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    downloadManager.addHtDownload(comicData);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  void onThumbnailTapped(int index, ComicPageLogic<HtComicInfo> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromHt(comicData),
        history: logic.history.value,
        initialPage: index + 1,
      ),
    );
  }

  @override
  EpsData? get eps => null;

  @override
  String? get introduction => data?.description;

  @override
  Future<Res<HtComicInfo>> loadData() => HtmangaNetwork().getComicInfo(id).then((res) {
    if (res.success) {
      DiskCache.writeModel(cacheKey, res.data.toJson());
    }
    return res;
  });

  @override
  Future<HtComicInfo?> loadCachedData() async {
    var data = await DiskCache.readModel(cacheKey, (map) => HtComicInfo.fromJson(map));
    if (data != null) return data;
    final downloadedId = "Ht$id";
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedHtComic) {
        return downloaded.comic;
      }
    }
    return null;
  }

  @override
  int? get pages => null;

  @override
  void read(History? history, ComicPageLogic<HtComicInfo> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromHt(comicData),
        history: history,
      ),
    );
  }

  @override
  SliverGrid? recommendationBuilder(HtComicInfo data) => null;


  @override
  Map<String, List<String>>? get tags {
    final comicData = data;
    if (comicData == null) return null;
    return {"分类".tl: comicData.category.toList(), "标签".tl: comicData.tags.keys.toList()};
  }

  @override
  void tapOnTag(String tag, String key) => context.to(() => SearchResultPage(
        keyword: tag,
        comicType: comicType,
      ));

  @override
  ThumbnailsData? get thumbnailsCreator {
    final comicData = data;
    if (comicData == null) return null;
    return ThumbnailsData(
        comicData.thumbnails,
        (page) => HtmangaNetwork().getThumbnails(comicData.id, page),
        (comicData.pages / 12).ceil());
  }

  @override
  String? get title => data?.name.removeAllBlank;

  @override
  Card? get uploaderInfo => Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.inversePrimary,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                flex: 0,
                child: Avatar(
                  size: 50,
                  avatarUrl: data?.avatar,
                  couldBeShown: false,
                  name: data?.uploader ?? "Unknown",
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 10, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data?.uploader ?? "Unknown",
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text("投稿作品${data?.uploadNum ?? 0}部")
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Future<bool> loadFavorite(HtComicInfo data) => Future.value(false);

  @override
  String get source => "绅士漫画".tl;

  @override
  FavoriteItem toLocalFavoriteItem([HtComicInfo? comicData]) {
    final comic = comicData ?? data;
    if (comic == null) {
      return FavoriteItem.fromHtcomic(HtComicBrief("", "", "", "", 0));
    }
    return FavoriteItem.fromHtcomic(comic.toBrief());
  }

  @override
  String get downloadedId => "Ht$id";

  @override
  ComicType get comicType => ComicType.htmanga;

  @override
  String get tag => "HtManga $id";
}



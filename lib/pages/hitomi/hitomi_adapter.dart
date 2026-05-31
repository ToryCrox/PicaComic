import 'package:flutter/material.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/log.dart';
import '../../foundation/ui_mode.dart';
import '../../network/hitomi_network/hitomi_download_model.dart';
import '../../network/hitomi_network/hitomi_main_network.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../network/hitomi_network/image.dart';
import '../../network/res.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';
import 'hitomi_search.dart';

// ============================================================================
// HitomiAdapter
// ============================================================================

class HitomiAdapter extends ComicPageAdapter<HitomiComic> {
  @override
  String get source => "hitomi";
  @override
  ComicType get comicType => ComicType.hitomi;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id) => "hitomi$id";
  @override
  String? url(HitomiComic data) => null;
  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  // -------- B. 数据加载 --------
  @override
  Future<Res<HitomiComic>> loadData(String id) async {
    final result = await HiNetwork().getComicInfo(id);
    if (result.success) DiskCache.writeModel(tag(id), result.data.toMap());
    return result;
  }

  @override
  Future<HitomiComic?> loadCachedData(String id) async {
    var data = await DiskCache.readModel(
      tag(id),
      (map) => HitomiComic.fromMap(map),
    );
    if (data != null) return data;
    final downloadedId = "hitomi$id";
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedHitomiComic) return downloaded.comic;
    }
    return null;
  }

  @override
  Future<bool> loadFavorite(HitomiComic data) async =>
      (await LocalFavoritesManager().findWithModel(
        toLocalFavoriteItem(data),
      )).isNotEmpty;

  // -------- C. 元数据提取 --------
  @override
  String? title(HitomiComic data) => data.title;
  @override
  String? subTitle(HitomiComic data) => null;
  @override
  String? cover(HitomiComic data) => data.cover;
  @override
  int? pages(HitomiComic data) => null;
  @override
  String? introduction(HitomiComic data) => null;
  @override
  bool? favoriteOnPlatformInitial(HitomiComic data) => null;
  @override
  String? commentsCount(HitomiComic data) => null;
  @override
  String? likeCount(HitomiComic data) => null;

  @override
  Map<String, List<String>>? tags(HitomiComic data) => {
    "Artists": data.artists ?? ["N/A"],
    "Groups": data.group,
    "Categories": data.type.toList(),
    "Time": data.time.toList(),
    "Languages": data.lang.toList(),
    "Tags": List.generate(data.tags.length, (i) => data.tags[i].name),
    "Series": data.parodys?.map((e) => e.name).toList() ?? [],
    "Characters": data.characters?.map((e) => e.name).toList() ?? [],
  };

  @override
  EpsData? eps(HitomiComic data, BuildContext context) => null;

  @override
  ThumbnailsData? createThumbnails(HitomiComic data) =>
      ThumbnailsData([], (page) async {
        try {
          var gg = GG();
          var images = <String>[];
          for (var file in data.files) {
            images.add(
              await gg.urlFromUrlFromHash(
                data.id,
                file,
                "webpsmallsmalltn",
                "webp",
              ),
            );
          }
          return Res(images);
        } catch (e, s) {
          Log.e("Network $e\n$s");
          return Res(null, errorMessage: e.toString());
        }
      }, 2);

  @override
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required HitomiComic data,
    List<String>? localImages,
  }) {
    if (localImages != null && index < localImages.length) {
      return PicaImage(
        url: Uri.file(localImages[index]).toString(),
        fit: BoxFit.contain,
        memCacheWidth: 200,
      );
    }
    return PicaImage(
      url: imageUrl,
      fit: BoxFit.contain,
      headers: {"sourceKey": comicType.name, "isThumbnail": "true"},
      memCacheWidth: 200,
    );
  }

  // -------- D. 操作 --------
  @override
  void read(HitomiComic data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage.hitomi(data, data.id, initialPage: h!.page),
    );
  }

  @override
  void download(HitomiComic data, BuildContext context) async {
    if (await downloadManager.isExists(data.id)) {
      showToast(message: "已下载".tl);
      return;
    }
    for (var i in downloadManager.downloading) {
      if (i.id == data.id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    downloadManager.addHitomiDownload(data, data.cover, data.id);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  void openFavoritePanel(
    HitomiComic data,
    ComicPageBridge bridge,
    BuildContext context,
  ) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: false,
      needLoadFolderData: false,
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      selectFolderCallback: (folder, _) {
        LocalFavoritesManager().addComic(folder, toLocalFavoriteItem(data));
        return Future.value(const Res(true));
      },
    );
    if (UiMode.m1(context)) {
      showModalBottomSheet(context: context, builder: (_) => widget);
    } else {
      showSideBar(
        App.globalContext!,
        widget,
        title: "收藏漫画".tl,
        useSurfaceTintColor: true,
      );
    }
  }

  @override
  ActionFunc? openComments(HitomiComic data, BuildContext context) => null;
  @override
  ActionFunc? onLike(HitomiComic data, BuildContext context) => null;
  @override
  bool isLiked(HitomiComic data) => false;
  @override
  ActionFunc? searchSimilar(HitomiComic data, BuildContext context) => null;

  @override
  void onTagTapped(
    String tag,
    String key,
    HitomiComic data,
    BuildContext context,
  ) {
    var t = tag;
    if (key == "Tags") {
      if (t.endsWith(' ♀')) {
        t = "female:${t.replaceLast(" ♀", "")}";
      } else if (t.endsWith('♂')) {
        t = "male:${t.replaceLast(" ♂", "")}";
      } else {
        t = "tag:$t";
      }
    }
    if (t.contains(" ")) t = t.replaceAll(' ', '_');
    String? param = switch (key) {
      "Artists" => "artist:$t",
      "Groups" => "group:$t",
      "Categories" => "type:$t",
      "Languages" => "language:$t",
      "Series" => "series:$t",
      "Characters" => "character:$t",
      "Tags" => t,
      "Time" => null,
      _ => null,
    };
    if (param != null && tag != "N/A") {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) =>
              SearchResultPage(keyword: param, comicType: comicType),
        ),
      );
    }
  }

  @override
  void onThumbnailTapped(
    int index,
    HitomiComic data,
    BuildContext context,
  ) async {
    await History.findOrCreate(data, page: index + 1);
    App.globalTo(
      () => ComicReadingPage.hitomi(data, data.id, initialPage: index + 1),
    );
  }

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(HitomiComic data, BuildContext context) =>
      SliverGrid(
        delegate: SliverChildBuilderDelegate(
          childCount: data.related.length,
          (_, i) => HitomiComicTileDynamicLoading(data.related[i]),
        ),
        gridDelegate: SliverGridDelegateWithComics(),
      );

  @override
  Card? buildUploaderInfo(HitomiComic data, BuildContext context) => null;
  @override
  Widget? buildMoreInfo(HitomiComic data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(
    HitomiComic data,
    BuildContext context,
    Widget Function(
      BuildContext,
      String,
      IconData,
      VoidCallback, [
      VoidCallback?,
    ])
    buildActionItem,
  ) => null;

  @override
  FavoriteItem toLocalFavoriteItem(HitomiComic data) =>
      FavoriteItem.fromHitomi(data.toBrief(data.id, data.cover));
}

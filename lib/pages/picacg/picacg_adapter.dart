import 'package:flutter/material.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../components/select_download_eps.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../network/download/download_model.dart';
import '../../network/picacg_network/methods.dart';
import '../../network/picacg_network/picacg_download_model.dart';
import '../../network/res.dart';
import '../../comic_source/built_in/picacg.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../../tools/type_util.dart';
import '../category_comics_page.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';
import 'comments_page.dart';

// ============================================================================
// PicacgAdapter
// ============================================================================

class PicacgAdapter extends ComicPageAdapter<ComicItem> {
  @override
  String get source => "Picacg";
  @override
  ComicType get comicType => ComicType.picacg;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id) => id;
  @override
  String? url(ComicItem data) => null;
  @override
  bool get supportThumbnails => false;

  // -------- B. 数据加载 --------
  @override
  Future<Res<ComicItem>> loadData(String id) => network.getComicInfo(id).then((
    res,
  ) {
    if (res.success) {
      DiskCache.writeString(tag(id), TypeUtil.parseString(res.data.toJson()));
    }
    return res;
  });

  @override
  Future<ComicItem?> loadCachedData(String id) async {
    return DiskCache.readModel(tag(id), (map) => ComicItem.fromJson(map));
  }

  @override
  ComicItem? dataFromDownloadedItem(DownloadedItem item) =>
      item is DownloadedComic ? item.comicItem : null;

  @override
  DownloadedItem? mergeDownloadedItem(DownloadedItem item, ComicItem data) {
    if (item is! DownloadedComic) return null;
    return DownloadedComic(
      data,
      List<String>.from(data.eps),
      item.comicSize,
      List<int>.from(item.downloadedEps),
      color: item.color,
    );
  }

  @override
  Future<bool> loadFavorite(ComicItem data) async =>
      data.isFavourite ||
      (await LocalFavoritesManager().findWithModel(
        toLocalFavoriteItem(data),
      )).isNotEmpty;

  // -------- C. 元数据提取 --------
  @override
  String? title(ComicItem data) => data.title;
  @override
  String? subTitle(ComicItem data) => null;
  @override
  String? cover(ComicItem data) => data.thumbUrl;
  @override
  int? pages(ComicItem data) => data.pagesCount;
  @override
  String? introduction(ComicItem data) => data.description;
  @override
  bool? favoriteOnPlatformInitial(ComicItem data) => data.isFavourite;
  @override
  String? commentsCount(ComicItem data) => data.comments.toString();
  @override
  String? likeCount(ComicItem data) => data.likes.toString();

  @override
  Map<String, List<String>>? tags(ComicItem data) => {
    "作者".tl: data.author.toList(),
    "汉化".tl: data.chineseTeam.toList(),
    "分类".tl: data.categories,
    "标签".tl: data.tags,
  };

  @override
  EpsData? eps(ComicItem data, BuildContext context) =>
      EpsData(data.eps, (i) async {
        await History.findOrCreate(data);
        App.globalTo(
          () => ComicReadingPage.picacg(data.id, i + 1, data.eps, data.title),
        );
      });

  @override
  ThumbnailsData? createThumbnails(ComicItem data) => null;

  @override
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required ComicItem data,
    List<String>? localImages,
  }) => const SizedBox.shrink();

  // -------- D. 操作 --------
  @override
  void read(ComicItem data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage.picacg(
        data.id,
        h!.ep,
        data.eps,
        data.title,
        initialPage: h.page,
      ),
    );
  }

  @override
  void download(ComicItem data, BuildContext context) {
    _downloadComic(data, context);
  }

  @override
  void openFavoritePanel(
    ComicItem data,
    ComicPageBridge bridge,
    BuildContext context,
  ) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: picacg.isLogin,
      needLoadFolderData: false,
      folders: const {"Picacg": "Picacg"},
      initialFolder: data.isFavourite ? null : "Picacg",
      favoriteOnPlatform: data.isFavourite,
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      cancelPlatformFavorite: () async {
        var res = await network.favouriteOrUnfavouriteComic(data.id);
        if (res) {
          data.isFavourite = false;
          return const Res(true);
        }
        return Res.error("网络错误".tl);
      },
      selectFolderCallback: (name, p) async {
        if (p == 0) {
          var res = await network.favouriteOrUnfavouriteComic(data.id);
          if (res) {
            data.isFavourite = true;
            bridge.updateState();
            return const Res(true);
          }
          return Res.error("网络错误".tl);
        }
        LocalFavoritesManager().addComic(name, toLocalFavoriteItem(data));
        return const Res(true);
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
  ActionFunc? openComments(ComicItem data, BuildContext context) =>
      () => showComments(App.globalContext!, data.id);

  @override
  ActionFunc? onLike(ComicItem data, BuildContext context) => () {
    network.likeOrUnlikeComic(data.id);
    data.isLiked = !data.isLiked;
  };

  @override
  bool isLiked(ComicItem data) => data.isLiked;
  @override
  ActionFunc? searchSimilar(ComicItem data, BuildContext context) => null;

  @override
  void onTagTapped(
    String tag,
    String key,
    ComicItem data,
    BuildContext context,
  ) {
    if (data.categories.contains(tag)) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) =>
              CategoryComicsPage(category: tag, comicType: ComicType.picacg),
        ),
      );
    } else if (data.author == tag) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => CategoryComicsPage(
            category: tag,
            param: "a",
            comicType: ComicType.picacg,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => SearchResultPage(keyword: tag, comicType: comicType),
        ),
      );
    }
  }

  @override
  void onThumbnailTapped(int index, ComicItem data, BuildContext context) {}

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(ComicItem data, BuildContext context) =>
      SliverGridComics(comics: data.recommendation, comicType: comicType);

  @override
  Card? buildUploaderInfo(ComicItem data, BuildContext context) => Card(
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
              avatarUrl: data.creator.avatarUrl,
              frame: data.creator.frameUrl,
              couldBeShown: true,
              name: data.creator.name,
              slogan: data.creator.slogan,
              level: data.creator.level,
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
                    data.creator.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    "${data.time.substring(0, 10)} ${data.time.substring(11, 19)}更新",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget? buildMoreInfo(ComicItem data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(
    ComicItem data,
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
  FavoriteItem toLocalFavoriteItem(ComicItem data) => FavoriteItem(
    target: data.id,
    name: data.title,
    coverPath: data.thumbUrl,
    author: data.author,
    type: FavoriteType.picacg,
    tags: data.tags,
  );

  // -------- 下载辅助 --------
  void _downloadComic(ComicItem comic, BuildContext context) async {
    for (var i in downloadManager.downloading) {
      if (i.id == comic.id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    var downloaded = <int>[];
    if (await downloadManager.isExists(comic.id)) {
      var dc =
          (await downloadManager.getComicOrNull(comic.id))! as DownloadedComic;
      downloaded.addAll(dc.downloadedEps);
    }
    final content = SelectDownloadChapter(
      comic.eps,
      (selectedEps) {
        downloadManager.addPicDownload(comic, selectedEps);
        App.globalBack();
        showToast(message: "已加入下载队列".tl);
      },
      downloaded,
      onEpisodeDelete: (ep) async {
        var dc = await downloadManager.getComicOrNull(comic.id);
        if (dc != null) {
          if (dc.downloadedEps.length == 1) {
            await downloadManager.delete([comic.id]);
          } else {
            await downloadManager.deleteEpisode(dc, ep);
          }
        }
      },
    );
    if (UiMode.m1(App.globalContext!)) {
      showModalBottomSheet(
        context: App.globalContext!,
        builder: (_) => content,
      );
    } else {
      showSideBar(App.globalContext!, content, useSurfaceTintColor: true);
    }
  }
}

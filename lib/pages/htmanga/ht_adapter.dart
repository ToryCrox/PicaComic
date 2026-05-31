import 'package:flutter/material.dart';

import '../../base.dart';
import '../../comic_source/built_in/ht_manga.dart';
import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../network/htmanga_network/ht_download_model.dart';
import '../../network/htmanga_network/htmanga_main_network.dart';
import '../../network/htmanga_network/models.dart';
import '../../network/res.dart';
import '../../foundation/ui_mode.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';

// ============================================================================
// HtAdapter — 绅士漫画
// ============================================================================

class HtAdapter extends ComicPageAdapter<HtComicInfo> {
  @override
  String get source => "绅士漫画".tl;
  @override
  ComicType get comicType => ComicType.htmanga;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id) => "Ht$id";
  @override
  String? url(HtComicInfo data) => null;

  // -------- B. 数据加载 --------
  @override
  Future<Res<HtComicInfo>> loadData(String id) =>
      HtmangaNetwork().getComicInfo(id).then((res) {
        if (res.success) DiskCache.writeModel(tag(id), res.data.toJson());
        return res;
      });

  @override
  Future<HtComicInfo?> loadCachedData(String id) async {
    var data = await DiskCache.readModel(
      tag(id),
      (map) => HtComicInfo.fromJson(map),
    );
    if (data != null) return data;
    final downloadedId = "Ht$id";
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedHtComic) return downloaded.comic;
    }
    return null;
  }

  @override
  Future<bool> loadFavorite(HtComicInfo data) => Future.value(false);

  // -------- C. 元数据提取 --------
  @override
  String? title(HtComicInfo data) => data.name.removeAllBlank;
  @override
  String? subTitle(HtComicInfo data) => null;
  @override
  String? cover(HtComicInfo data) => data.cover;
  @override
  int? pages(HtComicInfo data) => null;
  @override
  String? introduction(HtComicInfo data) => data.description;
  @override
  bool? favoriteOnPlatformInitial(HtComicInfo data) => null;
  @override
  String? commentsCount(HtComicInfo data) => null;
  @override
  String? likeCount(HtComicInfo data) => null;

  @override
  Map<String, List<String>>? tags(HtComicInfo data) => {
    "分类".tl: data.category.toList(),
    "标签".tl: data.tags.keys.toList(),
  };

  @override
  EpsData? eps(HtComicInfo data, BuildContext context) => null;

  @override
  ThumbnailsData? createThumbnails(HtComicInfo data) => ThumbnailsData(
    data.thumbnails,
    (page) => HtmangaNetwork().getThumbnails(data.id, page),
    (data.pages / 12).ceil(),
  );

  @override
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required HtComicInfo data,
    List<String>? localImages,
  }) {
    var url = imageUrl;
    if (localImages != null && index < localImages.length) {
      url = Uri.file(localImages[index]).toString();
    }
    return PicaImage(
      url: url,
      fit: BoxFit.contain,
      headers: {"sourceKey": comicType.name, "isThumbnail": "true"},
      memCacheWidth: 200,
    );
  }

  // -------- D. 操作 --------
  @override
  void read(HtComicInfo data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage.htmanga(
        data.target,
        data.title,
        initialPage: h!.page,
      ),
    );
  }

  @override
  void download(HtComicInfo data, BuildContext context) async {
    final id = "Ht${data.id}";
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
    downloadManager.addHtDownload(data);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  void openFavoritePanel(
    HtComicInfo data,
    ComicPageBridge bridge,
    BuildContext context,
  ) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: htManga.isLogin,
      needLoadFolderData: true,
      foldersLoader: () => HtmangaNetwork().getFolders(),
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {},
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          return HtmangaNetwork().addFavorite(data.id, folder);
        }
        LocalFavoritesManager().addComic(
          folder,
          FavoriteItem.fromHtcomic(data.toBrief()),
        );
        return const Res(true);
      },
    );
    _showFavoriteSheet(context, widget);
  }

  @override
  ActionFunc? openComments(HtComicInfo data, BuildContext context) => null;
  @override
  ActionFunc? onLike(HtComicInfo data, BuildContext context) => null;
  @override
  bool isLiked(HtComicInfo data) => false;
  @override
  ActionFunc? searchSimilar(HtComicInfo data, BuildContext context) => null;

  @override
  void onTagTapped(
    String tag,
    String key,
    HtComicInfo data,
    BuildContext context,
  ) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => SearchResultPage(keyword: tag, comicType: comicType),
      ),
    );
  }

  @override
  void onThumbnailTapped(
    int index,
    HtComicInfo data,
    BuildContext context,
  ) async {
    await History.findOrCreate(data);
    App.globalTo(
      () => ComicReadingPage.htmanga(
        data.target,
        data.title,
        initialPage: index + 1,
      ),
    );
  }

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(HtComicInfo data, BuildContext context) => null;

  @override
  Card? buildUploaderInfo(HtComicInfo data, BuildContext context) => Card(
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
              avatarUrl: data.avatar,
              couldBeShown: false,
              name: data.uploader,
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
                    data.uploader,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text("投稿作品${data.uploadNum}部"),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget? buildMoreInfo(HtComicInfo data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(
    HtComicInfo data,
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
  FavoriteItem toLocalFavoriteItem(HtComicInfo data) =>
      FavoriteItem.fromHtcomic(data.toBrief());

  void _showFavoriteSheet(BuildContext context, FavoriteComicWidget widget) {
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
}

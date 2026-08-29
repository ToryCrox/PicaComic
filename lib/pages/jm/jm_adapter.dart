import 'package:flutter/material.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../components/select_download_eps.dart';
import '../../comic_source/built_in/jm.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/def.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../network/download/download_model.dart';
import '../../network/jm_network/jm_image.dart';
import '../../network/jm_network/jm_download.dart';
import '../../network/jm_network/jm_models.dart';
import '../../network/jm_network/jm_network.dart';
import '../../network/res.dart';
import '../../tools/extensions.dart';
import '../../tools/translations.dart';
import '../../tools/type_util.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import 'jm_comments_page.dart';

// ============================================================================
// JmAdapter — 禁漫天堂
// ============================================================================

class JmAdapter extends ComicPageAdapter<JmComicInfo> {
  // -------- A. 核心标识 --------
  @override
  String get source => "禁漫天堂".tl;
  @override
  ComicType get comicType => ComicType.jm;
  @override
  String tag(String id) => comicPageTag(comicType, id);
  @override
  String downloadId(String id) => "jm$id";
  @override
  String? url(JmComicInfo data) => null;

  // -------- B. 数据加载 --------
  @override
  Future<Res<JmComicInfo>> loadData(String id) =>
      JmNetwork().getComicInfo(id).then((res) {
        if (res.success) {
          DiskCache.writeString(
            tag(id),
            TypeUtil.parseString(res.data.toJson()),
          );
        }
        return res;
      });

  @override
  Future<JmComicInfo?> loadCachedData(String id) async {
    return DiskCache.readModel(tag(id), (map) => JmComicInfo.fromMap(map));
  }

  @override
  JmComicInfo? dataFromDownloadedItem(DownloadedItem item) =>
      item is DownloadedJmComic ? item.comic : null;

  @override
  DownloadedItem? mergeDownloadedItem(DownloadedItem item, JmComicInfo data) {
    if (item is! DownloadedJmComic) return null;
    return DownloadedJmComic(
      data,
      item.comicSize,
      List<int>.from(item.downloadedEps),
      color: item.color,
    );
  }

  @override
  Future<bool> loadFavorite(JmComicInfo data) async =>
      data.favorite ||
      (await LocalFavoritesManager().findWithModel(
        toLocalFavoriteItem(data),
      )).isNotEmpty;

  // -------- C. 元数据提取 --------
  @override
  String? title(JmComicInfo data) => data.name;
  @override
  String? subTitle(JmComicInfo data) => null;
  @override
  String? cover(JmComicInfo data) => getJmCoverUrl(data.id);
  @override
  int? pages(JmComicInfo data) => null;
  @override
  String? introduction(JmComicInfo data) => data.description;
  @override
  bool get supportThumbnails => false;

  @override
  Map<String, List<String>>? tags(JmComicInfo data) => {
    "ID": "JM${data.id}".toList(),
    "作者".tl: data.author.isEmpty ? "未知".tl.toList() : data.author,
    if (data.works.isNotEmpty) "作品".tl: data.works,
    if (data.actors.isNotEmpty) "登场人物".tl: data.actors,
    if (data.tags.isNotEmpty) "标签".tl: data.tags,
  };

  @override
  EpsData? eps(JmComicInfo data, BuildContext context) {
    String epName(int i) {
      final n = data.epNames.elementAtOrNull(i);
      if (n != null) return n;
      return "第 @c 章".tlParams({"c": (i + 1).toString()});
    }

    return EpsData(List.generate(data.series.values.length, (i) => epName(i)), (
      i,
    ) async {
      await History.findOrCreate(data);
      App.globalTo(() => ComicReadingPage.jmComic(data, i + 1));
    });
  }

  @override
  bool? favoriteOnPlatformInitial(JmComicInfo data) => data.favorite;
  @override
  ThumbnailsData? createThumbnails(JmComicInfo data) => null;
  @override
  String? commentsCount(JmComicInfo data) => null;
  @override
  String? likeCount(JmComicInfo data) =>
      data.likes.toString().replaceLast("000", "K");

  @override
  Widget buildThumbnailImage(
    int index,
    String imageUrl,
    BuildContext context, {
    required JmComicInfo data,
    List<String>? localImages,
  }) {
    return const SizedBox.shrink();
  }

  // -------- D. 操作 --------
  @override
  void read(JmComicInfo data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage.jmComic(data, h!.ep, initialPage: h.page),
    );
  }

  @override
  void download(JmComicInfo data, BuildContext context) {
    _downloadComic(data, context);
  }

  @override
  void openFavoritePanel(
    JmComicInfo data,
    ComicPageBridge bridge,
    BuildContext context,
  ) {
    _showFavoriteSheet(
      bridge,
      context,
      data: data,
      id: data.id,
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await jmNetwork.favorite(data.id, folder);
          if (res.success) {
            data = data.copyWith(favorite: true);
            bridge.updateData(data);
            bridge.updateState();
          }
          return res;
        }
        LocalFavoritesManager().addComic(folder, toLocalFavoriteItem(data));
        return const Res(true);
      },
      cancelPlatformFavorite: () async {
        var res = await jmNetwork.favorite(data.id, null);
        if (res.success) {
          data = data.copyWith(favorite: false);
          bridge.updateData(data);
          bridge.updateState();
        }
        return res;
      },
      foldersLoader: () async {
        var res = await jmNetwork.getFolders();
        if (res.error) return res;
        var resData = <String, String>{"0": "全部收藏".tl};
        resData.addAll(res.data);
        return Res(resData);
      },
      havePlatformFavorite: jm.isLogin,
      needLoadFolderData: true,
      favoriteOnPlatformFromData: data.favorite,
    );
  }

  @override
  ActionFunc? openComments(JmComicInfo data, BuildContext context) => () {
    showComments(App.globalContext!, data.id, data.comments);
  };

  @override
  ActionFunc? onLike(
    JmComicInfo data,
    ComicPageBridge bridge,
    BuildContext context,
  ) => () {
    if (!data.liked) jmNetwork.likeComic(data.id);
    bridge.updateData(data.copyWith(liked: true));
  };

  @override
  bool isLiked(JmComicInfo data) => data.liked;

  @override
  ActionFunc? searchSimilar(JmComicInfo data, BuildContext context) => null;

  @override
  void onTagTapped(
    String tag,
    String key,
    JmComicInfo data,
    BuildContext context,
  ) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => SearchResultPage(keyword: tag, comicType: comicType),
      ),
    );
  }

  @override
  void onThumbnailTapped(int index, JmComicInfo data, BuildContext context) {}

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(JmComicInfo data, BuildContext context) =>
      SliverGridComics(comics: data.relatedComics, comicType: comicType);

  @override
  Card? buildUploaderInfo(JmComicInfo data, BuildContext context) => null;
  @override
  Widget? buildMoreInfo(JmComicInfo data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(
    JmComicInfo data,
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
  FavoriteItem toLocalFavoriteItem(JmComicInfo data) =>
      FavoriteItem.fromJmComic(
        JmComicBrief(
          id: data.id,
          author: data.author.elementAtOrNull(0) ?? "",
          name: data.name,
          description: data.description,
          categories: const [],
        ),
      );

  // -------- 下载辅助 --------
  void _downloadComic(JmComicInfo comic, BuildContext context) async {
    for (var i in downloadManager.downloading) {
      if (i.id == comic.id) {
        showToast(message: "下载中".tl);
        return;
      }
    }
    List<String> eps = [];
    if (comic.series.isEmpty) {
      eps.add("第1章".tl);
    } else {
      eps = List.generate(
        comic.series.length,
        (i) => "第 @c 章".tlParams({"c": (i + 1).toString()}),
      );
    }
    var downloaded = <int>[];
    final dc = await downloadManager.getComicOrNull("jm${comic.id}");
    if (dc != null) downloaded.addAll(dc.downloadedEps);

    final child = SelectDownloadChapter(
      eps,
      (selectedEps) {
        downloadManager.addJmDownload(comic, selectedEps);
        App.globalBack();
        showToast(message: "已加入下载队列".tl);
      },
      downloaded,
      onEpisodeDelete: (ep) async {
        var dc = await downloadManager.getComicOrNull("jm${comic.id}");
        if (dc != null) {
          if (dc.downloadedEps.length == 1) {
            await downloadManager.delete(["jm${comic.id}"]);
          } else {
            await downloadManager.deleteEpisode(dc, ep);
          }
        }
      },
    );

    if (UiMode.m1(App.globalContext!)) {
      showModalBottomSheet(context: App.globalContext!, builder: (_) => child);
    } else {
      showSideBar(App.globalContext!, child, useSurfaceTintColor: true);
    }
  }

  // -------- 收藏面板辅助（统一UI逻辑） --------
  void _showFavoriteSheet(
    ComicPageBridge bridge,
    BuildContext context, {
    required JmComicInfo data,
    required String id,
    required Future<Res<bool>> Function(String, int)? selectFolderCallback,
    required Future<Res<bool>> Function()? cancelPlatformFavorite,
    required Future<Res<Map<String, String>>> Function()? foldersLoader,
    required bool havePlatformFavorite,
    required bool needLoadFolderData,
    required bool favoriteOnPlatformFromData,
  }) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: havePlatformFavorite,
      needLoadFolderData: needLoadFolderData,
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      foldersLoader: foldersLoader,
      localFavoriteItem: toLocalFavoriteItem(data),
      favoriteOnPlatform: favoriteOnPlatformFromData,
      selectFolderCallback: selectFolderCallback,
      cancelPlatformFavorite: cancelPlatformFavorite,
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
}

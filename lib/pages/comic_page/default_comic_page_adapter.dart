import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../base.dart';
import '../../components/components.dart';
import '../../components/select_download_eps.dart';
import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../foundation/app_page_route.dart';
import '../../foundation/def.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../network/base_comic.dart';
import '../../network/res.dart';
import '../../tools/translations.dart';
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import 'comic_page_adapter.dart';
import 'comic_page_logic.dart';

import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;

// ============================================================================
// DefaultComicPageAdapter — 通用适配器，处理 ComicInfoData
// ============================================================================

/// 当某个 [ComicType] 未注册专用适配器时使用此默认适配器。
///
/// 通过 [ComicSource] 动态获取来源特定的数据加载、收藏等功能。
class DefaultComicPageAdapter extends ComicPageAdapter<ComicInfoData> {
  DefaultComicPageAdapter(this._comicType);

  final ComicType _comicType;

  ComicSource? get _source => ComicSource.find(_comicType);

  // -------- A. 核心标识 --------

  @override
  String get source => _source?.name ?? _comicType.name;

  @override
  ComicType get comicType => _comicType;

  @override
  String tag(String id) => "${comicType.name} comic page with id: $id";

  @override
  String downloadId(String id) =>
      downloadManager.getDownloadIdFromComicId(comicType, id);

  @override
  String? url(ComicInfoData data) => null;

  // -------- B. 数据加载 --------

  @override
  Future<Res<ComicInfoData>> loadData(String id) async {
    if (_source?.loadComicInfo == null) {
      return const Res(null, errorMessage: "Comic Source Not Found");
    }
    return _source!.loadComicInfo!(id);
  }

  @override
  Future<ComicInfoData?> loadCachedData(String id) =>
      SynchronousFuture(null);

  @override
  Future<bool> loadFavorite(ComicInfoData data) async =>
      data.isFavorite ?? false;

  // -------- C. 元数据提取 --------

  @override
  String? title(ComicInfoData data) => data.title;

  @override
  String? subTitle(ComicInfoData data) => data.subTitle;

  @override
  String? cover(ComicInfoData data) => data.cover;

  @override
  int? pages(ComicInfoData data) => null;

  @override
  String? introduction(ComicInfoData data) => data.description;

  @override
  Map<String, List<String>>? tags(ComicInfoData data) => data.tags;

  @override
  EpsData? eps(ComicInfoData data, BuildContext context) {
    if (data.chapters == null || data.chapters!.isEmpty) return null;
    return EpsData(
      data.chapters!.values.toList(),
      (ep) async {
        await History.findOrCreate(data);
        App.globalTo(
          () => ComicReadingPage(
            CustomReadingData(
              data.target,
              data.title,
              _source!,
              data.chapters,
            ),
            0,
            ep + 1,
          ),
        );
      },
    );
  }

  @override
  bool? favoriteOnPlatformInitial(ComicInfoData data) => data.isFavorite;

  @override
  bool get supportThumbnails => true;

  @override
  ThumbnailsData? createThumbnails(ComicInfoData data) {
    if (data.thumbnails == null && data.thumbnailLoader == null) return null;
    return ThumbnailsData(
      data.thumbnails ?? [],
      (page) =>
          data.thumbnailLoader?.call(data.comicId, page) ??
          Future.value(const Res.error("")),
      data.thumbnailMaxPage,
    );
  }

  @override
  String? commentsCount(ComicInfoData data) => null;

  @override
  String? likeCount(ComicInfoData data) => null;

  @override
  Widget buildThumbnailImage(int index, String imageUrl, BuildContext context,
      {required ComicInfoData data, List<String>? localImages}) {
    var url = imageUrl;
    if (localImages != null && index < localImages.length) {
      url = Uri.file(localImages[index]).toString();
    }
    return PicaImage(
      url: url,
      headers: {
        "sourceKey": comicType.name,
        "isThumbnail": "true",
      },
      fit: BoxFit.contain,
      memCacheWidth: 200,
    );
  }

  // -------- D. 操作 --------

  @override
  void read(ComicInfoData data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage(
        CustomReadingData(
          data.target,
          data.title,
          _source!,
          data.chapters,
        ),
        h!.page,
        h.ep,
      ),
    );
  }

  @override
  void download(ComicInfoData data, BuildContext context) {
    final downloadId =
        downloadManager.getDownloadIdFromComicId(comicType, data.comicId);
    final eps = data.chapters?.values.toList();

    for (var i in downloadManager.downloading) {
      if (i.id == downloadId) {
        showToast(message: "下载中".tl);
        return;
      }
    }

    var downloaded = <int>[];
    downloadManager.isExists(downloadId).then((exists) async {
      if (exists) {
        if (eps == null) {
          showToast(message: "已下载".tl);
          return;
        }
        var downloadedComic =
            await downloadManager.getComicOrNull(downloadId);
        downloaded.addAll(downloadedComic!.downloadedEps);
      } else {
        if (eps == null) {
          downloadManager.addCustomDownload(data, [0]);
          App.globalBack();
          showToast(message: "已加入下载队列".tl);
          return;
        }
      }

      final child = SelectDownloadChapter(
        eps,
        (selectedEps) {
          downloadManager.addCustomDownload(data, selectedEps);
          App.globalBack();
          showToast(message: "已加入下载队列".tl);
        },
        downloaded,
        onEpisodeDelete: (ep) async {
          var dc = await downloadManager.getComicOrNull(downloadId);
          if (dc != null) {
            if (dc.downloadedEps.length == 1) {
              await downloadManager.delete([downloadId]);
            } else {
              await downloadManager.deleteEpisode(dc, ep);
            }
          }
        },
      );
      if (UiMode.m1(App.globalContext!)) {
        showModalBottomSheet(
          context: App.globalContext!,
          builder: (ctx) => child,
        );
      } else {
        showSideBar(
          App.globalContext!,
          child,
          useSurfaceTintColor: true,
        );
      }
    });
  }

  @override
  void openFavoritePanel(
      ComicInfoData data, ComicPageBridge bridge, BuildContext context) {
    final source = _source;
    final widget = FavoriteComicWidget(
      havePlatformFavorite:
          source?.favoriteData != null && source!.isLogin,
      needLoadFolderData: source?.favoriteData?.multiFolder ?? false,
      folders: {
        if (!(source?.favoriteData?.multiFolder ?? false))
          '0': source?.name ?? '',
      },
      foldersLoader: source?.favoriteData?.loadFolders == null
          ? null
          : () => source!.favoriteData!.loadFolders!(data.comicId),
      initialFolder:
          (source?.favoriteData?.multiFolder ?? false) ? null : '0',
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      favoriteOnPlatform: data.isFavorite,
      selectFolderCallback: (folder, type) async {
        if (type == 1) {
          LocalFavoritesManager()
              .addComic(folder, toLocalFavoriteItem(data));
          return const Res(true);
        }
        final res = await source?.favoriteData?.addOrDelFavorite?.call(
            data.comicId, folder, true);
        return res ?? const Res.error("Not supported");
      },
      cancelPlatformFavorite: () async {
        final res = await source?.favoriteData?.addOrDelFavorite?.call(
            data.comicId, '0', false);
        return res ?? const Res.error("");
      },
      cancelPlatformFavoriteWithFolder: (folder) {
        return source?.favoriteData?.addOrDelFavorite?.call(
                data.comicId, folder, false) ??
            Future.value(const Res.error(""));
      },
    );
    if (UiMode.m1(context)) {
      showModalBottomSheet(context: context, builder: (_) => widget);
    } else {
      showSideBar(App.globalContext!, widget,
          title: "收藏漫画".tl, useSurfaceTintColor: true);
    }
  }

  @override
  ActionFunc? openComments(ComicInfoData data, BuildContext context) {
    final source = _source;
    if (source?.commentsLoader == null) return null;
    return () {
      showSideBar(
        App.globalContext!,
        // 延迟导入 comments page
        _buildCommentsPage(data, source!),
        title: "评论".tl,
      );
    };
  }

  // _CommentsPage 在 comic_page.dart 中定义，无法直接 import（会产生循环依赖）
  // 因此保留在 comic_page.dart 中，此处不做处理
  Widget _buildCommentsPage(ComicInfoData data, ComicSource source) {
    // 委托给 comic_page.dart 中的 _CommentsPage
    throw UnimplementedError(
        'Comments page is implemented in comic_page.dart');
  }

  @override
  ActionFunc? onLike(ComicInfoData data, BuildContext context) => null;

  @override
  bool isLiked(ComicInfoData data) => false;

  @override
  ActionFunc? searchSimilar(ComicInfoData data, BuildContext context) => null;

  @override
  void onTagTapped(
      String tag, String key, ComicInfoData data, BuildContext context) {
    Navigator.of(context).push(AppPageRoute(
      builder: (context) => SearchResultPage(
        keyword: tag,
        options: const [],
        comicType: comicType,
      ),
    ));
  }

  @override
  void onThumbnailTapped(
      int index, ComicInfoData data, BuildContext context) async {
    await History.findOrCreate(data);
    App.globalTo(
      () => ComicReadingPage(
        CustomReadingData(
          data.target,
          data.title,
          _source!,
          data.chapters,
        ),
        index + 1,
        1,
      ),
    );
  }

  // -------- E. 自定义UI & 转换 --------

  @override
  Widget? buildRecommendation(ComicInfoData data, BuildContext context) {
    if (data.suggestions == null) return null;
    return SliverGridComics(comics: data.suggestions!, comicType: comicType);
  }

  @override
  Card? buildUploaderInfo(ComicInfoData data, BuildContext context) => null;

  @override
  Widget? buildMoreInfo(ComicInfoData data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(ComicInfoData data,
      BuildContext context,
      Widget Function(BuildContext, String, IconData, VoidCallback,
              [VoidCallback?])
          buildActionItem) =>
      null;

  @override
  FavoriteItem toLocalFavoriteItem(ComicInfoData data) {
    var tags = <String>[];
    data.tags.forEach((key, value) => tags.addAll(value));
    return FavoriteItem.fromBaseComic(CustomComic(data.title,
        data.subTitle ?? "", data.cover, data.comicId, tags, "", comicType.name));
  }

}

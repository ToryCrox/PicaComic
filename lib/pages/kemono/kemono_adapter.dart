import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../base.dart';
import '../../foundation/app_page_route.dart';
import '../../components/components.dart';
import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../foundation/def.dart';
import '../../foundation/history.dart';
import '../../foundation/ui_mode.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/pica_image_manager.dart';
import '../../network/kemono_network/kemono_main_network.dart';
import '../../network/res.dart';
import '../../tools/translations.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';

// ============================================================================
// KemonoAdapter
// ============================================================================

class KemonoAdapter extends ComicPageAdapter<KemonoPost> {
  @override String get source => "Kemono";
  @override ComicType get comicType => ComicType.kemono;
  @override String tag(String id) => "Kemono $id";
  @override String downloadId(String id) =>
      downloadManager.getDownloadIdFromComicId(comicType, id);
  @override String? url(KemonoPost data) => null;
  @override bool get supportThumbnails => true;

  // -------- B. 数据加载 --------
  @override
  Future<Res<KemonoPost>> loadData(String id) async {
    final parts = id.split('/');
    if (parts.length != 3) {
      return const Res(null, errorMessage: 'Invalid ID format');
    }
    return KemonoNetwork().getPostDetail(parts[0], parts[1], parts[2]);
  }

  @override Future<KemonoPost?> loadCachedData(String id) =>
      SynchronousFuture(null);

  @override
  Future<bool> loadFavorite(KemonoPost data) async =>
      (await LocalFavoritesManager()
              .findWithModel(toLocalFavoriteItem(data)))
          .isNotEmpty;

  // -------- C. 元数据提取 --------
  @override String? title(KemonoPost data) => data.title;
  @override String? subTitle(KemonoPost data) => data.userName;
  @override String? cover(KemonoPost data) => data.cover;
  @override int? pages(KemonoPost data) => null;
  @override String? introduction(KemonoPost data) => data.content;
  @override bool? favoriteOnPlatformInitial(KemonoPost data) => null;
  @override String? commentsCount(KemonoPost data) => null;
  @override String? likeCount(KemonoPost data) => null;

  @override
  Map<String, List<String>>? tags(KemonoPost data) => {
    "Service": [data.service],
    "User": [data.userName],
  };

  @override EpsData? eps(KemonoPost data, BuildContext context) => null;

  @override
  ThumbnailsData? createThumbnails(KemonoPost data) {
    if (data.thumbnailUrls.isEmpty) return null;
    return ThumbnailsData(
      data.thumbnailUrls,
      (page) async => Res(data.thumbnailUrls),
      1,
    );
  }

  @override
  Widget buildThumbnailImage(int index, String imageUrl, BuildContext context,
      {List<String>? localImages}) {
    // Kemono 使用 CachedNetworkImage 而非 PicaImage
    return Image(
      image: CachedNetworkImageProvider(imageUrl,
          headers: KemonoNetwork.getImageHeaders(),
          cacheManager: picaImageManager),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const Center(child: Icon(Icons.error)),
    );
  }

  // -------- D. 操作 --------
  @override
  void read(KemonoPost data, History? history, BuildContext context) async {
    if (data.imageUrls.isEmpty) {
      showToast(message: "没有图片".tl);
      return;
    }
    final h = await History.createIfNull(history, data);
    App.globalTo(
      () => ComicReadingPage(
        CustomReadingData(
            data.target, data.title, ComicSource.find(comicType)!, null),
        h!.page,
        h.ep,
      ),
    );
  }

  @override
  void download(KemonoPost data, BuildContext context) async {
    final dId = downloadManager.getDownloadIdFromComicId(comicType, data.target);
    if (downloadManager.downloading.any((e) => e.id == dId)) {
      showToast(message: "下载中".tl);
      return;
    }
    if (await downloadManager.isExists(dId)) {
      showToast(message: "已下载".tl);
      return;
    }

    final comicData = ComicInfoData(
      data.title,
      data.userName,
      data.cover,
      data.content,
      tags(data) ?? {},
      null,
      data.imageUrls,
      null,
      0,
      null,
      comicType.name,
      data.target,
    );
    downloadManager.addCustomDownload(comicData, [0]);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  void openFavoritePanel(
      KemonoPost data, ComicPageBridge bridge, BuildContext context) {
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
      showSideBar(App.globalContext!, widget,
          title: "收藏漫画".tl, useSurfaceTintColor: true);
    }
  }

  @override ActionFunc? openComments(KemonoPost data, BuildContext context) => null;
  @override ActionFunc? onLike(KemonoPost data, BuildContext context) => null;
  @override bool isLiked(KemonoPost data) => false;
  @override ActionFunc? searchSimilar(KemonoPost data, BuildContext context) => null;

  @override
  void onTagTapped(
      String tag, String key, KemonoPost data, BuildContext context) {
    Navigator.of(context).push(AppPageRoute(
      builder: (_) => SearchResultPage(keyword: tag, comicType: comicType)));
  }

  @override
  void onThumbnailTapped(
      int index, KemonoPost data, BuildContext context) async {
    if (data.imageUrls.isEmpty) return;
    await History.findOrCreate(data, page: index + 1);
    App.globalTo(
      () => ComicReadingPage(
        CustomReadingData(
            data.target, data.title, ComicSource.find(comicType)!, null),
        index + 1,
        1,
      ),
    );
  }

  // -------- E. 自定义UI & 转换 --------
  @override Widget? buildRecommendation(KemonoPost data, BuildContext context) => null;
  @override Card? buildUploaderInfo(KemonoPost data, BuildContext context) => null;
  @override Widget? buildMoreInfo(KemonoPost data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(KemonoPost data, BuildContext context,
      Widget Function(BuildContext, String, IconData, VoidCallback, [VoidCallback?])
          buildActionItem) {
    return [
      buildActionItem(context, "附件下载".tl, Icons.attach_file, () {
        if (data.attachments.isEmpty) {
          showToast(message: "没有附件".tl);
          return;
        }
        // Show attachment download dialog
        showDialog(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text("选择保存位置".tl),
            children: [
              for (var attachment in data.attachments)
                ListTile(
                  title: Text(attachment.name),
                  subtitle: Text(attachment.path),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    showToast(message: "附件下载功能暂未迁移".tl);
                  },
                ),
            ],
          ),
        );
      }),
      buildActionItem(context, "在网页中打开".tl, Icons.open_in_browser, () {
        launchUrlString(
            "https://kemono.su/${data.service}/user/${data.userId}/post/${data.id}");
      }),
    ];
  }

  @override
  FavoriteItem toLocalFavoriteItem(KemonoPost data) {
    // Simplified version - the original has more fields
    return FavoriteItem(
      target: data.target,
      name: data.title,
      coverPath: data.cover,
      author: data.userName,
      type: FavoriteType('kemono'.hashCode),
      tags: [],
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../base.dart';
import '../../foundation/app_page_route.dart';
import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../foundation/def.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../network/nhentai_network/nhentai_main_network.dart';
import '../../network/res.dart';
import '../../foundation/ui_mode.dart';
import '../../tools/translations.dart';
import '../category_comics_page.dart';
import '../comic_page.dart' show EpsData, FavoriteComicWidget, ThumbnailsData;
import '../reader/comic_reading_page.dart';
import '../search_result_page.dart';
import '../comic_page/comic_page_adapter.dart';
import '../comic_page/comic_page_logic.dart';
import 'comments.dart';

// ============================================================================
// NhentaiAdapter
// ============================================================================

class NhentaiAdapter extends ComicPageAdapter<NhentaiComic> {
  @override String get source => "Nhentai";
  @override ComicType get comicType => ComicType.nhentai;

  String _resolveId(NhentaiComic data) => data.id;

  @override String tag(String id) => "Nhentai $id";
  @override String downloadId(String id) => "nhentai$id";

  @override
  String url(NhentaiComic data) => "https://nhentai.net/g/${data.id}/";

  // -------- B. 数据加载 --------
  @override
  Future<Res<NhentaiComic>> loadData(String id) =>
      NhentaiNetwork().getComicInfo(id);

  @override Future<NhentaiComic?> loadCachedData(String id) =>
      SynchronousFuture(null);

  @override
  Future<bool> loadFavorite(NhentaiComic data) async =>
      data.favorite ||
      (await LocalFavoritesManager()
              .findWithModel(toLocalFavoriteItem(data)))
          .isNotEmpty;

  // -------- C. 元数据提取 --------
  @override String? title(NhentaiComic data) => data.title;
  @override String? subTitle(NhentaiComic data) => data.subTitle;
  @override String? cover(NhentaiComic data) => data.cover;
  @override int? pages(NhentaiComic data) =>
      int.tryParse(data.tags["Pages"]?.elementAtOrNull(0) ?? "");
  @override String? introduction(NhentaiComic data) => null;
  @override bool? favoriteOnPlatformInitial(NhentaiComic data) => data.favorite;
  @override String? commentsCount(NhentaiComic data) => null;
  @override String? likeCount(NhentaiComic data) => null;
  @override bool get enableTranslationToCN => App.locale.languageCode == "zh";

  @override
  Map<String, List<String>>? tags(NhentaiComic data) {
    var tags = Map<String, List<String>>.from(data.tags);
    tags.remove("Pages");
    tags.removeWhere((key, value) => value.isEmpty);
    return tags;
  }

  @override EpsData? eps(NhentaiComic data, BuildContext context) => null;

  @override
  ThumbnailsData? createThumbnails(NhentaiComic data) =>
      ThumbnailsData(data.thumbnails, (page) async => const Res([]), 1);

  @override
  Widget buildThumbnailImage(int index, String imageUrl, BuildContext context,
      {List<String>? localImages}) {
    var url = imageUrl;
    if (localImages != null && index < localImages.length) {
      url = Uri.file(localImages[index]).toString();
    }
    return PicaImage(
        url: url,
        fit: BoxFit.contain,
        headers: {"sourceKey": comicType.name, "isThumbnail": "true"},
        memCacheWidth: 200);
  }

  // -------- D. 操作 --------
  @override
  void read(NhentaiComic data, History? history, BuildContext context) async {
    final h = await History.createIfNull(history, data);
    App.globalTo(() => ComicReadingPage.nhentai(data.id, data.title,
        initialPage: h!.page));
  }

  @override
  void download(NhentaiComic data, BuildContext context) async {
    final id = "nhentai${data.id}";
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
    downloadManager.addNhentaiDownload(data);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  void openFavoritePanel(
      NhentaiComic data, ComicPageBridge bridge, BuildContext context) {
    final widget = FavoriteComicWidget(
      havePlatformFavorite: NhentaiNetwork().logged,
      needLoadFolderData: false,
      favoriteOnPlatform: data.favorite,
      initialFolder: NhentaiNetwork().logged ? "0" : null,
      localFavoriteItem: toLocalFavoriteItem(data),
      setFavorite: (b) {
        if (bridge.favorite != b) {
          bridge.favorite = b;
          bridge.updateState();
        }
      },
      folders: const {"0": "Nhentai"},
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await NhentaiNetwork()
              .favoriteComic(data.id, data.token);
          if (res.success) data.favorite = true;
          return res;
        }
        LocalFavoritesManager().addComic(folder, toLocalFavoriteItem(data));
        return const Res(true);
      },
      cancelPlatformFavorite: () async {
        var res = await NhentaiNetwork()
            .unfavoriteComic(data.id, data.token);
        if (res.success) data.favorite = false;
        return res;
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
  ActionFunc? openComments(NhentaiComic data, BuildContext context) => () {
    showComments(App.globalContext!, data.id);
  };

  @override ActionFunc? onLike(NhentaiComic data, BuildContext context) => null;
  @override bool isLiked(NhentaiComic data) => false;

  @override
  ActionFunc? searchSimilar(NhentaiComic data, BuildContext context) => () {
    String? subTitle = data.subTitle;
    if (subTitle == "") subTitle = null;
    var title = subTitle ?? data.title;
    title = title
        .replaceAll(RegExp(r"\[.*?\]"), "")
        .replaceAll(RegExp(r"\(.*?\)"), "");
    Navigator.of(context).push(AppPageRoute(
      builder: (_) => SearchResultPage(
        keyword: "\"$title\"".trim(), comicType: comicType),
    ));
  };

  @override
  void onTagTapped(String tag, String key, NhentaiComic data,
      BuildContext context) {
    var t = tag;
    if (t.contains(" | ")) t = t.replaceAll(' | ', '-');
    if (t.contains(" ")) t = t.replaceAll(' ', '-');
    String? param = switch (key) {
      "Parodies" => "/parody/$t",
      "Character" => "/character/$t",
      "Tags" => "/tag/$t",
      "Artists" => "/artist/$t",
      "Groups" => "/group/$t",
      "Languages" => "/language/$t",
      "Categories" => "/category/$t",
      _ => null,
    };
    if (param == null) {
      Navigator.of(context).push(AppPageRoute(
        builder: (_) =>
            SearchResultPage(keyword: tag, comicType: comicType)));
    } else {
      Navigator.of(context).push(AppPageRoute(
        builder: (_) => CategoryComicsPage(
            category: tag, comicType: comicType, param: param)));
    }
  }

  @override
  void onThumbnailTapped(
      int index, NhentaiComic data, BuildContext context) async {
    await History.findOrCreate(data);
    App.globalTo(() => ComicReadingPage.nhentai(data.id, data.title,
        initialPage: index + 1));
  }

  // -------- E. 自定义UI & 转换 --------
  @override
  Widget? buildRecommendation(NhentaiComic data, BuildContext context) =>
      SliverGridComics(comics: data.recommendations, comicType: comicType);

  @override Card? buildUploaderInfo(NhentaiComic data, BuildContext context) => null;
  @override Widget? buildMoreInfo(NhentaiComic data, BuildContext context) => null;

  @override
  List<Widget>? buildExtraActionButtons(NhentaiComic data, BuildContext context,
      Widget Function(BuildContext, String, IconData, VoidCallback, [VoidCallback?])
          buildActionItem) => null;

  @override
  FavoriteItem toLocalFavoriteItem(NhentaiComic data) =>
      FavoriteItem.fromNhentai(NhentaiComicBrief(data.title, data.cover,
          data.id, "Unknown", data.tags["Tags"] ?? const <String>[]));
}

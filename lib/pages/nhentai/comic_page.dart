import 'package:flutter/material.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../base.dart';
import '../../foundation/app.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import 'comments.dart';

class NhentaiComicPage extends BaseComicPage<NhentaiComic> {
  const NhentaiComicPage(String id, {super.key, this.comicCover}) : _id = id;

  final String _id;

  final String? comicCover;

  @override
  String get url => "https://nhentai.net/g/$_id/";

  @override
  String get id => (data?.id) ?? _id;

  @override
  ActionFunc? get searchSimilar {
    final comicData = data;
    if (comicData == null) return null;
    return () {
      String? subTitle = comicData.subTitle;
      if (subTitle == "") {
        subTitle = null;
      }
      var title = subTitle ?? comicData.title;
      title = title
          .replaceAll(RegExp(r"\[.*?\]"), "")
          .replaceAll(RegExp(r"\(.*?\)"), "");
      context.to(
        () => SearchResultPage(
          keyword: "\"$title\"".trim(),
          comicType: comicType,
        ),
      );
    };
  }

  @override
  void openFavoritePanel(ComicPageLogic<NhentaiComic> logic) {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: NhentaiNetwork().logged,
      needLoadFolderData: false,
      favoriteOnPlatform: data?.favorite ?? false,
      initialFolder: NhentaiNetwork().logged ? "0" : null,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (logic.favorite.value != b) {
          logic.favorite.value = b;
          logic.update();
        }
      },
      folders: const {"0": "Nhentai"},
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await NhentaiNetwork().favoriteComic(id, data?.token ?? "");
          if (res.success) {
            data?.favorite = true;
          }
          return res;
        } else {
          final comicData = data;
          LocalFavoritesManager().addComic(
            folder,
            FavoriteItem.fromNhentai(
              NhentaiComicBrief(
                comicData?.title ?? "",
                comicData?.cover ?? "",
                id,
                "Unknown",
                comicData?.tags["Tags"] ?? const <String>[],
              ),
            ),
          );
          return const Res(true);
        }
      },
      cancelPlatformFavorite: () async {
        var res = await NhentaiNetwork().unfavoriteComic(id, data?.token ?? "");
        if (res.success) {
          data?.favorite = false;
        }
        return res;
      },
      favoriteOnPlatformValue: data?.favorite,
    ));
  }

  @override
  ActionFunc? get openComments => () {
        showComments(App.globalContext!, id);
      };

  @override
  String? get cover => comicCover ?? data?.cover;

  @override
  void download(ComicPageLogic<NhentaiComic> logic) async {
    final comicData = data;
    if (comicData == null) return;
    final id = "nhentai${comicData.id}";
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
    downloadManager.addNhentaiDownload(comicData);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  EpsData? get eps => null;

  @override
  String? get introduction => null;

  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  @override
  Future<Res<NhentaiComic>> loadData() => NhentaiNetwork().getComicInfo(_id);

  @override
  int? get pages => int.tryParse(data?.tags["Pages"]?.elementAtOrNull(0) ?? "");

  @override
  String? get subTitle => data?.subTitle;

  @override
  void read(History? history, ComicPageLogic<NhentaiComic> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(() => ComicReadingPage(
        ReadingData.fromNhentai(comicData.id, comicData.title),
        history: history,
      )
    );
  }

  @override
  void onThumbnailTapped(int index, ComicPageLogic<NhentaiComic> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromNhentai(comicData.id, comicData.title),
        history: logic.history.value,
        initialPage: index + 1,
      ),
    );
  }

  @override
  Future<bool> loadFavorite(NhentaiComic data) async {
    return data.favorite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem(data))).isNotEmpty;
  }

  @override
  Widget? recommendationBuilder(NhentaiComic data) =>
      SliverGridComics(comics: data.recommendations, comicType: comicType);

  @override
  String get tag => "Nhentai $_id";

  Map<String, List<String>> generateTags() {
    final comicData = data;
    if (comicData == null) return {};
    var tags = Map<String, List<String>>.from(comicData.tags);
    tags.remove("Pages");
    tags.removeWhere((key, value) => value.isEmpty);
    return tags;
  }

  @override
  Map<String, List<String>>? get tags => generateTags();

  @override
  void tapOnTag(String tag, String key) {
    if (tag.contains(" | ")) {
      tag = tag.replaceAll(' | ', '-');
    }
    if (tag.contains(" ")) {
      tag = tag.replaceAll(' ', '-');
    }
    String? categoryParam = switch (key) {
      "Parodies" => "/parody/$tag",
      "Character" => "/character/$tag",
      "Tags" => "/tag/$tag",
      "Artists" => "/artist/$tag",
      "Groups" => "/group/$tag",
      "Languages" => "/language/$tag",
      "Categories" => "/category/$tag",
      _ => null
    };

    if (categoryParam == null) {
      context.to(
        () => SearchResultPage(
          keyword: tag,
          comicType: comicType,
        ),
      );
    } else {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          comicType: comicType,
          param: categoryParam,
        ),
      );
    }
  }

  @override
  ThumbnailsData? get thumbnailsCreator {
    if (data == null) return null;
    return ThumbnailsData(data!.thumbnails, (page) async => const Res([]), 1);
  }

  @override
  String? get title => data?.title;

  @override
  Card? get uploaderInfo => null;

  @override
  String get source => "Nhentai";

  @override
  FavoriteItem toLocalFavoriteItem([NhentaiComic? comicData]) {
    final comic = comicData ?? data;
    if (comic == null) {
      return FavoriteItem.fromNhentai(NhentaiComicBrief(
          "", "", id, "Unknown", const <String>[]));
    }
    return FavoriteItem.fromNhentai(NhentaiComicBrief(comic.title, comic.cover,
        id, "Unknown", comic.tags["Tags"] ?? const <String>[]));
  }

  @override
  String get downloadedId => "nhentai$id";

  @override
  ComicType get comicType => ComicType.nhentai;
}

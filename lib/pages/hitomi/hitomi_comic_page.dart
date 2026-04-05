import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/hitomi_network/image.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_search.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../foundation/disk_cache.dart';
import '../../network/hitomi_network/hitomi_download_model.dart';

class HitomiComicPage extends BaseComicPage<HitomiComic> {
  HitomiComicPage(HitomiComicBrief comic, {super.key})
      : link = comic.link,
        comicCover = comic.cover;

  const HitomiComicPage.fromLink(this.link, {super.key, String? cover})
      : comicCover = cover;

  final String link;

  final String? comicCover;

  @override
  String? get url => link;

  @override
  void openFavoritePanel(ComicPageLogic<HitomiComic> logic) {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: false,
      needLoadFolderData: false,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (logic.favorite.value != b) {
          logic.favorite.value = b;
          logic.update();
        }
      },
      selectFolderCallback: (folder, page) {
        final comicData = data;
        if (comicData != null) {
          LocalFavoritesManager().addComic(
            folder,
            FavoriteItem.fromHitomi(comicData.toBrief(link, cover ?? "")),
          );
        }
        return Future.value(const Res(true));
      },
      favoriteOnPlatformValue: false,
    ));
  }

  @override
  String? get cover => data?.cover ?? comicCover;

  @override
  void download(ComicPageLogic<HitomiComic> logic) {
    final comicData = data;
    if (comicData != null) {
      _downloadComic(comicData, context, cover ?? "", link);
    }
  }

  @override
  EpsData? get eps => null;

  @override
  String? get introduction => null;

  @override
  Future<Res<HitomiComic>> loadData() async {
    final result = await HiNetwork().getComicInfo(link);
    if (result.success) {
      DiskCache.writeModel(cacheKey, result.data.toMap());
    }
    return result;
  }

  @override
  Future<HitomiComic?> loadCachedData() async {
    var data = await DiskCache.readModel(cacheKey, (map) => HitomiComic.fromMap(map));
    if (data != null) return data;
    final downloadedId = "hitomi$id";
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedHitomiComic) {
        return downloaded.comic;
      }
    }
    return null;
  }

  @override
  int? get pages => null;

  @override
  void read(History? history, ComicPageLogic<HitomiComic> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromHitomi(comicData),
        history: history,
      ),
    );
  }

  @override
  Widget? recommendationBuilder(HitomiComic data) => SliverGrid(
        delegate: SliverChildBuilderDelegate(childCount: data.related.length,
            (context, i) {
          return HitomiComicTileDynamicLoading(data.related[i]);
        }),
        gridDelegate: SliverGridDelegateWithComics(),
      );


  @override
  Map<String, List<String>>? get tags {
    final comicData = data;
    if (comicData == null) return null;
    return {
      "Artists": comicData.artists ?? ["N/A"],
      "Groups": comicData.group,
      "Categories": comicData.type.toList(),
      "Time": comicData.time.toList(),
      "Languages": comicData.lang.toList(),
      "Tags":
          List.generate(comicData.tags.length, (index) => comicData.tags[index].name),
      "Series": comicData.parodys != null
          ? List.generate(comicData.parodys!.length, (index) => comicData.parodys![index].name)
          : [],
      "Characters": comicData.characters != null
          ? List.generate(comicData.characters!.length, (index) => comicData.characters![index].name)
          : [],
    };
  }

  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  @override
  void tapOnTag(String tag, String key) {
    if (key == "Tags") {
      if (tag.endsWith(' ♀')) {
        tag = "female:${tag.replaceLast(" ♀", "")}";
      } else if (tag.endsWith('♂')) {
        tag = "male:${tag.replaceLast(" ♂", "")}";
      } else {
        tag = "tag:$tag";
      }
    }
    if (tag.contains(" ")) {
      tag = tag.replaceAll(' ', '_');
    }
    String? categoryParam = switch (key) {
      "Artists" => "artist:$tag",
      "Groups" => "group:$tag",
      "Categories" => "type:$tag",
      "Languages" => "language:$tag",
      "Series" => "series:$tag",
      "Characters" => "character:$tag",
      "Tags" => tag,
      "Time" => null,
      _ => null
    };
    if (categoryParam != null && tag != "N/A") {
      context.to(
            () => SearchResultPage(
          keyword: categoryParam,
          comicType: comicType,
        ),
      );
    }
  }



  @override
  ThumbnailsData? get thumbnailsCreator {
    final comicData = data;
    if (comicData == null) return null;
    return ThumbnailsData([], (page) async {
      try {
        var gg = GG();
        var images = <String>[];
        for (var file in comicData.files) {
          images.add(await gg.urlFromUrlFromHash(
              comicData.id, file, "webpsmallsmalltn", "webp"));
        }
        return Res(images);
      } catch (e, s) {
        Log.e("Network $e\n$s");
        return Res(null, errorMessage: e.toString());
      }
    }, 2);
  }

  @override
  void onThumbnailTapped(int index, ComicPageLogic<HitomiComic> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(() => ComicReadingPage(
          ReadingData.fromHitomi(comicData),
          history: logic.history.value,
          initialPage: index + 1,
        ));
  }

  @override
  String? get title => data?.title;

  @override
  Card? get uploaderInfo => null;

  @override
  Future<bool> loadFavorite(HitomiComic data) async {
    return (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem(data)))
        .isNotEmpty;
  }

  @override
  String get id => data?.id ?? link;

  @override
  String get source => "hitomi";

  @override
  FavoriteItem toLocalFavoriteItem([HitomiComic? comicData]) {
    final comic = comicData ?? data;
    if (comic == null) {
      return FavoriteItem.fromHitomi(
          HitomiComicBrief("", "", "", [], "", "", link, ""));
    }
    return FavoriteItem.fromHitomi(comic.toBrief(link, cover ?? ""));
  }

  @override
  String get downloadedId => "hitomi${data?.id ?? link}";

  @override
  ComicType get comicType => ComicType.hitomi;

  @override
  String get tag => "Hitomi $id";
}

Future<void> _downloadComic(
    HitomiComic comic, BuildContext context, String cover, String link) async {
  if (await downloadManager.isExists(comic.id)) {
    showToast(message: "已下载".tl);
    return;
  }
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }
  downloadManager.addHitomiDownload(comic, cover, link);
  showToast(message: "已加入下载队列".tl);
}

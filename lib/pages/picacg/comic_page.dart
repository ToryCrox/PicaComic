import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/components/select_download_eps.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/picacg/comments_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

import '../../foundation/disk_cache.dart';
import '../../network/picacg_network/picacg_download_model.dart';
import '../../tools/type_util.dart';
import '../comic_page.dart';

class PicacgComicPage extends BaseComicPage<ComicItem> {
  @override
  final String id;

  @override
  final String? cover;

  const PicacgComicPage(this.id, this.cover, {super.key});

  @override
  ActionFunc? get onLike {
    final comicData = data;
    if (comicData == null) return null;
    return () {
      network.likeOrUnlikeComic(id);
      comicData.isLiked = !comicData.isLiked;
      update();
    };
  }

  @override
  String? get likeCount => data?.likes.toString();

  @override
  bool get isLiked => data?.isLiked ?? false;

  @override
  void openFavoritePanel(ComicPageLogic<ComicItem> logic) {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: picacg.isLogin,
      needLoadFolderData: false,
      folders: const {"Picacg": "Picacg"},
      initialFolder: data?.isFavourite ?? false ? null : "Picacg",
      favoriteOnPlatform: data?.isFavourite ?? false,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (logic.favorite.value != b) {
          logic.favorite.value = b;
          logic.update();
        }
      },
      cancelPlatformFavorite: () async {
        var res = await network.favouriteOrUnfavouriteComic(id);
        if (res) {
          data?.isFavourite = false;
          return const Res(true);
        }
        return Res.error("网络错误".tl);
      },
      selectFolderCallback: (name, p) async {
        if (p == 0) {
          var res = await network.favouriteOrUnfavouriteComic(id);
          if (res) {
            data?.isFavourite = true;
            logic.update();
            return const Res(true);
          } else {
            return Res.error("网络错误".tl);
          }
        } else {
          LocalFavoritesManager().addComic(name, toLocalFavoriteItem());
          return const Res(true);
        }
      },
      favoriteOnPlatformValue: data?.isFavourite ?? false,
    ));
  }

  @override
  ActionFunc? get openComments => () => showComments(App.globalContext!, id);

  @override
  String? get commentsCount => data!.comments.toString();

  @override
  void download(ComicPageLogic<ComicItem> logic) {
    final comicData = data;
    if (comicData != null) {
      _downloadComic(comicData, App.globalContext!, comicData.eps);
    }
  }

  @override
  EpsData? get eps {
    final comicData = data;
    if (comicData == null) return null;
    return EpsData(
      comicData.eps,
      (i) async {
        await History.findOrCreate(comicData);
        App.globalTo(
            () => ComicReadingPage.picacg(id, i + 1, comicData.eps, comicData.title));
      },
    );
  }

  @override
  String? get introduction => data?.description;

  @override
  Future<Res<ComicItem>> loadData() => network.getComicInfo(id).then((res){
    if (res.success) {
      DiskCache.writeString(cacheKey, TypeUtil.parseString(res.data.toJson()));
    }
    return res;
  });

  @override
  Future<ComicItem?> loadCachedData() async {
    var data = await DiskCache.readModel(cacheKey, (map) => ComicItem.fromJson(map));
    if (data != null) return data;
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedComic) {
        return downloaded.comicItem;
      }
    }
    return null;
  }

  @override
  int? get pages => data?.pagesCount;

  @override
  void read(History? history, ComicPageLogic<ComicItem> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromPicacg(comicData, comicData.eps),
        history: history,
      ),
    );
  }

  @override
  Widget recommendationBuilder(data) =>
      SliverGridComics(comics: data.recommendation, comicType: comicType);

  @override
  String get tag => "Picacg Comic Page $id";

  @override
  Map<String, List<String>>? get tags {
    final comicData = data;
    if (comicData == null) return null;
    return {
      "作者".tl: comicData.author.toList(),
      "汉化".tl: comicData.chineseTeam.toList(),
      "分类".tl: comicData.categories,
      "标签".tl: comicData.tags
    };
  }

  @override
  void tapOnTag(String tag, String key) {
    final comicData = data;
    if (comicData == null) return;
    if (comicData.categories.contains(tag)) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          comicType: ComicType.picacg,
        ),
      );
    } else if (comicData.author == tag) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          param: "a",
          comicType: ComicType.picacg,
        ),
      );
    } else {
      context.to(
        () => SearchResultPage(
          keyword: tag,
          comicType: comicType,
        ),
      );
    }
  }

  @override
  ThumbnailsData? get thumbnailsCreator => null;

  @override
  String? get title => data?.title;

  @override
  Future<bool> loadFavorite(ComicItem data) async {
    return data.isFavourite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem(data))).isNotEmpty;
  }

  @override
  Card? get uploaderInfo => Card(
        elevation: 0,
        color: context.colorScheme.inversePrimary,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                flex: 0,
                child: Avatar(
                  size: 50,
                  avatarUrl: data!.creator.avatarUrl,
                  frame: data!.creator.frameUrl,
                  couldBeShown: true,
                  name: data!.creator.name,
                  slogan: data!.creator.slogan,
                  level: data!.creator.level,
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
                        data!.creator.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                          "${data!.time.substring(0, 10)} ${data!.time.substring(11, 19)}更新")
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  String get source => "Picacg";

  @override
  FavoriteItem toLocalFavoriteItem([ComicItem? comicData]) {
    final comic = comicData ?? data;
    if (comic == null) {
      return FavoriteItem(
        target: id,
        name: "",
        coverPath: "",
        author: "",
        type: FavoriteType.picacg,
        tags: [],
      );
    }
    return FavoriteItem(
      target: id,
      name: comic.title,
      coverPath: comic.thumbUrl,
      author: comic.author,
      type: FavoriteType.picacg,
      tags: comic.tags,
    );
  }

  @override
  String get downloadedId => id;

  @override
  ComicType get comicType => ComicType.picacg;

  @override
  bool get supportThumbnails => false;
}

void _downloadComic(
    ComicItem comic, BuildContext context, List<String> eps) async {
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }
  var downloaded = <int>[];
  if (await downloadManager.isExists(comic.id)) {
    var downloadedComic = (await downloadManager.getComicOrNull(comic.id))!
      as DownloadedComic;
    downloaded.addAll(downloadedComic.downloadedEps);
  }
  var content = SelectDownloadChapter(
    eps,
    (selectedEps) {
      downloadManager.addPicDownload(comic, selectedEps);
      App.globalBack();
      showToast(message: "已加入下载队列".tl);
    },
    downloaded,
    onEpisodeDelete: (ep) async {
      var downloadedComic = await downloadManager.getComicOrNull(comic.id);
      if (downloadedComic != null) {
        if (downloadedComic.downloadedEps.length == 1) {
          await downloadManager.delete([comic.id]);
        } else {
          await downloadManager.deleteEpisode(downloadedComic, ep);
        }
      }
    },
  );
  if (UiMode.m1(App.globalContext!)) {
    showModalBottomSheet(
      context: App.globalContext!,
      builder: (context) => content,
    );
  } else {
    showSideBar(
      App.globalContext!,
      content,
      useSurfaceTintColor: true,
    );
  }
}

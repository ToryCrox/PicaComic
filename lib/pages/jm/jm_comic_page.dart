import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/built_in/jm.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/select_download_eps.dart';

import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/type_util.dart';

import '../../foundation/app.dart';
import '../../foundation/disk_cache.dart';
import '../../foundation/history.dart';
import '../../foundation/local_favorites.dart';
import '../../foundation/ui_mode.dart';
import '../../network/jm_network/jm_models.dart';
import '../../network/jm_network/jm_network.dart';
import 'jm_comments_page.dart';
import '../../network/jm_network/jm_download.dart';

class JmComicPage extends BaseComicPage<JmComicInfo> {
  const JmComicPage(this.id, {super.key});

  @override
  final String id;

  @override
  ActionFunc? get searchSimilar => () {
        context.to(
          () => SearchResultPage(
            keyword: data!.name,
            comicType: comicType,
          ),
        );
      };

  @override
  ActionFunc? get onLike {
    final comicData = data;
    if (comicData == null) return null;
    return () {
      if (!comicData.liked) {
        jmNetwork.likeComic(comicData.id);
      }
      comicData.liked = true;
      update();
    };
  }

  @override
  bool get isLiked => data?.liked ?? false;

  @override
  String? get likeCount => data?.likes.toString().replaceLast("000", "K");

  @override
  void openFavoritePanel(ComicPageLogic<JmComicInfo> logic) {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: jm.isLogin,
      needLoadFolderData: true,
      setFavorite: (b) {
        if (logic.favorite.value != b) {
          logic.favorite.value = b;
          logic.update();
        }
      },
      foldersLoader: () async {
        var res = await jmNetwork.getFolders();
        if (res.error) {
          return res;
        } else {
          var resData = <String, String>{"0": "全部收藏".tl};
          resData.addAll(res.data);
          return Res(resData);
        }
      },
      localFavoriteItem: toLocalFavoriteItem(),
      favoriteOnPlatform: data?.favorite ?? false,
      selectFolderCallback: (folder, page) async {
        if (page == 0) {
          var res = await jmNetwork.favorite(id, folder);
          if (res.success) {
            data?.favorite = true;
          }
          return res;
        } else {
          LocalFavoritesManager().addComic(
            folder,
            toLocalFavoriteItem(),
          );
          return const Res(true);
        }
      },
      cancelPlatformFavorite: () async {
        var res = await jmNetwork.favorite(id, null);
        if (res.success) {
          data?.favorite = false;
        }
        return res;
      },
      favoriteOnPlatformValue: data?.favorite ?? false,
    ));
  }

  @override
  ActionFunc? get openComments {
    if (data == null) return null;
    return () {
      showComments(App.globalContext!, id, data!.comments);
    };
  }

  @override
  String get cover => getJmCoverUrl(id);

  @override
  void download(ComicPageLogic<JmComicInfo> logic) {
    if (data != null) {
      downloadComic(data!, App.globalContext!);
    }
  }

  String _getEpName(int index) {
    final epName = data!.epNames.elementAtOrNull(index);
    if (epName != null) {
      return epName;
    }
    var name = "第 @c 章".tlParams({"c": (index + 1).toString()});
    return name;
  }

  @override
  EpsData? get eps {
    final comicData = data;
    if (comicData == null) return null;
    return EpsData(
      List<String>.generate(
          comicData.series.values.length, (index) => _getEpName(index)),
      (i) async {
        await History.findOrCreate(comicData);
        App.globalTo(() => ComicReadingPage.jmComic(comicData, i + 1));
      },
    );
  }

  @override
  String? get introduction => data?.description;

  @override
  Future<Res<JmComicInfo>> loadData() =>
      JmNetwork().getComicInfo(id).then((res) {
        if (res.success) {
          DiskCache.writeString(
              cacheKey, TypeUtil.parseString(res.data.toJson()));
        }
        return res;
      });

  @override
  Future<JmComicInfo?> loadCachedData() async {
    var data = await DiskCache.readModel(
        cacheKey, (map) => JmComicInfo.fromMap(map));
    if (data != null) return data;
    final downloadedId = "jm$id";
    if (await downloadManager.isExists(downloadedId)) {
      var downloaded = await downloadManager.getComicOrNull(downloadedId);
      if (downloaded is DownloadedJmComic) {
        return downloaded.comic;
      }
    }
    return null;
  }

  @override
  int? get pages => null;

  @override
  Future<bool> loadFavorite(JmComicInfo data) async {
    return data.favorite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem(data)))
            .isNotEmpty;
  }

  @override
  void read(History? history, ComicPageLogic<JmComicInfo> logic) {
    final comicData = data;
    if (comicData == null) return;
    App.globalTo(
      () => ComicReadingPage(
        ReadingData.fromJm(comicData),
        history: history,
      ),
    );
  }

  @override
  void onThumbnailTapped(int index, ComicPageLogic<JmComicInfo> logic) {
    App.globalTo(() => ComicReadingPage(
          ReadingData.fromJm(data!),
          initialPage: index + 1,
          history: HistoryManager().findInCache(id),
        ));
  }

  @override
  Widget recommendationBuilder(JmComicInfo data) =>
      SliverGridComics(comics: data.relatedComics, comicType: comicType);


  @override
  Map<String, List<String>>? get tags {
    final comicData = data;
    if (comicData == null) return null;
    return {
      "ID": "JM${comicData.id}".toList(),
      "作者".tl: (comicData.author.isEmpty) ? "未知".tl.toList() : comicData.author,
      if (comicData.works.isNotEmpty) "作品".tl: comicData.works,
      if (comicData.actors.isNotEmpty) "登场人物".tl: comicData.actors,
      if (comicData.tags.isNotEmpty) "标签".tl: comicData.tags
    };
  }

  @override
  void tapOnTag(String tag, String key) => context.to(() => SearchResultPage(
        keyword: tag,
        comicType: comicType,
      ));

  @override
  ThumbnailsData? get thumbnailsCreator => null;

  @override
  String? get title => data?.name;

  @override
  Card? get uploaderInfo => null;

  @override
  String get source => "禁漫天堂".tl;

  @override
  FavoriteItem toLocalFavoriteItem([JmComicInfo? comicData]) {
    final comic = comicData ?? data!;
    return FavoriteItem.fromJmComic(JmComicBrief(
        id,
        comic.author.elementAtOrNull(0) ?? "",
        comic.name,
        comic.description,
        []));
  }

  @override
  String get downloadedId => "jm$id";

  @override
  ComicType get comicType => ComicType.jm;

  @override
  String get tag => "${comicType.name} comic page $id";

  @override
  bool get supportThumbnails => false;
}

void downloadComic(JmComicInfo comic, BuildContext context) async {
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
    eps = List<String>.generate(comic.series.length,
        (index) => "第 @c 章".tlParams({"c": (index + 1).toString()}));
  }

  var downloaded = <int>[];
  final downloadedComic =
      await downloadManager.getComicOrNull("jm${comic.id}");
  if (downloadedComic != null) {
    downloaded.addAll(downloadedComic.downloadedEps);
  }

  if (UiMode.m1(App.globalContext!)) {
    showModalBottomSheet(
        context: App.globalContext!,
        builder: (context) {
          return SelectDownloadChapter(eps, (selectedEps) {
            downloadManager.addJmDownload(comic, selectedEps);
            App.globalBack();
            showToast(message: "已加入下载队列".tl);
          }, downloaded, onEpisodeDelete: (ep) async {
            var downloadedComic =
                await downloadManager.getComicOrNull("jm${comic.id}");
            if (downloadedComic != null) {
              if (downloadedComic.downloadedEps.length == 1) {
                await downloadManager.delete(["jm${comic.id}"]);
              } else {
                await downloadManager.deleteEpisode(downloadedComic, ep);
              }
            }
          });
        });
  } else {
    showSideBar(
        App.globalContext!,
        SelectDownloadChapter(eps, (selectedEps) {
          downloadManager.addJmDownload(comic, selectedEps);
          App.globalBack();
          showToast(message: "已加入下载队列".tl);
        }, downloaded, onEpisodeDelete: (ep) async {
          var downloadedComic =
              await downloadManager.getComicOrNull("jm${comic.id}");
          if (downloadedComic != null) {
            if (downloadedComic.downloadedEps.length == 1) {
              await downloadManager.delete(["jm${comic.id}"]);
            } else {
              await downloadManager.deleteEpisode(downloadedComic, ep);
            }
          }
        }),
        useSurfaceTintColor: true);
  }
}

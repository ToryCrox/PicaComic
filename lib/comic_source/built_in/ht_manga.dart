import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/disk_cache.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/htmanga/ht_comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import '../comic_source.dart';

final htManga = ComicSource.named(
  name: '绅士漫画',
  key: ComicType.htmanga,
  filePath: 'built-in',
  favoriteData: FavoriteData(
    key: "htmanga",
    title: "绅士漫画",
    multiFolder: true,
    loadComic: (ref, i, [folder]) =>
        ref.read(htMangaNetworkProvider).getFavoriteFolderComics(folder!, i),
    loadFolders: (ref, [String? comicId]) =>
        ref.read(htMangaNetworkProvider).getFolders(),
    allFavoritesId: "0",
    deleteFolder: (ref, id) async {
      var res = await ref.read(htMangaNetworkProvider).deleteFolder(id);
      return res
          ? const Res(true)
          : const Res(false, errorMessage: "Network Error");
    },
    addFolder: (ref, name) async {
      var res = await ref.read(htMangaNetworkProvider).createFolder(name);
      return res
          ? const Res(true)
          : const Res(false, errorMessage: "Network Error");
    },
    addOrDelFavorite: (ref, id, folder, isAdding) async {
      if (isAdding) return const Res.error("invalid");
      var res = await ref.read(htMangaNetworkProvider).delFavorite(id);
      return res;
    },
  ),
  categoryData: const CategoryData(
    title: "绅士漫画",
    key: "htmanga",
    categories: [
      FixedCategoryPart("最新", ["最新漫画"], "category", ["/albums.html"]),
      FixedCategoryPart(
        "同人志",
        [
          "同人志",
          "同人志-汉化",
          "同人志-日语",
          "同人志-English",
          "同人志-CG画集",
          "同人志-3D漫画",
          "同人志-Cosplay",
        ],
        "category",
        [
          "/albums-index-cate-5.html",
          "/albums-index-cate-1.html",
          "/albums-index-cate-12.html",
          "/albums-index-cate-16.html",
          "/albums-index-cate-2.html",
          "/albums-index-cate-22.html",
          "/albums-index-cate-3.html",
        ],
      ),
      FixedCategoryPart(
        "单行本",
        ["单行本", "单行本-汉化", "单行本-日语", "单行本-English"],
        "category",
        [
          "/albums-index-cate-6.html",
          "/albums-index-cate-9.html",
          "/albums-index-cate-13.html",
          "/albums-index-cate-17.html",
        ],
      ),
      FixedCategoryPart(
        "杂志&短篇",
        ["杂志&短篇", "杂志&短篇-汉化", "杂志&短篇-日语", "杂志&短篇-English"],
        "category",
        [
          "/albums-index-cate-7.html",
          "/albums-index-cate-10.html",
          "/albums-index-cate-14.html",
          "/albums-index-cate-18.html",
        ],
      ),
      FixedCategoryPart(
        "韩漫",
        ["韩漫", "韩漫-汉化", "韩漫-其它"],
        "category",
        [
          "/albums-index-cate-19.html",
          "/albums-index-cate-20.html",
          "/albums-index-cate-21.html",
        ],
      ),
    ],
    enableRankingPage: true,
  ),
  categoryComicsData: CategoryComicsData.named(
    load: (ref, category, param, options, page) async {
      final network = ref.read(htMangaNetworkProvider);
      if (!param!.startsWith("http")) {
        param = network.baseUrl + param;
      }
      return network.getComicList(param, page);
    },
    rankingData: RankingData.named(
      options: {
        "/albums-favorite_ranking-type-day.html": "今日",
        "/albums-favorite_ranking-type-week.html": "本週",
        "/albums-favorite_ranking-type-month.html": "本月",
      },
      load: (ref, option, page) {
        final network = ref.read(htMangaNetworkProvider);
        return network.getComicList("${network.baseUrl}$option", page);
      },
    ),
  ),
  account: AccountConfig.named(
    registerWebsite: "https://www.wnacg.com/albums.html",
    login: (ref, account, pwd) async {
      var htManga = ComicSource.find(ComicType.htmanga.name)!;
      var res = await ref.read(htMangaNetworkProvider).login(account, pwd);
      if (!res.error) {
        htManga.data['name'] = account;
      }
      var a = <String>[account, pwd];
      htManga.data['account'] = a;
      return res;
    },
    logout: (ref) {
      ComicSource.find(ComicType.htmanga.name)!.data['name'] = null;
      ref.read(htMangaNetworkProvider).logout();
    },
  ),
  comicTileBuilderOverride: (context, comic, options) {
    return _HtComicTile(
      comic: comic as HtComicBrief,
      addonMenuOptions: options,
    );
  },
  explorePages: [
    ExplorePageData.named(
      title: "绅士漫画",
      type: ExplorePageType.singlePageWithMultiPart,
      loadMultiPart: (ref) async {
        var homepage = await ref.read(htMangaNetworkProvider).getHomePage();
        if (homepage.error) {
          return Res.fromErrorRes(homepage);
        }
        if (homepage.dataOrNull != null) {
          DiskCache.writeModel('ht_manga_home', homepage.data.toJson());
        }
        var res = <ExplorePagePart>[];
        for (int i = 0; i < homepage.data.comics.length; i++) {
          var name = homepage.data.links.keys.elementAt(i);
          res.add(
            ExplorePagePart(
              name,
              homepage.data.comics[i],
              "category:$name@${homepage.data.links[name]}",
            ),
          );
        }
        return Res(res);
      },
      loadMultiPartCache: () async {
        var homepage = await DiskCache.readModel(
          'ht_manga_home',
          HtHomePageData.fromJson,
        );
        final list = homepage?.comics ?? [];
        final links = homepage?.links ?? {};
        return [
          for (int i = 0; i < list.length; i++)
            ExplorePagePart(
              links.keys.elementAt(i),
              list[i],
              "category:${links.keys.elementAt(i)}@${links.values.elementAt(i)}",
            ),
        ];
      },
    ),
  ],
  searchPageData: SearchPageData.named(
    loadPage: (ref, keyword, page, options) {
      return ref.read(htMangaNetworkProvider).search(keyword, page);
    },
  ),
  comicPageBuilder: (context, id, cover) {
    return HtComicPage(id, comicCover: cover);
  },
);

class _HtComicTile extends ComicTile {
  const _HtComicTile({required this.comic, this.addonMenuOptions});

  final HtComicBrief comic;

  @override
  String get description => comic.time.trim();

  @override
  Widget get image => PicaImage(
    url: comic.image,
    sourceKey: ComicType.htmanga.name,
    isThumbnail: true,
    fit: BoxFit.cover,
    height: double.infinity,
    width: double.infinity,
  );

  @override
  void onTap_() {
    App.mainNavigatorKey!.currentContext!.to(
      () => ComicPage(
        comicType: ComicType.htmanga,
        id: comic.id,
        cover: comic.cover,
      ),
    );
  }

  @override
  String get subTitle => "${comic.pages} Pages";

  @override
  ActionFunc? readAction(WidgetRef ref) => () async {
    bool cancel = false;
    var dialog = showLoadingDialog(
      App.globalContext!,
      onCancel: () => cancel = true,
    );
    var res = await ref.read(htMangaNetworkProvider).getComicInfo(comic.id);
    if (cancel) {
      return;
    }
    dialog.close();
    if (res.error) {
      showToast(message: res.errorMessage ?? "Error");
    } else {
      var history = await History.findOrCreate(res.data);
      App.globalTo(
        () => ComicReadingPage.htmanga(
          res.data.id,
          comic.name,
          initialPage: history.page,
        ),
      );
    }
  };

  @override
  String get title => comic.name.trim();

  @override
  FavoriteItem? get favoriteItem => FavoriteItem.fromHtcomic(comic);

  @override
  String get comicID => comic.id;

  @override
  ComicType? get comicType => ComicType.htmanga;

  @override
  final List<ComicTileMenuOption>? addonMenuOptions;
}

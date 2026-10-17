import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/disk_cache.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/picacg/collections_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';

import '../comic_source.dart';

final picacg = ComicSource.named(
  name: "picacg",
  key: ComicType.picacg,
  filePath: 'built-in',
  favoriteData: FavoriteData(
    key: "picacg",
    title: "Picacg",
    multiFolder: false,
    loadComic: (ref, i, [folder]) => ref
        .read(picacgNetworkProvider)
        .getFavorites(
          i,
          ref
              .read(appSettingsProvider)
              .enabled(AppSettingKeys.picacgFavoritesNewestFirst),
        ),
    loadFolders: null,
    addOrDelFavorite: (ref, id, folder, isAdding) async {
      var res = await ref
          .read(picacgNetworkProvider)
          .favouriteOrUnfavouriteComic(id);
      return res
          ? const Res(true)
          : const Res(false, errorMessage: "Network Error");
    },
  ),
  categoryData: CategoryData(
    title: "Picacg",
    key: "picacg",
    categories: [const FixedCategoryPart("分类", _categories, "category")],
    enableRankingPage: true,
    buttons: [
      CategoryButtonData(
        label: "推荐",
        onTap: () => App.mainNavigatorKey?.currentContext?.to(
          () => const CollectionsPage(),
        ),
      ),
    ],
  ),
  account: AccountConfig.named(
    login: (ref, account, pwd) =>
        ref.read(picacgNetworkProvider).loginWithAccount(account, pwd),
    logout: (ref) {
      var picacg = ComicSource.find(ComicType.picacg.name)!;
      picacg.data['user'] = null;
      picacg.data['token'] = null;
      picacg.saveData();
    },
    infoItems: [
      AccountInfoItem(
        title: "账号",
        data: () =>
            (ComicSource.find(ComicType.picacg)?.data['user'] as Map?)?['email']
                ?.toString() ??
            '',
      ),
      AccountInfoItem(
        title: "用户名",
        data: () =>
            (ComicSource.find(ComicType.picacg)?.data['user'] as Map?)?['name']
                ?.toString() ??
            '',
      ),
      AccountInfoItem(
        title: "等级",
        data: () {
          final user = ComicSource.find(ComicType.picacg)?.data['user'] as Map?;
          return "Lv${user?['level']} ${user?['title']} Exp${user?['exp']}";
        },
      ),
      AccountInfoItem(
        title: "简介",
        data: () =>
            (ComicSource.find(ComicType.picacg)?.data['user']
                    as Map?)?['slogan']
                ?.toString() ??
            '',
      ),
    ],
  ),
  initData: (s, ref) {
    if (s.data['appChannel'] == null) {
      s.data['appChannel'] = '3';
    }
    if (s.data['imageQuality'] == null) {
      s.data['imageQuality'] = "original";
    }
  },
  comicTileBuilderOverride: (context, comic, options) {
    comic as ComicItemBrief;
    return _PicComicTile(comic, addonMenuOptions: options);
  },
  explorePages: [
    ExplorePageData.named(
      title: "picacg",
      type: ExplorePageType.singlePageWithMultiPart,
      loadMultiPart: (ref) async {
        final network = ref.read(picacgNetworkProvider);
        var [res0, res1] = await Future.wait([
          network.getRandomComics(),
          network.getLatest(1),
        ]);
        if (res0.error) {
          return Res.fromErrorRes(res0);
        }
        if (res1.error) {
          return Res.fromErrorRes(res1);
        }
        DiskCache.writeModelList(
          'pica_radom_comic',
          res0.data.map((e) => e.toJson()).toList(),
        );
        DiskCache.writeModelList(
          'pica_radom_latest',
          res1.data.map((e) => e.toJson()).toList(),
        );
        return Res([
          ExplorePagePart("随机".tl, res0.data, "category:random"),
          ExplorePagePart("最新".tl, res1.data, "category:latest"),
        ]);
      },
      loadMultiPartCache: () async {
        var [res0, res1] = await Future.wait([
          DiskCache.readModelList('pica_radom_comic', ComicItemBrief.fromJson),
          DiskCache.readModelList('pica_radom_latest', ComicItemBrief.fromJson),
        ]);
        if (res0.isNotEmpty || res1.isNotEmpty) {
          return [
            ExplorePagePart("随机".tl, res0, "category:random"),
            ExplorePagePart("最新".tl, res1, "category:latest"),
          ];
        } else {
          return [];
        }
      },
    ),
  ],
  categoryComicsData: CategoryComicsData.named(
    load: (ref, category, param, options, page) async {
      final network = ref.read(picacgNetworkProvider);
      if (category == "random") {
        return network.getRandomComics();
      } else if (category == "latest") {
        return network.getLatest(page);
      }
      return network.getCategoryComics(
        category,
        page,
        options[0],
        param ?? 'c',
      );
    },
    options: [
      CategoryComicsOptions.named(
        options: LinkedHashMap.of({
          "dd": "新到旧",
          "da": "旧到新",
          "ld": "最多喜欢",
          "vd": "最多指名",
        }),
        notShowWhen: ["random", "latest"],
      ),
    ],
    rankingData: RankingData.named(
      options: {"H24": "24小时", "D7": "7天", "D30": "30天"},
      load: (ref, options, page) {
        return ref.read(picacgNetworkProvider).getLeaderboard(options);
      },
    ),
  ),
  searchPageData: SearchPageData.named(
    loadPage: (ref, keyword, page, options) {
      return ref
          .read(picacgNetworkProvider)
          .search(keyword, options[0], page, addToHistory: true);
    },
    searchOptions: [
      SearchOptions.named(
        label: "排序",
        options: LinkedHashMap.of({
          "dd": "新到旧",
          "da": "旧到新",
          "ld": "最多喜欢",
          "vd": "最多指名",
        }),
      ),
    ],
  ),
  comicPageBuilder: (context, id, cover) => PicacgComicPage(id, cover),
);

class _PicComicTile extends ComicTile {
  final ComicItemBrief comic;

  const _PicComicTile(this.comic, {Key? key, this.addonMenuOptions})
    : super(key: key);

  @override
  String get description => '${comic.likes} likes';

  @override
  List<String>? get tags => comic.tags;

  @override
  Widget get image => PicaImage(
    url: comic.path,
    sourceKey: ComicType.picacg.name,
    isThumbnail: true,
    fit: BoxFit.cover,
    height: double.infinity,
    width: double.infinity,
  );

  @override
  ActionFunc? readAction(WidgetRef ref) => () async {
    bool cancel = false;
    var dialog = showLoadingDialog(
      App.globalContext!,
      onCancel: () => cancel = true,
    );
    var res = await ref.read(picacgNetworkProvider).getEps(comic.id);
    if (cancel) {
      return;
    }
    dialog.close();
    if (res.error) {
      showToast(message: res.errorMessage ?? "Error");
    } else {
      var history = await HistoryManager().find(comic.id);
      if (history == null) {
        history = History(
          HistoryType.picacg,
          DateTime.now(),
          comic.title,
          comic.author,
          comic.cover,
          0,
          0,
          comic.id,
        );
        await HistoryManager().addHistory(history);
      }
      App.globalTo(
        () => ComicReadingPage.picacg(
          comic.id,
          history!.ep,
          res.data,
          comic.title,
          initialPage: history.page,
        ),
      );
    }
  };

  @override
  void onTap_() {
    App.mainNavigatorKey!.currentContext!.to(
      () => ComicPage(
        comicType: ComicType.picacg,
        id: comic.id,
        cover: comic.cover,
      ),
    );
  }

  @override
  String get subTitle => comic.author;

  @override
  String get title => comic.title;

  @override
  int? get pages => comic.pages;

  @override
  FavoriteItem? get favoriteItem => FavoriteItem.fromPicacg(comic);

  @override
  String get comicID => comic.id;

  @override
  ComicType? get comicType => ComicType.picacg;

  @override
  final List<ComicTileMenuOption>? addonMenuOptions;
}

const _categories = [
  "大家都在看",
  "大濕推薦",
  "那年今天",
  "官方都在看",
  "嗶咔漢化",
  "全彩",
  "長篇",
  "同人",
  "短篇",
  "圓神領域",
  "碧藍幻想",
  "CG雜圖",
  "英語 ENG",
  "生肉",
  "純愛",
  "百合花園",
  "耽美花園",
  "偽娘哲學",
  "後宮閃光",
  "扶他樂園",
  "單行本",
  "姐姐系",
  "妹妹系",
  "SM",
  "性轉換",
  "足の恋",
  "人妻",
  "NTR",
  "強暴",
  "非人類",
  "艦隊收藏",
  "Love Live",
  "SAO 刀劍神域",
  "Fate",
  "東方",
  "WEBTOON",
  "禁書目錄",
  "歐美",
  "Cosplay",
  "重口地帶",
];

library comic_source;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:pica_comic/network/image_config.dart';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import '../foundation/history.dart';
import '../foundation/log.dart';
import '../tools/extensions.dart';
import '../tools/map_extension.dart';
import '../tools/type_util.dart';
import '../base.dart';
import '../network/base_comic.dart';
import '../network/res.dart';
import 'built_in/ehentai.dart';
import 'built_in/hitomi.dart';
import 'built_in/ht_manga.dart';
import 'built_in/jm.dart';
import 'built_in/kemono.dart';
import 'built_in/nhentai.dart';
import 'built_in/picacg.dart';

part 'category.dart';

part 'favorites.dart';

/// build comic list, [Res.subData] should be maxPage or null if there is no limit.
typedef ComicListBuilder = Future<Res<List<BaseComic>>> Function(int page);

typedef ComicListCacheBuilder = Future<List<BaseComic>> Function();

typedef LoginFunction = Future<Res<bool>> Function(String, String);

typedef LoadComicFunc = Future<Res<ComicInfoData>> Function(String id);

typedef LoadComicPagesFunc =
    Future<Res<List<String>>> Function(String id, String? ep);

typedef CommentsLoader =
    Future<Res<List<Comment>>> Function(
      String id,
      String? subId,
      int page,
      String? replyTo,
    );

typedef SendCommentFunc =
    Future<Res<bool>> Function(
      String id,
      String? subId,
      String content,
      String? replyTo,
    );

typedef GetImageLoadingConfigFunc =
    ImageConfig? Function(String imageKey, String comicId, String epId);
typedef GetThumbnailLoadingConfigFunc = ImageConfig? Function(String imageKey);

class ComicSource {
  static final builtIn = [
    picacg,
    ehentai,
    jm,
    hitomi,
    htManga,
    nhentai,
    kemono,
  ];

  static List<ComicSource> sources = [];

  static ComicSource? find(dynamic key) {
    if (key is ComicType) {
      return sources.firstWhereOrNull((element) => element.key == key);
    }
    return sources.firstWhereOrNull(
      (element) => element.key.name == key.toString(),
    );
  }

  static ComicSource? fromIntKey(int key) => sources.firstWhereOrNull(
    (element) => element.key.index == key || element.key.name.hashCode == key,
  );

  static Future<void> init() async {
    for (var source in builtInSources) {
      if (appdata.appSettings.isComicSourceEnabled(source.name)) {
        var s = builtIn.firstWhere((e) => e.key == source);
        sources.add(s);
        await s.loadData();
        s.initData?.call(s);
      }
    }
  }

  static Future reload() async {
    sources.clear();
    await init();
  }

  /// Name of this source.
  final String name;

  /// Identifier of this source.
  final ComicType key;

  int get intKey {
    return key.index;
  }

  /// Account config.
  final AccountConfig? account;

  /// Category data used to build a static category tags page.
  final CategoryData? categoryData;

  /// Category comics data used to build a comics page with a category tag.
  final CategoryComicsData? categoryComicsData;

  /// Favorite data used to build favorite page.
  final FavoriteData? favoriteData;

  /// Explore pages.
  final List<ExplorePageData> explorePages;

  /// Search page.
  final SearchPageData? searchPageData;

  /// Settings.
  final List<SettingItem> settings;

  /// Load comic info.
  final LoadComicFunc? loadComicInfo;

  /// Load comic pages.
  final LoadComicPagesFunc? loadComicPages;

  final ImageConfig? Function(String url, String comicId, String epId)?
  getImageLoadingConfig;

  final ImageConfig? Function(String url)? getThumbnailLoadingConfig;

  final String? matchBriefIdReg;

  var data = <String, dynamic>{};

  bool get isLogin => data["account"] != null;

  final String filePath;

  final String url;

  final String version;

  final CommentsLoader? commentsLoader;

  final SendCommentFunc? sendCommentFunc;

  final RegExp? idMatcher;

  final Widget Function(BuildContext context, String id, String? cover)?
  comicPageBuilder;

  Future<void> loadData() async {
    var file = File("${App.dataPath}/comic_source/$key.data");
    if (await file.exists()) {
      data = TypeUtil.parseMap(jsonDecode(await file.readAsString()));
    }
  }

  bool _isSaving = false;
  bool _haveWaitingTask = false;

  Future<void> saveData() async {
    if (_haveWaitingTask) return;
    while (_isSaving) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 20));
      _haveWaitingTask = false;
    }
    _isSaving = true;
    var file = File("${App.dataPath}/comic_source/$key.data");
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(data));
    _isSaving = false;
  }

  Future<bool> reLogin() async {
    if (data["account"] == null) {
      return false;
    }
    final List accountData = data["account"];
    var res = await account!.login!(accountData[0], accountData[1]);
    if (res.error) {
      Log.e("Failed to re-login ${res.errorMessage ?? "Error"}");
    }
    return !res.error;
  }

  // only for built-in comic sources
  final FutureOr<void> Function(ComicSource source)? initData;

  bool get isBuiltIn => filePath == 'built-in';

  final Widget Function(BuildContext, BaseComic, List<ComicTileMenuOption>?)?
  comicTileBuilderOverride;

  ComicSource(
    this.name,
    this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages,
    this.searchPageData,
    this.settings,
    this.loadComicInfo,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.matchBriefIdReg,
    this.filePath,
    this.url,
    this.version,
    this.commentsLoader,
    this.sendCommentFunc,
  ) : initData = null,
      comicTileBuilderOverride = null,
      idMatcher = null,
      comicPageBuilder = null;

  ComicSource.named({
    required this.name,
    required this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages = const [],
    this.searchPageData,
    this.settings = const [],
    this.loadComicInfo,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.matchBriefIdReg,
    required this.filePath,
    this.url = '',
    this.version = '',
    this.commentsLoader,
    this.sendCommentFunc,
    this.initData,
    this.comicTileBuilderOverride,
    this.idMatcher,
    this.comicPageBuilder,
  });

  ComicSource.unknown(String key)
    : key = ComicType.fromString(key),
      name = "Unknown",
      account = null,
      categoryData = null,
      categoryComicsData = null,
      favoriteData = null,
      explorePages = [],
      searchPageData = null,
      settings = [],
      loadComicInfo = null,
      loadComicPages = null,
      getImageLoadingConfig = null,
      getThumbnailLoadingConfig = null,
      matchBriefIdReg = null,
      filePath = "",
      url = "",
      version = "",
      commentsLoader = null,
      sendCommentFunc = null,
      initData = null,
      comicTileBuilderOverride = null,
      idMatcher = null,
      comicPageBuilder = null;
}

class AccountConfig {
  final LoginFunction? login;

  final FutureOr<void> Function(BuildContext)? onLogin;

  final String? loginWebsite;

  final String? registerWebsite;

  final void Function() logout;

  final bool allowReLogin;

  final List<AccountInfoItem> infoItems;

  const AccountConfig(
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    this.logout, {
    this.onLogin,
  }) : allowReLogin = true,
       infoItems = const [];

  const AccountConfig.named({
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    required this.logout,
    this.onLogin,
    this.allowReLogin = true,
    this.infoItems = const [],
  });
}

class AccountInfoItem {
  final String title;
  final String Function()? data;
  final void Function()? onTap;
  final WidgetBuilder? builder;

  AccountInfoItem({required this.title, this.data, this.onTap, this.builder});
}

class LoadImageRequest {
  String url;

  Map<String, String> headers;

  LoadImageRequest(this.url, this.headers);
}

class ExplorePageData {
  final String title;

  final ExplorePageType type;

  final ComicListBuilder? loadPage;

  final ComicListCacheBuilder? loadCache;

  final Future<Res<List<ExplorePagePart>>> Function()? loadMultiPart;

  final Future<List<ExplorePagePart>> Function()? loadMultiPartCache;

  /// return a `List` contains `List<BaseComic>` or `ExplorePagePart`
  final Future<Res<List<Object>>> Function(int index)? loadMixed;

  final WidgetBuilder? overridePageBuilder;

  ExplorePageData(this.title, this.type, this.loadPage, this.loadMultiPart)
    : loadMixed = null,
      loadCache = null,
      loadMultiPartCache = null,
      overridePageBuilder = null;

  ExplorePageData.named({
    required this.title,
    required this.type,
    this.loadPage,
    this.loadCache,
    this.loadMultiPart,
    this.loadMultiPartCache,
    this.loadMixed,
    this.overridePageBuilder,
  });
}

class ExplorePagePart {
  final String title;

  final List<BaseComic> comics;

  /// If this is not null, the [ExplorePagePart] will show a button to jump to new page.
  ///
  /// Value of this field should match the following format:
  ///   - search:keyword
  ///   - category:categoryName
  ///
  /// End with `@`+`param` if the category has a parameter.
  final String? viewMore;

  const ExplorePagePart(this.title, this.comics, this.viewMore);
}

enum ExplorePageType {
  multiPageComicList,
  singlePageWithMultiPart,
  mixed,
  override,
}

typedef SearchFunction =
    Future<Res<List<BaseComic>>> Function(
      String keyword,
      int page,
      List<String> searchOption,
    );

class SearchPageData {
  /// If this is not null, the default value of search options will be first element.
  final List<SearchOptions>? searchOptions;

  final Widget Function(
    BuildContext,
    List<String> initialValues,
    void Function(List<String>),
  )?
  customOptionsBuilder;

  final Widget Function(String keyword, List<String> options)?
  overrideSearchResultBuilder;

  final SearchFunction? loadPage;

  final bool enableLanguageFilter;

  final bool enableTagsSuggestions;

  const SearchPageData(this.searchOptions, this.loadPage)
    : enableLanguageFilter = false,
      customOptionsBuilder = null,
      overrideSearchResultBuilder = null,
      enableTagsSuggestions = false;

  const SearchPageData.named({
    this.searchOptions,
    this.loadPage,
    this.enableLanguageFilter = false,
    this.customOptionsBuilder,
    this.overrideSearchResultBuilder,
    this.enableTagsSuggestions = false,
  });
}

class SearchOptions {
  final LinkedHashMap<String, String> options;

  final String label;

  const SearchOptions(this.options, this.label);

  String get defaultValue => options.keys.first;

  const SearchOptions.named({required this.options, required this.label});
}

class SettingItem {
  final String name;
  final String iconName;
  final SettingType type;
  final List<String>? options;

  const SettingItem(this.name, this.iconName, this.type, this.options);
}

enum SettingType { switcher, selector, input }

/// 可序列化的漫画详情推荐项。
class ComicInfoSuggestion extends BaseComic {
  @override
  final String title;
  @override
  final String subTitle;
  @override
  final String cover;
  @override
  final String id;
  @override
  final List<String> tags;
  @override
  final String description;

  const ComicInfoSuggestion({
    this.title = '',
    this.subTitle = '',
    this.cover = '',
    this.id = '',
    this.tags = const [],
    this.description = '',
  });

  ComicInfoSuggestion copyWith({
    String? title,
    String? subTitle,
    String? cover,
    String? id,
    List<String>? tags,
    String? description,
  }) => ComicInfoSuggestion(
    title: title ?? this.title,
    subTitle: subTitle ?? this.subTitle,
    cover: cover ?? this.cover,
    id: id ?? this.id,
    tags: tags ?? this.tags,
    description: description ?? this.description,
  );

  factory ComicInfoSuggestion.fromMap(Map<String, dynamic> map) =>
      ComicInfoSuggestion(
        title: map.optString('title'),
        subTitle: map.optString('subTitle'),
        cover: map.optString('cover'),
        id: map.optString('id'),
        tags: map.optStringList('tags'),
        description: map.optString('description'),
      );

  Map<String, dynamic> toMap() => {
    'title': title,
    'subTitle': subTitle,
    'cover': cover,
    'id': id,
    'tags': tags,
    'description': description,
  };

  factory ComicInfoSuggestion.fromJson(Map<String, dynamic> json) =>
      ComicInfoSuggestion.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicInfoSuggestion &&
          title == other.title &&
          subTitle == other.subTitle &&
          cover == other.cover &&
          id == other.id &&
          TypeUtil.equal(tags, other.tags) &&
          description == other.description;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'ComicInfoSuggestion${jsonEncode(toMap())}';
}

class ComicInfoData with HistoryMixin {
  @override
  final String title;

  @override
  final String? subTitle;

  @override
  final String cover;

  final String? description;

  final Map<String, List<String>> tags;

  /// id-name
  final Map<String, String>? chapters;

  final List<String>? thumbnails;

  final Future<Res<List<String>>> Function(String id, int page)?
  thumbnailLoader;

  final int thumbnailMaxPage;

  final List<BaseComic>? suggestions;

  final String sourceKey;

  final String comicId;

  final bool? isFavorite;

  final String? subId;

  const ComicInfoData({
    this.title = '',
    this.subTitle,
    this.cover = '',
    this.description,
    this.tags = const {},
    this.chapters,
    this.thumbnails,
    this.thumbnailLoader,
    this.thumbnailMaxPage = 0,
    this.suggestions,
    this.sourceKey = '',
    this.comicId = '',
    this.isFavorite,
    this.subId,
  });

  ComicInfoData copyWith({
    String? title,
    String? subTitle,
    String? cover,
    String? description,
    Map<String, List<String>>? tags,
    Map<String, String>? chapters,
    List<String>? thumbnails,
    Future<Res<List<String>>> Function(String id, int page)? thumbnailLoader,
    int? thumbnailMaxPage,
    List<BaseComic>? suggestions,
    String? sourceKey,
    String? comicId,
    bool? isFavorite,
    String? subId,
    bool clearSubTitle = false,
    bool clearDescription = false,
    bool clearChapters = false,
    bool clearThumbnails = false,
    bool clearThumbnailLoader = false,
    bool clearSuggestions = false,
    bool clearIsFavorite = false,
    bool clearSubId = false,
  }) {
    return ComicInfoData(
      title: title ?? this.title,
      subTitle: clearSubTitle ? null : subTitle ?? this.subTitle,
      cover: cover ?? this.cover,
      description: clearDescription ? null : description ?? this.description,
      tags: tags ?? this.tags,
      chapters: clearChapters ? null : chapters ?? this.chapters,
      thumbnails: clearThumbnails ? null : thumbnails ?? this.thumbnails,
      thumbnailLoader: clearThumbnailLoader
          ? null
          : thumbnailLoader ?? this.thumbnailLoader,
      thumbnailMaxPage: thumbnailMaxPage ?? this.thumbnailMaxPage,
      suggestions: clearSuggestions ? null : suggestions ?? this.suggestions,
      sourceKey: sourceKey ?? this.sourceKey,
      comicId: comicId ?? this.comicId,
      isFavorite: clearIsFavorite ? null : isFavorite ?? this.isFavorite,
      subId: clearSubId ? null : subId ?? this.subId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "title": title,
      "subTitle": subTitle,
      "cover": cover,
      "description": description,
      "tags": tags,
      "chapters": chapters,
      "thumbnails": thumbnails,
      "thumbnailMaxPage": thumbnailMaxPage,
      "suggestions": suggestions
          ?.map(
            (comic) => {
              "title": comic.title,
              "subTitle": comic.subTitle,
              "cover": comic.cover,
              "id": comic.id,
              "tags": comic.tags,
              "description": comic.description,
            },
          )
          .toList(),
      "sourceKey": sourceKey,
      "comicId": comicId,
      "isFavorite": isFavorite,
      "subId": subId,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  static Map<String, List<String>> _generateMap(Map<String, dynamic> map) {
    final res = <String, List<String>>{};
    map.forEach((key, value) {
      res[key] = TypeUtil.parseStringList(value);
    });
    return res;
  }

  factory ComicInfoData.fromMap(Map<String, dynamic> map) {
    final chaptersMap = map.optMapOrNull('chapters');
    final suggestionsValue = map['suggestions'];
    return ComicInfoData(
      title: map.optString('title'),
      subTitle: map.optStringOrNull('subTitle'),
      cover: map.optString('cover'),
      description: map.optStringOrNull('description'),
      tags: _generateMap(map.optMap('tags')),
      chapters: chaptersMap == null
          ? null
          : chaptersMap.map(
              (key, value) => MapEntry(key, TypeUtil.parseString(value)),
            ),
      sourceKey: map.optString('sourceKey'),
      comicId: map.optString('comicId'),
      thumbnails: map['thumbnails'] == null
          ? null
          : map.optStringList('thumbnails'),
      thumbnailMaxPage: map.optInt('thumbnailMaxPage'),
      suggestions: suggestionsValue == null
          ? null
          : map.optList(
              'suggestions',
              (item) => ComicInfoSuggestion.fromMap(item),
            ),
      isFavorite: map.optBoolOrNull('isFavorite'),
      subId: map.optStringOrNull('subId'),
    );
  }

  factory ComicInfoData.fromJson(Map<String, dynamic> json) =>
      ComicInfoData.fromMap(json);

  @override
  HistoryType get historyType => HistoryType(sourceKey.hashCode);

  @override
  String get target => comicId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicInfoData &&
          title == other.title &&
          subTitle == other.subTitle &&
          cover == other.cover &&
          description == other.description &&
          TypeUtil.equal(tags, other.tags) &&
          TypeUtil.equal(chapters, other.chapters) &&
          TypeUtil.equal(thumbnails, other.thumbnails) &&
          thumbnailMaxPage == other.thumbnailMaxPage &&
          TypeUtil.equal(suggestions, other.suggestions) &&
          sourceKey == other.sourceKey &&
          comicId == other.comicId &&
          isFavorite == other.isFavorite &&
          subId == other.subId;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'ComicInfoData${jsonEncode(toMap())}';
}

typedef CategoryComicsLoader =
    Future<Res<List<BaseComic>>> Function(
      String category,
      String? param,
      List<String> options,
      int page,
    );

class CategoryComicsData {
  /// options
  final List<CategoryComicsOptions> options;

  /// [category] is the one clicked by the user on the category page.

  /// if [BaseCategoryPart.categoryParams] is not null, [param] will be not null.
  ///
  /// [Res.subData] should be maxPage or null if there is no limit.
  final CategoryComicsLoader load;

  final RankingData? rankingData;

  const CategoryComicsData(this.options, this.load, {this.rankingData});

  const CategoryComicsData.named({
    this.options = const [],
    required this.load,
    this.rankingData,
  });
}

class RankingData {
  final Map<String, String> options;

  final Future<Res<List<BaseComic>>> Function(String option, int page) load;

  const RankingData(this.options, this.load);

  const RankingData.named({required this.options, required this.load});
}

class CategoryComicsOptions {
  /// Use a [LinkedHashMap] to describe an option list.
  /// key is for loading comics, value is the name displayed on screen.
  /// Default value will be the first of the Map.
  final LinkedHashMap<String, String> options;

  /// If [notShowWhen] contains category's name, the option will not be shown.
  final List<String> notShowWhen;

  final List<String>? showWhen;

  const CategoryComicsOptions(this.options, this.notShowWhen, this.showWhen);

  const CategoryComicsOptions.named({
    required this.options,
    this.notShowWhen = const [],
    this.showWhen,
  });
}

class Comment {
  final String userName;
  final String? avatar;
  final String content;
  final String? time;
  final int? replyCount;
  final String? id;

  const Comment(
    this.userName,
    this.avatar,
    this.content,
    this.time,
    this.replyCount,
    this.id,
  );
}

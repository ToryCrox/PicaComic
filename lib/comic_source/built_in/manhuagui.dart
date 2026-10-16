import 'dart:collection';

import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/image_config.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_explore_page.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_category_page.dart';

/// 漫画柜内置源，只注册一个探索入口，所有功能无需账号。
final manhuagui = ComicSource.named(
  name: '漫画柜',
  key: ComicType.manhuagui,
  filePath: 'built-in',
  url: ManhuaguiNetwork.baseUrl,
  matchBriefIdReg: r'^(\d+)$',
  idMatcher: RegExp(r'^\d+$'),
  comicTileBuilderOverride: (_, comic, options) =>
      _ManhuaguiComicTile(comic, options),
  explorePages: [
    ExplorePageData.named(
      title: '漫画柜',
      type: ExplorePageType.override,
      overridePageBuilder: (_) => const ManhuaguiExplorePage(),
    ),
  ],
  categoryData: CategoryData(
    title: '漫画柜',
    key: 'manhuagui',
    categories: const [],
    enableRankingPage: false,
    overridePageBuilder: (_) => const ManhuaguiCategoryPage(),
  ),
  searchPageData: SearchPageData.named(
    searchOptions: [
      SearchOptions(
        LinkedHashMap.of({'': '最近更新', '1': '人气最旺', '2': '最新发布', '3': '评分最高'}),
        '排序',
      ),
    ],
    loadPage: (ref, keyword, page, options) => ref
        .read(manhuaguiNetworkProvider)
        .search(keyword, page, sort: options.firstOrNull ?? ''),
  ),
  loadComicInfoCache: (id) => appComicSourceServices.manhuagui.infoCache(id),
  loadComicInfo: (ref, id) => ref.read(manhuaguiNetworkProvider).info(id),
  loadComicPages: (ref, id, chapter) => chapter == null
      ? Future.value(const Res.error('缺少章节 ID'))
      : ref.read(manhuaguiNetworkProvider).pages(id, chapter),
  getImageLoadingConfig: (_, url, _, _) =>
      ImageConfig(url: url, headers: ManhuaguiNetwork.imageHeaders),
  getThumbnailLoadingConfig: (_, url) =>
      ImageConfig(url: url, headers: ManhuaguiNetwork.imageHeaders),
  commentsLoader: (ref, id, _, page, _) async {
    final result = await ref
        .read(manhuaguiNetworkProvider)
        .comments(id, page, ManhuaguiCommentSort.latest);
    if (result.error) return Res.fromErrorRes(result);
    return Res(
      result.data.map((thread) => thread.comment).toList(),
      subData: result.subData,
    );
  },
  initData: (source, ref) async {
    var changed = false;
    for (final registration in [
      (
        flag: 'exploreRegistered',
        key: AppSettingKeys.explorePages,
        title: '漫画柜',
      ),
      (
        flag: 'categoryRegistered',
        key: AppSettingKeys.categoryPages,
        title: 'manhuagui',
      ),
    ]) {
      if (source.data[registration.flag] == true) continue;
      final pages = ref
          .read(appSettingProvider(registration.key))
          .split(',')
          .where((title) => title.isNotEmpty)
          .toList();
      if (!pages.contains(registration.title)) {
        await ref
            .read(appSettingsProvider.notifier)
            .setValue(
              registration.key,
              [...pages, registration.title].join(','),
            );
      }
      source.data[registration.flag] = true;
      changed = true;
    }
    if (!changed) return;
    await source.saveData();
  },
);

/// 将站点列表和缓存推荐统一交给现有漫画卡片。
class _ManhuaguiComicTile extends CustomComicTile {
  _ManhuaguiComicTile(BaseComic comic, List<ComicTileMenuOption>? options)
    : super(
        CustomComic(
          comic.title,
          comic.subTitle,
          comic.cover,
          comic.id,
          comic.tags,
          comic.description,
          'manhuagui',
        ),
        addonMenuOptions: options,
      );

  @override
  ComicType get comicType => ComicType.manhuagui;
}

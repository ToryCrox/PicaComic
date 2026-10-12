import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart';
import 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/kemono_network/kemono_main_network.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/image_config.dart';

// 兼容旧导入路径；Provider 定义与各自的网络客户端放在同一文件。
export 'package:pica_comic/network/eh_network/eh_main_network.dart'
    show ehNetworkProvider;
export 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart'
    show hiperdexNetworkProvider;
export 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart'
    show hitomiNetworkProvider;
export 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart'
    show htMangaNetworkProvider;
export 'package:pica_comic/network/jm_network/jm_network.dart'
    show jmNetworkProvider;
export 'package:pica_comic/network/kemono_network/kemono_main_network.dart'
    show kemonoNetworkProvider;
export 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart'
    show nhentaiNetworkProvider;
export 'package:pica_comic/network/picacg_network/methods.dart'
    show picacgNetworkProvider;

/// 漫画源回调使用的有类型依赖集合。
class ComicSourceServices implements ComicSourceServiceResolver {
  ComicSourceServices({
    required PicacgNetwork Function() picacg,
    required EhNetwork Function() ehentai,
    required JmNetwork Function() jm,
    required HiNetwork Function() hitomi,
    required HtmangaNetwork Function() htmanga,
    required NhentaiNetwork Function() nhentai,
    required KemonoNetwork Function() kemono,
    required HiperdexNetwork Function() hiperdex,
  }) : _resolvers = {
         'picacg': picacg,
         'ehentai': ehentai,
         'jm': jm,
         'hitomi': hitomi,
         'htmanga': htmanga,
         'nhentai': nhentai,
         'kemono': kemono,
         'hiperdex': hiperdex,
       };

  final Map<String, Object Function()> _resolvers;

  PicacgNetwork get picacg => get<PicacgNetwork>('picacg');
  EhNetwork get ehentai => get<EhNetwork>('ehentai');
  JmNetwork get jm => get<JmNetwork>('jm');
  HiNetwork get hitomi => get<HiNetwork>('hitomi');
  HtmangaNetwork get htmanga => get<HtmangaNetwork>('htmanga');
  NhentaiNetwork get nhentai => get<NhentaiNetwork>('nhentai');
  KemonoNetwork get kemono => get<KemonoNetwork>('kemono');
  HiperdexNetwork get hiperdex => get<HiperdexNetwork>('hiperdex');

  @override
  T get<T extends Object>(String sourceKey) {
    final resolver = _resolvers[sourceKey];
    if (resolver == null) {
      throw ArgumentError.value(sourceKey, 'sourceKey', '未知漫画源');
    }
    final service = resolver();
    if (service is T) return service;
    throw StateError('漫画源 $sourceKey 的网络服务类型不匹配');
  }
}

final comicSourceServicesProvider = Provider<ComicSourceServices>((ref) {
  return ComicSourceServices(
    picacg: () => ref.read(picacgNetworkProvider),
    ehentai: () => ref.read(ehNetworkProvider),
    jm: () => ref.read(jmNetworkProvider),
    hitomi: () => ref.read(hitomiNetworkProvider),
    htmanga: () => ref.read(htMangaNetworkProvider),
    nhentai: () => ref.read(nhentaiNetworkProvider),
    kemono: () => ref.read(kemonoNetworkProvider),
    hiperdex: () => ref.read(hiperdexNetworkProvider),
  );
});

/// 从当前 ProviderScope 取得应用级漫画源服务集合。
ComicSourceServices comicSourceServicesOf(BuildContext context) {
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(comicSourceServicesProvider);
}

/// 从应用根上下文取得漫画源服务，供没有 Ref 的应用级回调使用。
ComicSourceServices get appComicSourceServices =>
    comicSourceServicesOf(App.globalContext!);

/// 通过当前 Provider Ref 执行漫画源定义的回调。
///
/// 回调本身直接读取具体网络 Provider；该控制器只为没有 `Ref` 的旧 UI
/// 入口提供执行上下文，不传递网络服务集合。
class ComicSourceCallbackRunner {
  const ComicSourceCallbackRunner(this._ref);

  final Ref _ref;

  /// 通过漫画源定义加载章节图片链接。
  Future<Res<List<String>>> loadComicPages(ComicPagesQuery query) async {
    try {
      return await _ref.read(comicPagesQueryProvider(query).future);
    } catch (error) {
      return Res.error(error.toString());
    }
  }

  Future<Res<List<BaseComic>>> loadFavorites(
    FavoriteData data,
    int page, [
    String? folder,
  ]) => data.loadComic(_ref, page, folder);

  Future<Res<Map<String, String>>> loadFavoriteFolders(
    FavoriteData data, [
    String? comicId,
  ]) {
    final loader = data.loadFolders;
    if (loader == null) return Future.value(const Res({}));
    return loader(_ref, comicId);
  }

  Future<Res<bool>> changeFavorite(
    FavoriteData data,
    String comicId,
    String folderId,
    bool isAdding,
  ) {
    final callback = data.addOrDelFavorite;
    if (callback == null) return Future.value(const Res.error('不支持收藏操作'));
    return callback(_ref, comicId, folderId, isAdding);
  }

  Future<Res<bool>> deleteFavoriteFolder(FavoriteData data, String folderId) {
    final callback = data.deleteFolder;
    if (callback == null) return Future.value(const Res.error('不支持删除收藏夹'));
    return callback(_ref, folderId);
  }

  Future<Res<bool>> addFavoriteFolder(FavoriteData data, String name) {
    final callback = data.addFolder;
    if (callback == null) return Future.value(const Res.error('不支持创建收藏夹'));
    return callback(_ref, name);
  }

  Future<Res<bool>> login(ComicSource source, String account, String password) {
    final callback = source.account?.login;
    if (callback == null) return Future.value(const Res.error('不支持登录'));
    return callback(_ref, account, password);
  }

  Future<void> onLogin(ComicSource source, BuildContext context) async {
    await source.account?.onLogin?.call(_ref, context);
  }

  Future<void> logout(ComicSource source) async {
    await source.account?.logout(_ref);
  }

  ImageConfig? imageConfig(
    ComicSource source,
    String url,
    String comicId,
    String episodeId,
  ) => source.getImageLoadingConfig?.call(_ref, url, comicId, episodeId);

  ImageConfig? thumbnailConfig(ComicSource source, String url) =>
      source.getThumbnailLoadingConfig?.call(_ref, url);
}

final comicSourceCallbackRunnerProvider = Provider<ComicSourceCallbackRunner>(
  (ref) => ComicSourceCallbackRunner(ref),
);

/// 通过当前 ProviderScope 重新加载漫画源并同步注册表状态。
Future<void> reloadComicSources(BuildContext context) {
  return ProviderScope.containerOf(
    context,
    listen: false,
  ).read(comicSourceRegistryProvider.notifier).reload();
}

/// 网络请求错误在 Provider 边界转换为 AsyncError。
class ComicSourceRequestException implements Exception {
  const ComicSourceRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ComicInfoQuery {
  const ComicInfoQuery(this.sourceKey, this.id);

  final String sourceKey;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ComicInfoQuery && other.sourceKey == sourceKey && other.id == id;

  @override
  int get hashCode => Object.hash(sourceKey, id);
}

class ComicPagesQuery {
  const ComicPagesQuery(this.sourceKey, this.id, this.episodeId);

  final String sourceKey;
  final String id;
  final String? episodeId;

  @override
  bool operator ==(Object other) =>
      other is ComicPagesQuery &&
      other.sourceKey == sourceKey &&
      other.id == id &&
      other.episodeId == episodeId;

  @override
  int get hashCode => Object.hash(sourceKey, id, episodeId);
}

/// 内置漫画源的统一注册表，负责加载数据并延迟初始化运行时服务。
class ComicSourceRegistry extends AsyncNotifier<List<ComicSource>> {
  bool _runtimeInitialized = false;

  @override
  Future<List<ComicSource>> build() async {
    await ComicSource.init(initializeRuntime: false, ref: ref);
    return List.unmodifiable(ComicSource.sources);
  }

  Future<void> initializeRuntime() async {
    if (_runtimeInitialized) return;
    await ComicSource.initRuntime(ref: ref);
    _runtimeInitialized = true;
    state = AsyncData(List.unmodifiable(ComicSource.sources));
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ComicSource.init(initializeRuntime: false, ref: ref);
      if (_runtimeInitialized) {
        await ComicSource.initRuntime(ref: ref);
      }
      return List.unmodifiable(ComicSource.sources);
    });
  }
}

final comicSourceRegistryProvider =
    AsyncNotifierProvider<ComicSourceRegistry, List<ComicSource>>(
      ComicSourceRegistry.new,
    );

/// 漫画详情查询 Provider：保留成功的 Res<T>，将 Res.error 映射为 AsyncError。
final comicInfoQueryProvider = FutureProvider.autoDispose
    .family<Res<ComicInfoData>, ComicInfoQuery>((ref, query) async {
      await ref.watch(comicSourceRegistryProvider.future);
      final source = ComicSource.find(query.sourceKey);
      final loader = source?.loadComicInfo;
      if (loader == null) {
        throw ComicSourceRequestException('漫画源 ${query.sourceKey} 不支持详情请求');
      }
      final result = await loader(ref, query.id);
      if (result.error) {
        throw ComicSourceRequestException(result.errorMessageWithoutNull);
      }
      return result;
    });

/// 漫画图片链接查询 Provider：供阅读器和自定义源下载流程复用。
final comicPagesQueryProvider = FutureProvider.autoDispose
    .family<Res<List<String>>, ComicPagesQuery>((ref, query) async {
      await ref.watch(comicSourceRegistryProvider.future);
      final source = ComicSource.find(query.sourceKey);
      final loader = source?.loadComicPages;
      if (loader == null) {
        throw ComicSourceRequestException('漫画源 ${query.sourceKey} 不支持图片请求');
      }
      final result = await loader(ref, query.id, query.episodeId);
      if (result.error) {
        throw ComicSourceRequestException(result.errorMessageWithoutNull);
      }
      return result;
    });

/// 从任意非 Provider 回调读取漫画详情查询，并保留旧 Res 返回约定。
Future<Res<ComicInfoData>> loadComicInfoFromProvider(
  ProviderContainer container,
  ComicInfoQuery query,
) async {
  try {
    return await container.read(comicInfoQueryProvider(query).future);
  } catch (error) {
    return Res.error(error.toString());
  }
}

/// 从任意非 Provider 回调读取章节图片查询，并保留旧 Res 返回约定。
Future<Res<List<String>>> loadComicPagesFromProvider(
  ProviderContainer container,
  ComicPagesQuery query,
) async {
  try {
    return await container.read(comicPagesQueryProvider(query).future);
  } catch (error) {
    return Res.error(error.toString());
  }
}

typedef ExplorePageQuery = ({String sourceKey, String title});

typedef ExploreMixedPageQuery = ({String sourceKey, String title, int page});

/// 通过 Provider Ref 加载漫画源的多分区探索页。
final exploreMultiPartQueryProvider = FutureProvider.autoDispose
    .family<Res<List<ExplorePagePart>>, ExplorePageQuery>((ref, query) async {
      await ref.watch(comicSourceRegistryProvider.future);
      final data = _findExplorePage(query.sourceKey, query.title);
      final loader = data?.loadMultiPart;
      if (loader == null) {
        return Res.error('漫画源 ${query.sourceKey} 不支持多分区探索页');
      }
      return loader(ref);
    });

/// 通过 Provider Ref 加载漫画源的混合探索页。
final exploreMixedPageQueryProvider = FutureProvider.autoDispose
    .family<Res<List<Object>>, ExploreMixedPageQuery>((ref, query) async {
      await ref.watch(comicSourceRegistryProvider.future);
      final data = _findExplorePage(query.sourceKey, query.title);
      final loader = data?.loadMixed;
      if (loader == null) {
        return Res.error('漫画源 ${query.sourceKey} 不支持混合探索页');
      }
      return loader(ref, query.page);
    });

ExplorePageData? _findExplorePage(String sourceKey, String title) {
  final source = ComicSource.find(sourceKey);
  if (source == null) return null;
  for (final page in source.explorePages) {
    if (page.title == title) return page;
  }
  return null;
}

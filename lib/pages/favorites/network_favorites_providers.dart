import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/res.dart';

part 'network_favorites_providers.g.dart';

/// 来源收藏的变更与账户会话快照。
class NetworkFavoriteState {
  const NetworkFavoriteState({
    this.revision = 0,
    this.session = 0,
    this.statuses = const {},
  });
  final int revision;
  final int session;
  final Map<String, bool> statuses;
}

/// 成功操作后统一刷新该来源的收藏数据。
@Riverpod(keepAlive: true)
class NetworkFavoriteRevision extends _$NetworkFavoriteRevision {
  @override
  NetworkFavoriteState build(String sourceKey) => const NetworkFavoriteState();

  /// 发布已经成功的远端收藏变化。
  void changed({String? comicId, bool? favorite}) {
    final statuses = {...state.statuses};
    if (comicId != null) {
      if (favorite == null) {
        statuses.remove(comicId);
      } else {
        statuses[comicId] = favorite;
      }
    }
    state = NetworkFavoriteState(
      revision: state.revision + 1,
      session: state.session,
      statuses: Map.unmodifiable(statuses),
    );
  }

  /// 登录、退出或来源重载后清除旧账号的收藏状态。
  void sessionChanged() => state = NetworkFavoriteState(
    revision: state.revision + 1,
    session: state.session + 1,
  );
}

/// 远端收藏操作状态与重复提交防护。
@Riverpod(keepAlive: true)
class NetworkFavoriteActions extends _$NetworkFavoriteActions {
  final _pending = <String, Future<Res<bool>>>{};
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// 保留漫画源既有回调及特殊参数，成功后发布统一变更。
  Future<Res<bool>> run(
    String sourceKey,
    Future<Res<bool>> Function() action, {
    String? comicId,
    bool? favorite,
    String? operationKey,
    bool? Function()? favoriteResult,
  }) {
    final generation = ref
        .read(networkFavoriteRevisionProvider(sourceKey))
        .session;
    final key =
        '$sourceKey:$generation:${operationKey ?? comicId ?? "mutation"}';
    final running = _pending[key];
    if (running != null) return running;
    final completer = Completer<Res<bool>>();
    _pending[key] = completer.future;
    state = const AsyncLoading();
    unawaited(() async {
      try {
        final response = await action();
        final result = !response.error && !response.data
            ? const Res<bool>.error('收藏操作失败')
            : response;
        if (ref.mounted &&
            generation ==
                ref.read(networkFavoriteRevisionProvider(sourceKey)).session) {
          if (result.error || !result.data) {
            state = AsyncError(
              StateError(result.errorMessage ?? '收藏操作失败'),
              StackTrace.current,
            );
          } else {
            ref
                .read(networkFavoriteRevisionProvider(sourceKey).notifier)
                .changed(
                  comicId: comicId,
                  favorite: favoriteResult?.call() ?? favorite,
                );
            state = const AsyncData(null);
          }
        }
        final currentSession =
            ref.mounted &&
            generation ==
                ref.read(networkFavoriteRevisionProvider(sourceKey)).session;
        if (ref.mounted && !currentSession && _pending.length == 1) {
          state = const AsyncData(null);
        }
        completer.complete(
          currentSession ? result : const Res.error('账户已变化，请重新操作'),
        );
      } catch (error, stack) {
        if (ref.mounted) {
          final current =
              generation ==
              ref.read(networkFavoriteRevisionProvider(sourceKey)).session;
          if (current) {
            state = AsyncError(error, stack);
          } else if (_pending.length == 1) {
            state = const AsyncData(null);
          }
        }
        completer.complete(Res.error(error.toString()));
      } finally {
        _pending.remove(key);
      }
    }());
    return completer.future;
  }

  /// 创建收藏夹。
  Future<Res<bool>> createFolder(String sourceKey, String name) {
    final runner = ref.read(comicSourceCallbackRunnerProvider);
    final data = getFavoriteData(sourceKey);
    return run(
      sourceKey,
      () => runner.addFavoriteFolder(data, name),
      operationKey: 'create:$name',
    );
  }

  /// 删除收藏夹。
  Future<Res<bool>> deleteFolder(String sourceKey, String folderId) {
    final runner = ref.read(comicSourceCallbackRunnerProvider);
    final data = getFavoriteData(sourceKey);
    return run(
      sourceKey,
      () => runner.deleteFavoriteFolder(data, folderId),
      operationKey: 'delete:$folderId',
    );
  }

  /// 增加或取消远端收藏。
  Future<Res<bool>> change(
    String sourceKey,
    String comicId,
    String folderId,
    bool adding,
  ) {
    final runner = ref.read(comicSourceCallbackRunnerProvider);
    final data = getFavoriteData(sourceKey);
    bool? favorite;
    if (adding) {
      favorite = true;
    } else if (!data.multiFolder) {
      favorite = false;
    }
    return run(
      sourceKey,
      () async {
        final result = await runner.changeFavorite(
          data,
          comicId,
          folderId,
          adding,
        );
        if (!result.error && result.data && !adding && data.multiFolder) {
          final folders = await runner.loadFavoriteFolders(data, comicId);
          if (!folders.error && folders.subData is Iterable) {
            favorite = (folders.subData as Iterable).isNotEmpty;
          }
        }
        return result;
      },
      comicId: comicId,
      operationKey: '$comicId:$folderId:$adding',
      favoriteResult: () => favorite,
    );
  }
}

/// 网络收藏夹与作品所在收藏夹的加载结果。
class NetworkFavoriteFolders {
  NetworkFavoriteFolders(Map<String, String> folders, Iterable<String> selected)
    : folders = Map.unmodifiable(folders),
      selected = Set.unmodifiable(selected);
  final Map<String, String> folders;
  final Set<String> selected;
}

/// 网络收藏夹查询身份，按来源和作品隔离。
typedef NetworkFavoriteFolderQuery = ({String sourceKey, String? comicId});

/// 收藏夹的加载和错误状态不再保存于 Widget。
@riverpod
Future<NetworkFavoriteFolders> networkFavoriteFolders(
  Ref ref,
  NetworkFavoriteFolderQuery query,
) async {
  ref.watch(networkFavoriteRevisionProvider(query.sourceKey));
  await ref.watch(comicSourceRegistryProvider.future);
  if (!ref.mounted) return NetworkFavoriteFolders({}, []);
  final data = getFavoriteData(query.sourceKey);
  final result = await ref
      .read(comicSourceCallbackRunnerProvider)
      .loadFavoriteFolders(data, query.comicId);
  if (result.error) throw StateError(result.errorMessageWithoutNull);
  return NetworkFavoriteFolders(
    result.data,
    result.subData is Iterable
        ? (result.subData as Iterable).whereType<String>()
        : const [],
  );
}

/// 一次浏览或导入任务的稳定分页身份。
typedef NetworkFavoriteLoaderQuery = ({
  String sourceKey,
  String? folderId,
  String sessionId,
});

/// 独立分页会话；E-Hentai 的游标和页缓存不会跨收藏夹共享。
class NetworkFavoritePageLoader {
  NetworkFavoritePageLoader({required this.loadPage, this.loadGallery});
  final Future<Res<List<BaseComic>>> Function(int page) loadPage;
  final Future<Res<Galleries>> Function(String? next)? loadGallery;
  final _lock = Lock();
  final _cache = <List<BaseComic>>[];
  String? _next;
  int _generation = 0;

  /// 刷新或释放当前会话。
  void reset() {
    _generation++;
    _cache.clear();
    _next = null;
  }

  /// 串行加载游标分页，拒绝刷新前返回的旧结果。
  Future<Res<List<BaseComic>>> load(int page) {
    final generation = _generation;
    return _lock.synchronized(() async {
      if (generation != _generation) return const Res.error('请求已取消');
      if (loadGallery == null) {
        final result = await loadPage(page);
        if (generation != _generation) return const Res.error('请求已取消');
        if (result.error) return result;
        return Res(List.unmodifiable(result.data), subData: result.subData);
      }
      if (page == 1) {
        _cache.clear();
        _next = null;
      }
      while (_cache.length < page) {
        if (_cache.isNotEmpty && _next == null) {
          return Res(const [], subData: _cache.length);
        }
        final result = await loadGallery!(_next);
        if (generation != _generation) return const Res.error('请求已取消');
        if (result.error) return Res.fromErrorRes(result);
        _cache.add(List.unmodifiable(result.data.galleries));
        _next = result.data.next;
      }
      return Res(
        _cache[page - 1],
        subData: _next == null ? _cache.length : null,
      );
    });
  }
}

/// 页面监听此 Provider 持有会话，后台任务在运行期间显式保持它存活。
@riverpod
NetworkFavoritePageLoader networkFavoriteLoader(
  Ref ref,
  NetworkFavoriteLoaderQuery query,
) {
  ref.watch(comicSourceRegistryProvider);
  final data = getFavoriteDataOrNull(query.sourceKey);
  final network = query.sourceKey == 'ehentai'
      ? ref.read(ehNetworkProvider)
      : null;
  final firstUrl = network == null
      ? null
      : '${network.ehBaseUrl}/favorites.php'
            '${query.folderId == null || query.folderId == "-1" ? "" : "?favcat=${query.folderId}"}';
  final runner = ref.read(comicSourceCallbackRunnerProvider);
  final loader = NetworkFavoritePageLoader(
    loadPage: (page) => data == null
        ? Future.value(const Res.error('漫画源不可用'))
        : runner.loadFavorites(data, page, query.folderId),
    loadGallery: network == null
        ? null
        : (next) => network.getGalleries(next ?? firstUrl!, favoritePage: true),
  );
  ref.onDispose(loader.reset);
  return loader;
}

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/res.dart';

import 'local_favorites_providers.dart';
import 'network_favorites_providers.dart';

part 'favorite_panel_providers.g.dart';

/// 详情面板的稳定会话配置，保留漫画源既有操作参数。
class FavoritePanelConfig {
  const FavoritePanelConfig({
    required this.sessionId,
    required this.item,
    required this.loadFolders,
    required this.initialFolders,
    this.foldersLoader,
    this.selectFolder,
    this.cancelPlatform,
    this.cancelFolder,
  });
  final String sessionId;
  final FavoriteItem item;
  final bool loadFolders;
  final Map<String, String> initialFolders;
  final Future<Res<Map<String, String>>> Function()? foldersLoader;
  final FutureOr<Res<bool>> Function(String folder, int type)? selectFolder;
  final Future<Res<bool>> Function()? cancelPlatform;
  final Future<Res<bool>> Function(String folder)? cancelFolder;

  String get sourceKey => item.type.comicSource?.key.name ?? item.type.name;

  @override
  bool operator ==(Object other) =>
      other is FavoritePanelConfig && other.sessionId == sessionId;
  @override
  int get hashCode => sessionId.hashCode;
}

/// 网络夹目录和作品归属的加载快照。
@riverpod
Future<NetworkFavoriteFolders> favoritePanelFolders(
  Ref ref,
  FavoritePanelConfig config,
) async {
  ref.watch(networkFavoriteRevisionProvider(config.sourceKey));
  if (!config.loadFolders || config.foldersLoader == null) {
    return NetworkFavoriteFolders(config.initialFolders, []);
  }
  final result = await config.foldersLoader!();
  if (result.error) throw StateError(result.errorMessageWithoutNull);
  return NetworkFavoriteFolders(
    result.data,
    result.subData is Iterable
        ? (result.subData as Iterable).whereType<String>()
        : const [],
  );
}

/// 面板的操作与错误状态；未提交的勾选仍由界面保存。
@riverpod
class FavoritePanelActions extends _$FavoritePanelActions {
  @override
  AsyncValue<void> build(FavoritePanelConfig config) => const AsyncData(null);

  /// 将持久化或网络错误转为面板可观察的状态。
  Future<Res<bool>> _run(Future<Res<bool>> Function() action) async {
    if (state.isLoading) return const Res.error('收藏操作进行中');
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final result = await action();
      if (ref.mounted) {
        state = result.error
            ? AsyncError(
                StateError(result.errorMessageWithoutNull),
                StackTrace.current,
              )
            : const AsyncData(null);
      }
      return result;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      return Res.error(error.toString());
    } finally {
      link.close();
    }
  }

  /// 添加到所选收藏夹，本地多夹操作在同一事务内完成。
  Future<Res<bool>> add(List<String> folders, int type) => _run(() async {
    if (type == 1) {
      await ref
          .read(localFavoritesProvider.notifier)
          .addToFolders(folders, config.item);
      return const Res(true);
    }
    final callback = config.selectFolder;
    if (callback == null) return const Res.error('不支持收藏操作');
    final actions = ref.read(networkFavoriteActionsProvider.notifier);
    for (final folder in folders) {
      final result = await actions.run(
        config.sourceKey,
        () async => callback(folder, 0),
        comicId: config.item.target,
        favorite: true,
        operationKey: 'add:${config.item.target}:$folder',
      );
      if (result.error) return result;
    }
    return const Res(true);
  });

  /// 取消本地多夹收藏。
  Future<Res<bool>> removeLocal(List<String> folders) => _run(() async {
    await ref
        .read(localFavoritesProvider.notifier)
        .removeFromFolders(folders, config.item);
    return const Res(true);
  });

  /// 取消网络收藏，保留单夹取消时其他夹的归属。
  Future<Res<bool>> removePlatform([String? folder]) => _run(() async {
    final snapshot = await ref.read(
      favoritePanelFoldersProvider(config).future,
    );
    final actions = ref.read(networkFavoriteActionsProvider.notifier);
    Future<Res<bool>> Function()? callback;
    if (folder == null) {
      callback = config.cancelPlatform;
    } else if (config.cancelFolder != null) {
      callback = () => config.cancelFolder!(folder);
    }
    if (callback == null) return const Res.error('不支持取消收藏');
    return actions.run(
      config.sourceKey,
      callback,
      comicId: config.item.target,
      operationKey: 'remove:${config.item.target}:$folder',
      favorite: folder == null
          ? false
          : snapshot.selected.any((e) => e != folder),
    );
  });
}

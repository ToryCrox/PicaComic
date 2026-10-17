import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'directory_favorite.dart';
import '../network/download/download_manager.dart';
import 'directory_favorites_repository.dart';
import '../tools/image_utils.dart';

part 'directory_favorites_providers.g.dart';

/// 应用级目录收藏仓库。
@Riverpod(keepAlive: true)
DirectoryFavoritesRepository directoryFavoritesRepository(Ref ref) {
  final manager = ref.read(downloadManagerProvider.notifier);
  final repository = DirectoryFavoritesRepository(ensureReady: manager.init);
  ref.onDispose(repository.dispose);
  return repository;
}

/// 单个目录的收藏状态。
@riverpod
Future<LocalFavoriteItem?> directoryFavorite(Ref ref, String path) {
  final repository = ref.watch(directoryFavoritesRepositoryProvider);
  final subscription = repository.changes.listen((change) {
    if (ref.mounted && change.affects(path)) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  return repository.find(path);
}

/// 目录是否存在，不进行同步磁盘访问。
@riverpod
Future<bool> comicDirectoryExists(Ref ref, String path) =>
    Directory(path).exists();

/// 按卡片需要懒加载目录封面。
@riverpod
Future<String> comicDirectoryCover(Ref ref, String path) async {
  if (!await ref.watch(comicDirectoryExistsProvider(path).future)) return '';
  try {
    return (await Directory(
      path,
    ).list(recursive: true).firstWhere(predictImageFile)).path;
  } on StateError {
    return '';
  }
}

/// 收藏列表及目录收藏写操作。
@riverpod
class DirectoryFavorites extends _$DirectoryFavorites {
  @override
  Future<List<LocalFavoriteItem>> build() async {
    final repository = ref.watch(directoryFavoritesRepositoryProvider);
    final subscription = repository.changes.listen((_) {
      if (ref.mounted) ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    final items = await repository.getAll();
    if (!ref.mounted) return const [];
    final exists = await Future.wait(
      items.map((e) => ref.watch(comicDirectoryExistsProvider(e.path).future)),
    );
    return List.unmodifiable([
      for (var i = 0; i < items.length; i++)
        if (exists[i]) items[i],
    ]);
  }

  /// 通过独立操作状态保留失败，避免替换已加载列表。
  Future<void> _run(
    Future<void> Function(DirectoryFavoritesRepository) action,
  ) {
    final repository = ref.read(directoryFavoritesRepositoryProvider);
    return ref
        .read(directoryFavoriteActionsProvider.notifier)
        .run(() => action(repository));
  }

  /// 添加收藏。
  Future<void> add(String path) => _run((repository) => repository.add(path));

  /// 取消收藏。
  Future<void> remove(String path) =>
      _run((repository) => repository.remove(path));

  /// 保存排序权重。
  Future<void> reorder(String path, int weight) =>
      _run((repository) => repository.reorder(path, weight));
}

/// 目录收藏写操作的加载和错误状态。
@Riverpod(keepAlive: true)
class DirectoryFavoriteActions extends _$DirectoryFavoriteActions {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// 失败只更新操作状态，保留数据库与列表的原数据。
  Future<void> run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      if (ref.mounted) state = const AsyncData(null);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }
}

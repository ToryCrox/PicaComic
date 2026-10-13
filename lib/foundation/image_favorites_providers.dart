import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/download/download_manager.dart';
import 'image_favorites.dart';
import 'image_favorites_repository.dart';

part 'image_favorites_providers.g.dart';

/// 仓库复用当前 ProviderScope 的下载服务，不创建全局容器。
final imageFavoritesRepositoryProvider = Provider<ImageFavoritesRepository>((
  ref,
) {
  final manager = ref.read(downloadManagerProvider.notifier);
  final repository = ImageFavoritesRepository(
    rootPath: () => manager.path!,
    comicDirectory: manager.getFullDirectory,
    ensureReady: manager.init,
  );
  ref.onDispose(() {
    unawaited(repository.dispose());
  });
  return repository;
});

/// 全局收藏数据及操作，页面的局部显示状态仍由页面保存。
@Riverpod(keepAlive: true)
class ImageFavorites extends _$ImageFavorites {
  @override
  Future<List<ImageFavorite>> build() async {
    final repository = ref.watch(imageFavoritesRepositoryProvider);
    final subscription = repository.changes.listen((_) {
      if (ref.mounted) ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    return repository.getAll();
  }

  /// 收藏操作完成后才返回，缩略图在后台生成。
  Future<void> add(
    ImageFavorite draft,
    File source, {
    String downloadId = '',
  }) async {
    final repository = ref.read(imageFavoritesRepositoryProvider);
    final favorite = await repository.add(
      draft,
      source,
      downloadId: downloadId,
    );
    unawaited(repository.prepareThumbnail(favorite));
  }

  /// 取消收藏及其自有文件。
  Future<void> delete(String recordId) =>
      ref.read(imageFavoritesRepositoryProvider).delete(recordId);
}

/// 按标题过滤收藏，不重复读取数据库。
@riverpod
Future<List<ImageFavorite>> filteredImageFavorites(
  Ref ref,
  String title,
) async {
  final images = await ref.watch(imageFavoritesProvider.future);
  return title.isEmpty
      ? images
      : images.where((image) => image.title == title).toList();
}

/// 标题分组。
@riverpod
Future<List<String>> imageFavoriteTitles(Ref ref) async {
  return (await ref.watch(
    imageFavoritesProvider.future,
  )).map((image) => image.title).toSet().toList();
}

/// 图片收藏数量。
@riverpod
Future<int> imageFavoriteCount(Ref ref) async =>
    (await ref.watch(imageFavoritesProvider.future)).length;

/// 缩略图按可见卡片加载，失效后重新检查文件。
@riverpod
Future<File> imageFavoriteThumbnail(Ref ref, ImageFavorite favorite) async {
  final repository = ref.watch(imageFavoritesRepositoryProvider);
  final subscription = repository.changes.listen((_) {
    if (ref.mounted) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  return repository.thumbnail(favorite);
}

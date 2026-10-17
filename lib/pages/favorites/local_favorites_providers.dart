import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/repository_change.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/download/download_manager.dart';

part 'local_favorites_providers.g.dart';

/// 现有数据库的应用级存储适配。
@Riverpod(keepAlive: true)
LocalFavoritesManager localFavoritesRepository(Ref ref) =>
    LocalFavoritesManager();

/// 收藏夹目录快照。
class LocalFavoritesState {
  const LocalFavoritesState({required this.folderNames});
  final List<String> folderNames;
}

/// 订阅收藏存储变更，查询随页面释放。
void _observe(
  Ref ref,
  LocalFavoritesManager repository, [
  bool Function(RepositoryChange<FavoriteIdentity>)? accepts,
]) {
  final subscription = repository.changes.listen((change) {
    if (ref.mounted && (accepts == null || accepts(change))) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(subscription.cancel);
}

/// 收藏写操作的共享错误状态，与列表刷新状态分离。
@Riverpod(keepAlive: true)
class FavoriteActionStatus extends _$FavoriteActionStatus {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// 失败保持数据快照，调用方可以展示操作错误。
  Future<T> run<T>(Future<T> Function() operation) async {
    state = const AsyncLoading();
    try {
      final result = await operation();
      if (ref.mounted) state = const AsyncData(null);
      return result;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }
}

/// 收藏夹目录及统一持久化操作入口。
@Riverpod(keepAlive: true)
class LocalFavorites extends _$LocalFavorites {
  @override
  Future<LocalFavoritesState> build() async {
    final repository = ref.watch(localFavoritesRepositoryProvider);
    _observe(ref, repository, (change) => change.foldersChanged);
    return LocalFavoritesState(
      folderNames: List.unmodifiable(await repository.folderNames),
    );
  }

  /// 执行写操作并保留独立错误状态。
  Future<T> _run<T>(
    Future<T> Function(LocalFavoritesManager repository) action,
  ) {
    final repository = ref.read(localFavoritesRepositoryProvider);
    return ref
        .read(favoriteActionStatusProvider.notifier)
        .run(() => action(repository));
  }

  /// 手动重试目录读取。
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// 创建收藏夹。
  Future<String> createFolder(
    String name, {
    bool renameWhenInvalidName = false,
  }) => _run(
    (repository) => repository.createFolder(name, renameWhenInvalidName),
  );

  /// 删除收藏夹。
  Future<void> deleteFolder(String name) =>
      _run((repository) => repository.deleteFolder(name));

  /// 重命名收藏夹。
  Future<void> renameFolder(String before, String after) =>
      _run((repository) => repository.rename(before, after));

  /// 添加漫画。
  Future<void> addComic(
    String folder,
    FavoriteItem item, {
    DownloadManager? manager,
  }) => _run((repository) => repository.addComic(folder, item, null, manager));

  /// 原子添加多个收藏夹归属。
  Future<void> addToFolders(List<String> folders, FavoriteItem item) => _run(
    (repository) => repository.setMembership(folders, item, adding: true),
  );

  /// 原子取消多个收藏夹归属。
  Future<void> removeFromFolders(List<String> folders, FavoriteItem item) =>
      _run(
        (repository) => repository.setMembership(folders, item, adding: false),
      );

  /// 取消漫画收藏。
  Future<void> deleteComic(String folder, FavoriteItem item) =>
      _run((repository) => repository.deleteComic(folder, item));

  /// 批量取消收藏。
  Future<void> deleteComics(String folder, List<FavoriteItem> items) =>
      _run((repository) => repository.deleteComics(folder, items));

  /// 复制到收藏夹。
  Future<void> copyComics(String folder, List<FavoriteItem> items) =>
      _run((repository) => repository.copyComics(folder, items));

  /// 编辑标签。
  Future<void> editTags(String folder, FavoriteItem item, List<String> tags) =>
      _run(
        (repository) =>
            repository.editTags(item.target, folder, tags, item.type),
      );

  /// 保存作品信息。
  Future<void> updateInfo(String folder, FavoriteItem item) =>
      _run((repository) => repository.updateInfo(folder, item));

  /// 保存漫画排序。
  Future<void> reorder(String folder, List<FavoriteItem> items) =>
      _run((repository) => repository.reorder(items, folder));

  /// 保存收藏夹顺序。
  Future<void> reorderFolders(List<String> folders) => _run(
    (repository) => repository.updateOrder({
      for (var i = 0; i < folders.length; i++) folders[i]: i,
    }),
  );

  /// 导入收藏夹文件。
  Future<void> importFolder(String json) => _run((repository) async {
    final result = await repository.loadFolderData(json);
    if (result.$1) throw StateError(result.$2);
  });
}

/// 单个收藏夹内容；空集合代表夹内无作品。
@riverpod
Future<List<FavoriteItem>> folderFavorites(Ref ref, String folder) {
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(
    ref,
    repository,
    (change) => change.keys == null || change.folders.contains(folder),
  );
  return repository.getAllComics(folder);
}

/// 单个收藏夹的数量，不为数量读取所有条目。
@riverpod
Future<int> localFavoriteCount(Ref ref, String folder) async {
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(
    ref,
    repository,
    (change) => change.keys == null || change.folders.contains(folder),
  );
  if (!(await repository.folderNames).contains(folder)) return 0;
  return repository.count(folder);
}

/// 卡片收藏标记的轻量身份索引。
@Riverpod(keepAlive: true)
Future<Set<FavoriteIdentity>> favoriteIdentities(Ref ref) {
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(
    ref,
    repository,
    (change) => change.keys == null || change.keys!.isNotEmpty,
  );
  return repository.identities();
}

/// 查询作品所在的本地收藏夹。
@riverpod
Future<List<String>> favoriteMembership(Ref ref, FavoriteIdentity identity) {
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(ref, repository, (change) => change.affects(identity));
  return repository.find(identity.target, FavoriteType(identity.type));
}

/// 单个收藏夹的同步配置。
@riverpod
Future<FolderSync?> favoriteFolderSync(Ref ref, String folder) async {
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(
    ref,
    repository,
    (change) => change.keys == null || change.folders.contains(folder),
  );
  for (final sync in await repository.folderSync) {
    if (sync.folderName == folder) return sync;
  }
  return null;
}

/// 搜索请求，关键词相同的页面共享查询结果。
@riverpod
Future<List<FavoriteItemWithFolderInfo>> favoriteSearch(
  Ref ref,
  String keyword,
) async {
  if (keyword.isEmpty) return const [];
  final repository = ref.watch(localFavoritesRepositoryProvider);
  _observe(ref, repository);
  return List.unmodifiable(await repository.search(keyword));
}

/// 搜索输入防抖；提交立即生效，旧查询由 family 生命周期隔离。
@riverpod
class FavoriteSearchInput extends _$FavoriteSearchInput {
  Timer? _timer;
  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return '';
  }

  /// 输入后等待 300 毫秒。
  void change(String keyword) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (ref.mounted) state = keyword;
    });
  }

  /// 立即提交当前输入。
  void submit(String keyword) {
    _timer?.cancel();
    state = keyword;
  }
}

/// 收藏封面身份包含 URL，避免作品元数据变化被身份比较吞掉。
typedef FavoriteCoverQuery = ({int type, String target, String cover});

/// 已下载徽标，随下载数据库变更刷新。
@riverpod
Future<bool> favoriteDownloaded(Ref ref, FavoriteIdentity identity) async {
  final manager = ref.watch(downloadManagerProvider.notifier);
  final subscription = manager.onComicsChanged.listen((_) {
    if (ref.mounted) ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
  await manager.init();
  return manager.isExists(
    manager.getDownloadIdFromComicId(
      FavoriteType(identity.type).comicType,
      identity.target,
    ),
  );
}

/// 封面按需加载，优先使用下载封面。
@riverpod
Future<File> favoriteCover(Ref ref, FavoriteCoverQuery query) async {
  final identity = (type: query.type, target: query.target);
  final downloaded = ref.watch(favoriteDownloadedProvider(identity).future);
  final manager = ref.watch(downloadManagerProvider.notifier);
  final repository = ref.watch(localFavoritesRepositoryProvider);
  final ehNetwork = query.type == FavoriteType.ehentai.key
      ? ref.read(ehNetworkProvider)
      : null;
  if (await downloaded) {
    return manager.getCover(
      manager.getDownloadIdFromComicId(
        FavoriteType(query.type).comicType,
        query.target,
      ),
    );
  }
  final cookie = ehNetwork == null ? '' : await ehNetwork.getCookies(false);
  return repository.getCover(
    FavoriteItem(
      target: query.target,
      name: '',
      coverPath: query.cover,
      author: '',
      type: FavoriteType(query.type),
      tags: const [],
    ),
    manager: manager,
    loadDownloadedCover: manager.getCover,
    ehCookie: cookie,
  );
}

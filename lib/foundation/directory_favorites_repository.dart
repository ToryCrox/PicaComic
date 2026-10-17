import 'dart:async';

import 'package:synchronized/synchronized.dart';

import 'batch_lookup.dart';
import 'database/download_database.dart';
import 'directory_favorite.dart';
import 'repository_change.dart';

/// 目录收藏存储；不依赖下载队列或界面生命周期。
class DirectoryFavoritesRepository {
  DirectoryFavoritesRepository({
    DownloadDatabase? database,
    Future<void> Function()? ensureReady,
  }) : _db = database ?? DownloadDatabase(),
       _ensureReady = ensureReady;

  final DownloadDatabase _db;
  final Future<void> Function()? _ensureReady;
  final _lock = Lock();
  final _changes = StreamController<RepositoryChange<String>>.broadcast();
  late final _lookup = BatchLookup<String, LocalFavoriteItem>(_load);

  Stream<RepositoryChange<String>> get changes => _changes.stream;

  /// 以 SQLite 参数安全的大小分批查询。
  Future<Map<String, LocalFavoriteItem>> _load(List<String> paths) async {
    await _ensureReady?.call();
    final result = <String, LocalFavoriteItem>{};
    for (var offset = 0; offset < paths.length; offset += 400) {
      final rows = await _db.getLocalFavoritesByPaths(
        paths.skip(offset).take(400).toList(),
      );
      for (final row in rows) {
        final item = LocalFavoriteItem.fromMap(row);
        result[item.path] = item;
      }
    }
    return result;
  }

  /// 查找目录收藏。
  Future<LocalFavoriteItem?> find(String path) => _lookup.get(path);

  /// 获取按权重和时间排序的收藏列表。
  Future<List<LocalFavoriteItem>> getAll() async {
    await _ensureReady?.call();
    return List.unmodifiable(
      (await _db.getAllLocalFavorites()).map(LocalFavoriteItem.fromMap),
    );
  }

  /// 添加目录收藏。
  Future<void> add(String path, {int sortOrder = 0}) =>
      _lock.synchronized(() async {
        await _ensureReady?.call();
        await _db.addOrUpdateLocalFavorite(path, sortOrder: sortOrder);
        final row = await _db.getLocalFavorite(path);
        _lookup.set(path, row == null ? null : LocalFavoriteItem.fromMap(row));
        _changes.add(RepositoryChange(keys: {path}));
      });

  /// 修改目录权重。
  Future<void> reorder(String path, int sortOrder) =>
      _lock.synchronized(() async {
        await _ensureReady?.call();
        await _db.updateLocalFavoriteSortOrder(path, sortOrder);
        final row = await _db.getLocalFavorite(path);
        _lookup.set(path, row == null ? null : LocalFavoriteItem.fromMap(row));
        _changes.add(RepositoryChange(keys: {path}));
      });

  /// 取消目录收藏。
  Future<void> remove(String path) => _lock.synchronized(() async {
    await _ensureReady?.call();
    await _db.deleteLocalFavorite(path);
    _lookup.set(path, null);
    _changes.add(RepositoryChange(keys: {path}));
  });

  /// 释放通知资源。
  Future<void> dispose() => _changes.close();
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/foundation/local_favorites.dart';

/// 本地收藏功能的只读状态快照。
class LocalFavoritesState {
  const LocalFavoritesState({required this.folderNames});

  final List<String> folderNames;
}

/// 本地收藏功能状态。
///
/// Manager 只负责数据库访问；Notifier 负责懒加载、刷新和错误状态。
class LocalFavoritesNotifier extends AsyncNotifier<LocalFavoritesState> {
  LocalFavoritesManager get _manager => LocalFavoritesManager();
  StreamSubscription<void>? _subscription;
  bool _disposed = false;
  bool _refreshScheduled = false;

  @override
  Future<LocalFavoritesState> build() async {
    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
    });
    await _manager.init();
    if (_disposed) {
      return const LocalFavoritesState(folderNames: []);
    }
    await _subscription?.cancel();
    _subscription = _manager.changes.listen((_) {
      if (!_disposed) {
        _scheduleRefresh();
      }
    });
    return _snapshot();
  }

  Future<LocalFavoritesState> _snapshot() async {
    final folders = await _manager.folderNames;
    return LocalFavoritesState(folderNames: List.unmodifiable(folders));
  }

  Future<LocalFavoritesState> _load() async {
    await _manager.init();
    return _snapshot();
  }

  Future<void> _refreshFromRepository() async {
    final next = await AsyncValue.guard(_load);
    if (!_disposed) state = next;
  }

  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!_disposed) unawaited(_refreshFromRepository());
    });
  }

  /// 重新读取收藏夹列表。
  Future<void> refresh() async {
    if (_disposed) return;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(_load);
    if (!_disposed) state = next;
  }

  /// 创建收藏夹并刷新 Provider 状态。
  Future<String> createFolder(
    String name, {
    bool renameWhenInvalidName = false,
  }) async {
    await _manager.init();
    final result = await _manager.createFolder(name, renameWhenInvalidName);
    await refresh();
    return result;
  }

  /// 删除收藏夹并刷新 Provider 状态。
  Future<void> deleteFolder(String name) async {
    await _manager.init();
    await _manager.deleteFolder(name);
    await refresh();
  }

  /// 重命名收藏夹并刷新 Provider 状态。
  Future<void> renameFolder(String before, String after) async {
    await _manager.init();
    await _manager.rename(before, after);
    await refresh();
  }
}

final localFavoritesProvider =
    AsyncNotifierProvider<LocalFavoritesNotifier, LocalFavoritesState>(
      LocalFavoritesNotifier.new,
    );

/// 单个收藏夹的漫画数量。
final localFavoriteCountProvider = FutureProvider.family<int, String>((
  ref,
  folder,
) async {
  final state = await ref.watch(localFavoritesProvider.future);
  if (!state.folderNames.contains(folder)) return 0;
  return LocalFavoritesManager().count(folder);
});

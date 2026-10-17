import 'package:pica_comic/network/comic_source_services.dart';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/repository_change.dart';

import 'local_favorites_providers.dart';
import '../../foundation/log.dart';

part 'favorites_session.g.dart';

/// 仅在存储边界读写旧的收藏页导航格式。
class FavoritesNavigationStore {
  /// 读取上次打开的位置。
  String read() => appdata.implicitData[0];

  /// 保持现有隐式设置格式，网络位置仍保存展示名称。
  Future<void> write(FavoritesSessionState state) async {
    final kind = state.isNetwork == null ? '' : (state.isNetwork! ? '1' : '0');
    appdata.implicitData[0] =
        '${state.selectingFolder ? 1 : 0};$kind;${state.current ?? ''}';
    await appdata.writeImplicitData();
  }
}

/// 收藏页导航存储，可在测试中替换。
@Riverpod(keepAlive: true)
FavoritesNavigationStore favoritesNavigationStore(Ref ref) =>
    FavoritesNavigationStore();

/// 收藏页会话快照，不持有 Widget、菜单函数或漫画对象。
class FavoritesSessionState {
  const FavoritesSessionState({
    this.current,
    this.isNetwork,
    this.sourceKey,
    this.selectingFolder = true,
    this.selected = const {},
  });

  final String? current;
  final bool? isNetwork;
  final String? sourceKey;
  final bool selectingFolder;
  final Set<FavoriteIdentity> selected;

  /// 更新当前面板和选择集合。
  FavoritesSessionState copyWith({
    String? current,
    bool? selectingFolder,
    Set<FavoriteIdentity>? selected,
  }) => FavoritesSessionState(
    current: current ?? this.current,
    isNetwork: isNetwork,
    sourceKey: sourceKey,
    selectingFolder: selectingFolder ?? this.selectingFolder,
    selected: selected == null ? this.selected : Set.unmodifiable(selected),
  );
}

/// 页面挂载期间共享导航和多选，卸载后按存储重建。
@riverpod
class FavoritesSession extends _$FavoritesSession {
  @override
  FavoritesSessionState build() {
    final repository = ref.read(localFavoritesRepositoryProvider);
    final subscription = repository.changes.listen((change) {
      unawaited(_repositoryChanged(change));
    });
    ref.onDispose(subscription.cancel);
    ref.listen(localFavoritesProvider, (_, next) {
      if (next.isLoading || next.hasError) return;
      final folders = next.asData?.value.folderNames;
      if (folders != null &&
          state.isNetwork == false &&
          !folders.contains(state.current)) {
        _replace(const FavoritesSessionState());
      }
    });
    ref.listen(
      appSettingProvider(AppSettingKeys.networkFavoritePages),
      (_, __) => _validateNetwork(),
    );
    ref.listen(comicSourceRegistryProvider, (_, __) => _validateNetwork());
    final parts = ref.read(favoritesNavigationStoreProvider).read().split(';');
    if (parts.length < 3) return const FavoritesSessionState();
    final current = parts.sublist(2).join(';');
    if (current.isEmpty) return const FavoritesSessionState();
    if (parts[1] == '1') {
      for (final key
          in ref
              .read(appSettingProvider(AppSettingKeys.networkFavoritePages))
              .split(',')) {
        final data = getFavoriteDataOrNull(key);
        if (data != null && (data.title == current || data.key == current)) {
          return FavoritesSessionState(
            current: data.title,
            isNetwork: true,
            sourceKey: data.key,
            selectingFolder: parts[0] == '1',
          );
        }
      }
      return const FavoritesSessionState();
    }
    return FavoritesSessionState(
      current: current,
      isNetwork: false,
      selectingFolder: parts[0] == '1',
    );
  }

  /// 写入会话，并保存兼容的导航位置。
  void _replace(FavoritesSessionState next) {
    state = next;
    unawaited(
      ref.read(favoritesNavigationStoreProvider).write(next).catchError((
        Object error,
        StackTrace stack,
      ) {
        Log.w('保存收藏页位置失败', error: error, stackTrace: stack);
      }),
    );
  }

  /// 来源删除或禁用后回到收藏夹列表。
  void _validateNetwork() {
    if (state.isNetwork != true) return;
    final keys = ref
        .read(appSettingProvider(AppSettingKeys.networkFavoritePages))
        .split(',');
    if (!keys.contains(state.sourceKey) ||
        getFavoriteDataOrNull(state.sourceKey!) == null) {
      _replace(const FavoritesSessionState());
    }
  }

  /// 存储变化后保持当前位置及有效选择。
  Future<void> _repositoryChanged(
    RepositoryChange<FavoriteIdentity> change,
  ) async {
    if (!ref.mounted || state.isNetwork != false) return;
    if (change.previousName == state.current) {
      if (change.currentName == null) {
        _replace(const FavoritesSessionState());
        return;
      }
      _replace(state.copyWith(current: change.currentName));
      return;
    }
    final folder = state.current;
    if (folder == null || state.selected.isEmpty) return;
    if (change.keys != null) {
      if (change.removed && change.folders.contains(folder)) {
        state = state.copyWith(
          selected: state.selected.difference(change.keys!),
        );
      }
      return;
    }
    try {
      final items = await ref
          .read(localFavoritesRepositoryProvider)
          .getAllComics(folder);
      if (!ref.mounted || state.current != folder) return;
      final identities = items.map((e) => e.identity).toSet();
      state = state.copyWith(selected: state.selected.intersection(identities));
    } catch (_) {
      // 删除收藏夹的事件会处理导航；其他查询错误交由列表展示。
    }
  }

  /// 打开本地收藏夹并清空多选。
  void openLocal(String folder) => _replace(
    FavoritesSessionState(
      current: folder,
      isNetwork: false,
      selectingFolder: false,
    ),
  );

  /// 打开网络收藏源并清空多选。
  void openNetwork(FavoriteData data) => _replace(
    FavoritesSessionState(
      current: data.title,
      sourceKey: data.key,
      isNetwork: true,
      selectingFolder: false,
    ),
  );

  /// 展开或收起收藏夹面板。
  void toggleFolders() => _replace(
    state.copyWith(
      selectingFolder: state.current == null || !state.selectingFolder,
    ),
  );

  /// 切换单个作品的选择状态。
  void toggle(FavoriteIdentity identity) {
    final selected = {...state.selected};
    if (!selected.remove(identity)) selected.add(identity);
    state = state.copyWith(selected: selected);
  }

  /// 全选当前收藏夹。
  void selectAll(Iterable<FavoriteItem> comics) =>
      state = state.copyWith(selected: comics.map((e) => e.identity).toSet());

  /// 退出多选模式。
  void clearSelection() => state = state.copyWith(selected: {});
}

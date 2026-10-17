import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';

import '../base.dart';
import '../components/comic_list_page_logic.dart';
import 'user_library_events.dart';

part 'user_library_preferences.g.dart';

/// 屏蔽词与标签收藏的旧格式存储适配，界面通过操作 Provider 写入。
class UserLibraryPreferencesRepository {
  final _lock = Lock();

  /// 兼容旧网络服务、导入和数据替换入口的保存通知。
  Stream<void> get changes => userLibraryChanges;

  /// 读取用户列表的独立快照。
  UserLibraryState snapshot() => UserLibraryState(
    searchHistory: appdata.searchHistory,
    favoriteTags: appdata.favoriteTags,
    blockingKeywords: appdata.blockingKeyword,
    showBlockingHint: appdata.firstUse[0] == '1',
  );

  /// 删除屏蔽词，写入失败恢复原列表。
  Future<void> removeBlockedWord(String word) => _lock.synchronized(() async {
    final previous = List<String>.of(appdata.blockingKeyword);
    appdata.blockingKeyword = previous.where((item) => item != word).toList();
    try {
      await appdata.writeData();
    } catch (_) {
      appdata.blockingKeyword = previous;
      rethrow;
    }
  });

  /// 关闭屏蔽词说明，沿用独立的首次使用数据。
  Future<void> dismissBlockingHint() => _lock.synchronized(() async {
    final previous = appdata.firstUse[0];
    appdata.firstUse[0] = '0';
    try {
      await appdata.writeData();
    } catch (_) {
      appdata.firstUse[0] = previous;
      rethrow;
    }
  });

  /// 删除指定搜索记录；未指定时清空搜索历史。
  Future<void> removeSearchHistory([String? keyword]) => _editHistory(() {
    if (keyword == null) {
      appdata.searchHistory.clear();
    } else {
      appdata.searchHistory.remove(keyword);
    }
  });

  /// 删除指定标签；未指定时清空标签收藏。
  Future<void> removeFavoriteTag([String? tag]) => _editHistory(() {
    if (tag == null) {
      appdata.favoriteTags.clear();
    } else {
      appdata.favoriteTags.remove(tag);
    }
  });

  /// 沿用历史存储格式，串行保存并在失败时恢复列表。
  Future<void> _editHistory(void Function() edit) =>
      _lock.synchronized(() async {
        final history = List<String>.of(appdata.searchHistory);
        final tags = Set<String>.of(appdata.favoriteTags);
        edit();
        try {
          await appdata.writeHistory();
        } catch (_) {
          appdata.searchHistory = history;
          appdata.favoriteTags = tags;
          rethrow;
        }
      });

  /// 获取独立快照，不允许界面直接修改原集合。
  List<String> get blockingKeywords =>
      List.unmodifiable(appdata.blockingKeyword);

  /// 合并屏蔽词；保存失败恢复原集合。
  Future<void> addBlockedWords(Iterable<String> words) =>
      _lock.synchronized(() async {
        final previous = List<String>.of(appdata.blockingKeyword);
        final next = {...previous, ...words.where((word) => word.isNotEmpty)};
        appdata.blockingKeyword = next.toList();
        try {
          await appdata.writeData();
        } catch (_) {
          appdata.blockingKeyword = previous;
          rethrow;
        }
      });

  /// 添加标签收藏，保持原有来源与标签编码。
  Future<void> addFavoriteTag(String tag) => _lock.synchronized(() async {
    if (appdata.favoriteTags.contains(tag)) return;
    appdata.favoriteTags.add(tag);
    try {
      await appdata.writeHistory();
    } catch (_) {
      appdata.favoriteTags.remove(tag);
      rethrow;
    }
  });
}

/// 用户列表的不可变快照，与页面筛选和输入草稿分离。
class UserLibraryState {
  UserLibraryState({
    Iterable<String> searchHistory = const [],
    Iterable<String> favoriteTags = const [],
    Iterable<String> blockingKeywords = const [],
    this.showBlockingHint = false,
  }) : searchHistory = List.unmodifiable(searchHistory),
       favoriteTags = List.unmodifiable(favoriteTags),
       blockingKeywords = List.unmodifiable(blockingKeywords);

  final List<String> searchHistory;
  final List<String> favoriteTags;
  final List<String> blockingKeywords;
  final bool showBlockingHint;
}

/// 统一观察用户列表，旧网络服务无需查找任何页面实例。
@Riverpod(keepAlive: true)
class UserLibrary extends _$UserLibrary {
  @override
  UserLibraryState build() {
    final repository = ref.watch(userLibraryPreferencesRepositoryProvider);
    final subscription = repository.changes.listen((_) {
      if (!ref.mounted) return;
      final next = repository.snapshot();
      final blockingChanged = !listEquals(
        state.blockingKeywords,
        next.blockingKeywords,
      );
      state = next;
      if (blockingChanged) {
        ref.read(blockingKeywordRevisionProvider.notifier).bump();
      }
    });
    ref.onDispose(subscription.cancel);
    return repository.snapshot();
  }
}

/// 应用级用户列表存储。
@Riverpod(keepAlive: true)
UserLibraryPreferencesRepository userLibraryPreferencesRepository(Ref ref) =>
    UserLibraryPreferencesRepository();

/// 屏蔽与标签收藏操作的加载、错误状态。
@Riverpod(keepAlive: true)
class UserLibraryPreferencesActions extends _$UserLibraryPreferencesActions {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// 统一等待持久化，并向界面发布操作错误。
  Future<void> _run(Future<void> Function() operation) async {
    // 先建立存储通知订阅，操作完成后统一刷新快照和屏蔽版本。
    ref.read(userLibraryProvider);
    state = const AsyncLoading();
    try {
      await operation();
      if (ref.mounted) state = const AsyncData(null);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }

  /// 屏蔽成功后刷新既有漫画列表过滤。
  Future<void> addBlockedWords(Iterable<String> words) => _run(
    () => ref
        .read(userLibraryPreferencesRepositoryProvider)
        .addBlockedWords(words),
  );

  /// 添加标签收藏。
  Future<void> addFavoriteTag(String tag) => _run(
    () =>
        ref.read(userLibraryPreferencesRepositoryProvider).addFavoriteTag(tag),
  );

  /// 删除屏蔽词并刷新漫画列表。
  Future<void> removeBlockedWord(String word) => _run(
    () => ref
        .read(userLibraryPreferencesRepositoryProvider)
        .removeBlockedWord(word),
  );

  /// 关闭屏蔽词说明。
  Future<void> dismissBlockingHint() => _run(
    () => ref
        .read(userLibraryPreferencesRepositoryProvider)
        .dismissBlockingHint(),
  );

  /// 删除或清空搜索历史。
  Future<void> removeSearchHistory([String? keyword]) => _run(
    () => ref
        .read(userLibraryPreferencesRepositoryProvider)
        .removeSearchHistory(keyword),
  );

  /// 删除或清空标签收藏。
  Future<void> removeFavoriteTag([String? tag]) => _run(
    () => ref
        .read(userLibraryPreferencesRepositoryProvider)
        .removeFavoriteTag(tag),
  );
}

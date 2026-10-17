import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:synchronized/synchronized.dart';

import '../base.dart';
import '../components/comic_list_page_logic.dart';

part 'user_library_preferences.g.dart';

/// 屏蔽词与标签收藏的旧格式存储适配，界面通过操作 Provider 写入。
class UserLibraryPreferencesRepository {
  final _lock = Lock();

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
  Future<void> addBlockedWords(Iterable<String> words) => _run(() async {
    await ref
        .read(userLibraryPreferencesRepositoryProvider)
        .addBlockedWords(words);
    if (ref.mounted) ref.read(blockingKeywordRevisionProvider.notifier).bump();
  });

  /// 添加标签收藏。
  Future<void> addFavoriteTag(String tag) => _run(
    () =>
        ref.read(userLibraryPreferencesRepositoryProvider).addFavoriteTag(tag),
  );
}

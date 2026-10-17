import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'history.dart';
import '../network/download/download_manager.dart';
import 'image_favorites_providers.dart';
import 'local_history.dart';
import 'repository_change.dart';

part 'history_providers.g.dart';

/// 应用级历史存储适配，可在测试中替换。
@Riverpod(keepAlive: true)
HistoryManager historyRepository(Ref ref) => HistoryManager();

/// 应用级本地历史存储适配。
@Riverpod(keepAlive: true)
LocalHistoryManager localHistoryRepository(Ref ref) {
  final repository = LocalHistoryManager();
  repository.bindDatabaseReady(ref.read(downloadManagerProvider.notifier).init);
  return repository;
}

/// 只在相关记录变化时重新读取，订阅随查询释放。
void _observe(
  Ref ref,
  Stream<RepositoryChange<String>> changes, [
  String? key,
]) {
  final subscription = changes.listen((change) {
    if (ref.mounted && (key == null || change.affects(key)))
      ref.invalidateSelf();
  });
  ref.onDispose(subscription.cancel);
}

/// 单个在线漫画的不可变阅读快照。
@riverpod
Future<HistoryRecord?> historyEntry(Ref ref, String target) {
  final repository = ref.watch(historyRepositoryProvider);
  _observe(ref, repository.changes, target);
  return repository.findRecord(target);
}

/// 单个目录的阅读快照。
@riverpod
Future<LocalHistory?> localHistoryEntry(Ref ref, String path) {
  final repository = ref.watch(localHistoryRepositoryProvider);
  _observe(ref, repository.changes, path);
  return repository.find(path);
}

/// 全量历史，沿用历史页现有的搜索和排序策略。
@riverpod
Future<List<HistoryRecord>> allHistory(Ref ref) async {
  final repository = ref.watch(historyRepositoryProvider);
  _observe(ref, repository.changes);
  return List.unmodifiable(
    (await repository.getAll()).map((e) => e.toRecord()),
  );
}

/// 按最近阅读时间排序的本地历史。
@riverpod
Future<List<LocalHistory>> allLocalHistory(Ref ref) {
  final repository = ref.watch(localHistoryRepositoryProvider);
  _observe(ref, repository.changes);
  return repository.getAll();
}

/// 最近阅读记录。
@riverpod
Future<List<HistoryRecord>> recentHistory(Ref ref) async {
  final repository = ref.watch(historyRepositoryProvider);
  _observe(ref, repository.changes);
  return List.unmodifiable(
    (await repository.getRecent()).map((e) => e.toRecord()),
  );
}

/// 历史数据库和图片收藏的摘要。
class HistorySummary {
  const HistorySummary({required this.historyCount, required this.imageCount});
  final int historyCount;
  final int imageCount;
}

/// 历史和图片收藏数量。
@riverpod
Future<HistorySummary> historySummary(Ref ref) async {
  final repository = ref.watch(historyRepositoryProvider);
  _observe(ref, repository.changes);
  final images = ref.watch(imageFavoriteCountProvider.future);
  final counts = await Future.wait([repository.count(), images]);
  return HistorySummary(historyCount: counts[0], imageCount: counts[1]);
}

/// 分页历史，页码从零开始。
@riverpod
Future<List<HistoryRecord>> historyList(Ref ref, int page) async {
  final repository = ref.watch(historyRepositoryProvider);
  _observe(ref, repository.changes);
  return List.unmodifiable(
    (await repository.getPage(page)).map((e) => e.toRecord()),
  );
}

/// 历史写操作及错误状态。
@riverpod
class HistoryActions extends _$HistoryActions {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// 保存操作状态，失败交由调用方展示错误。
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

  /// 删除在线记录。
  Future<void> remove(String target) =>
      _run(() => ref.read(historyRepositoryProvider).remove(target));

  /// 清空在线记录。
  Future<void> clear() =>
      _run(ref.read(historyRepositoryProvider).clearHistory);

  /// 删除本地记录。
  Future<void> removeLocal(String path) =>
      _run(() => ref.read(localHistoryRepositoryProvider).remove(path));

  /// 清空本地记录。
  Future<void> clearLocal() =>
      _run(ref.read(localHistoryRepositoryProvider).clearHistory);

  /// 清理已失效的目录记录。
  Future<int> clearInvalidLocal() async {
    final repository = ref.read(localHistoryRepositoryProvider);
    var count = 0;
    await _run(() async {
      for (final record in await repository.getAll()) {
        if (!await Directory(record.path).exists()) {
          await repository.remove(record.path);
          count++;
        }
      }
    });
    return count;
  }
}

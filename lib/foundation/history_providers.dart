import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'history.dart';

/// 历史数据库和图片收藏的摘要数据。
class HistorySummary {
  const HistorySummary({required this.historyCount, required this.imageCount});

  final int historyCount;
  final int imageCount;
}

/// 最近阅读记录。
final recentHistoryProvider = FutureProvider<List<History>>((ref) async {
  ref.keepAlive();
  final manager = HistoryManager();
  StreamSubscription<void>? subscription;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    subscription?.cancel();
  });
  await manager.init();
  if (disposed) return const [];
  subscription = manager.changes.listen((_) {
    if (!disposed) ref.invalidateSelf();
  });
  return manager.getRecent();
});

/// 历史记录和图片收藏数量。
final historySummaryProvider = FutureProvider<HistorySummary>((ref) async {
  ref.keepAlive();
  final manager = HistoryManager();
  StreamSubscription<void>? historySubscription;
  StreamSubscription<void>? imageSubscription;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    historySubscription?.cancel();
    imageSubscription?.cancel();
  });
  await manager.init();
  if (disposed) return const HistorySummary(historyCount: 0, imageCount: 0);
  historySubscription = manager.changes.listen((_) {
    if (!disposed) ref.invalidateSelf();
  });
  imageSubscription = ImageFavoriteManager.changes.listen((_) {
    if (!disposed) ref.invalidateSelf();
  });
  final counts = await Future.wait<int>([
    manager.count(),
    ImageFavoriteManager.length,
  ]);
  return HistorySummary(historyCount: counts[0], imageCount: counts[1]);
});

/// 分页历史记录。
final historyListProvider = FutureProvider.family<List<History>, int>((
  ref,
  page,
) async {
  final manager = HistoryManager();
  StreamSubscription<void>? subscription;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    subscription?.cancel();
  });
  await manager.init();
  if (disposed) return const [];
  subscription = manager.changes.listen((_) {
    if (!disposed) ref.invalidateSelf();
  });
  const pageSize = 30;
  return manager.getPage(page, pageSize: pageSize);
});

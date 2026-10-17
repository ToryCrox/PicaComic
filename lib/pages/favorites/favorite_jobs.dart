import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pica_comic/foundation/favorite_metadata_service.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/res.dart';

import 'local_favorites_providers.dart';

part 'favorite_jobs.g.dart';

/// 收藏元数据服务，网络依赖来自当前 ProviderScope。
@Riverpod(keepAlive: true)
FavoriteMetadataService favoriteMetadataService(Ref ref) =>
    FavoriteMetadataService(
      ref.watch(comicSourceServicesProvider),
      (query) => ref.read(comicInfoQueryProvider(query).future),
    );

/// 任务阶段，提交事务时不能取消。
enum FavoriteJobPhase {
  idle,
  fetching,
  committing,
  completed,
  cancelled,
  failed,
}

/// 可观察的批量任务快照。
class FavoriteJobState {
  const FavoriteJobState({
    this.phase = FavoriteJobPhase.idle,
    this.completed = 0,
    this.total,
    this.success = 0,
    this.failures = 0,
    this.unavailable = 0,
    this.error,
    this.resultFolder,
  });

  final FavoriteJobPhase phase;
  final int completed;
  final int? total;
  final int success;
  final int failures;
  final int unavailable;
  final String? error;
  final String? resultFolder;

  bool get running =>
      phase == FavoriteJobPhase.fetching ||
      phase == FavoriteJobPhase.committing;
  bool get canCancel => phase == FavoriteJobPhase.fetching;
}

/// 抓取阶段取消，不会进入本地提交。
class FavoriteJobCancelled implements Exception {}

/// 同一目标收藏夹共享一个互斥任务，任务运行期间保持存活。
@riverpod
class FavoriteJob extends _$FavoriteJob {
  Future<FavoriteJobState>? _running;
  bool _cancelled = false;

  @override
  FavoriteJobState build(String folder) {
    ref.onDispose(() => _cancelled = true);
    return const FavoriteJobState();
  }

  /// 获取任务互斥权，重复启动返回当前任务。
  Future<FavoriteJobState> _start(Future<FavoriteJobState> Function() action) {
    final running = _running;
    if (running != null) return running;
    final link = ref.keepAlive();
    _cancelled = false;
    state = const FavoriteJobState(phase: FavoriteJobPhase.fetching);
    final completer = Completer<FavoriteJobState>();
    _running = completer.future;
    unawaited(() async {
      try {
        final result = await action();
        if (ref.mounted) state = result;
        completer.complete(result);
      } on FavoriteJobCancelled {
        final previous = ref.mounted ? state : const FavoriteJobState();
        final result = FavoriteJobState(
          phase: FavoriteJobPhase.cancelled,
          completed: previous.completed,
          total: previous.total,
          success: previous.success,
          failures: previous.failures,
          unavailable: previous.unavailable,
        );
        if (ref.mounted) state = result;
        completer.complete(result);
      } catch (error, stack) {
        final previous = ref.mounted ? state : const FavoriteJobState();
        Log.e('收藏批处理失败', error: error, stackTrace: stack);
        final result = FavoriteJobState(
          phase: FavoriteJobPhase.failed,
          completed: previous.completed,
          total: previous.total,
          success: previous.success,
          failures: previous.failures,
          unavailable: previous.unavailable,
          error: error.toString(),
        );
        if (ref.mounted) state = result;
        completer.complete(result);
      } finally {
        _running = null;
        link.close();
      }
    }());
    return completer.future;
  }

  /// 每个异步边界后检查取消，避免取消后仍写入。
  void _checkCancelled() {
    if (_cancelled || !ref.mounted) throw FavoriteJobCancelled();
  }

  /// 取消抓取或逐条处理，事务提交开始后保持不可取消。
  void cancel() {
    if (ref.mounted && state.canCancel) _cancelled = true;
  }

  /// 完整读取所有指定页，再原子提交导入或同步。
  Future<FavoriteJobState> importNetwork({
    required Future<Res<List<BaseComic>>> Function(int page) loadPage,
    required FavoriteItem Function(BaseComic comic) convert,
    required String targetFolder,
    bool create = false,
    FolderSync? sync,
    int? pageLimit,
    Duration? interval,
    bool Function()? isSessionCurrent,
    Future<void> Function(List<FavoriteItem> items)? prepareCovers,
  }) => _start(() async {
    final repository = ref.read(localFavoritesRepositoryProvider);
    final comics = <FavoriteItem>[];
    int? total;
    var page = 1;
    while (pageLimit == null || page <= pageLimit) {
      _checkCancelled();
      if (isSessionCurrent != null && !isSessionCurrent()) {
        throw FavoriteJobCancelled();
      }
      final result = await loadPage(page);
      _checkCancelled();
      if (result.error) throw StateError(result.errorMessageWithoutNull);
      comics.addAll(result.data.map(convert));
      if (result.subData is int && (result.subData as int) >= 0) {
        total = result.subData as int;
      }
      state = FavoriteJobState(
        phase: FavoriteJobPhase.fetching,
        completed: page,
        total: pageLimit ?? total,
      );
      if (result.data.isEmpty || (total != null && page >= total)) break;
      page++;
      if (interval != null) {
        await Future<void>.delayed(interval);
      } else if (page > 5) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
    }
    _checkCancelled();
    if (isSessionCurrent != null && !isSessionCurrent()) {
      throw FavoriteJobCancelled();
    }
    state = FavoriteJobState(
      phase: FavoriteJobPhase.committing,
      completed: comics.length,
      total: comics.length,
    );
    final result = await repository.importFavorites(
      targetFolder,
      comics,
      create: create,
      sync: sync,
    );
    if (prepareCovers != null) {
      unawaited(
        prepareCovers(List.unmodifiable(comics)).catchError((
          Object error,
          StackTrace stack,
        ) {
          Log.w('收藏已保存，准备封面失败', error: error, stackTrace: stack);
        }),
      );
    }
    return FavoriteJobState(
      phase: FavoriteJobPhase.completed,
      completed: comics.length,
      total: comics.length,
      success: result.$2,
      resultFolder: result.$1,
    );
  });

  /// 逐条更新元数据或检查失效；保留已经提交的处理结果。
  Future<FavoriteJobState> updateItems(
    List<FavoriteItem> items, {
    bool checkAvailability = false,
  }) => _start(() async {
    final repository = ref.read(localFavoritesRepositoryProvider);
    final service = ref.read(favoriteMetadataServiceProvider);
    var success = 0;
    var failures = 0;
    var unavailable = 0;
    final batch = repository.beginChangeBatch();
    try {
      for (var i = 0; i < items.length; i++) {
        _checkCancelled();
        Res<FavoriteItem> result;
        try {
          result = await service.load(items[i]);
        } catch (error) {
          result = Res.error(error.toString());
        }
        _checkCancelled();
        if (result.error) {
          if (checkAvailability && isFavoriteUnavailable(result)) {
            unavailable++;
            await repository.addTagTo(
              folder,
              items[i].target,
              'Unavailable',
              items[i].type,
              batch: batch,
            );
          } else {
            failures++;
          }
        } else {
          if (!checkAvailability) {
            await repository.updateInfo(folder, result.data, batch: batch);
          }
          success++;
        }
        if (!ref.mounted) throw FavoriteJobCancelled();
        state = FavoriteJobState(
          phase: FavoriteJobPhase.fetching,
          completed: i + 1,
          total: items.length,
          success: success,
          failures: failures,
          unavailable: unavailable,
        );
      }
    } finally {
      batch.finish();
    }
    _checkCancelled();
    return FavoriteJobState(
      phase: FavoriteJobPhase.completed,
      completed: items.length,
      total: items.length,
      success: success,
      failures: failures,
      unavailable: unavailable,
    );
  });
}

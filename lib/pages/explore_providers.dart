import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../comic_source/comic_source.dart';
import '../foundation/log.dart';
import '../network/res.dart';

part 'explore_providers.g.dart';

/// 网络失败由页面重试按钮处理，避免后台自动重复加载。
Duration? _noRetry(int count, Object error) => null;

/// 刷新信号按探索页实例、漫画源和页面名称隔离。
@riverpod
class ExploreRefresh extends _$ExploreRefresh {
  @override
  int build(Object session, String sourceKey, String title) => 0;

  /// 刷新当前页面，未挂载页面下次创建时直接读取最新版本。
  void refresh() => state++;
}

/// 多分区探索页保留缓存展示，再以网络结果更新。
@Riverpod(retry: _noRetry)
class ExploreParts extends _$ExploreParts {
  int _generation = 0;

  @override
  Future<List<ExplorePagePart>> build(
    Object session,
    String sourceKey,
    ExplorePageData data,
  ) async {
    ref.watch(exploreRefreshProvider(session, sourceKey, data.title));
    final generation = ++_generation;
    try {
      final cache = await data.loadMultiPartCache?.call();
      if (!ref.mounted || generation != _generation) return [];
      if (cache != null && cache.isNotEmpty) state = AsyncData(cache);
    } catch (error, stack) {
      Log.w('读取探索页缓存失败', error: error, stackTrace: stack);
    }
    if (!ref.mounted || generation != _generation) return [];
    final result = await data.loadMultiPart!(ref);
    if (result.error) throw StateError(result.errorMessageWithoutNull);
    return result.data;
  }
}

/// 混合探索页按会话和刷新版本隔离分页请求，保留原有 Res 约定。
@riverpod
Future<Res<List<Object>>> exploreMixed(
  Ref ref,
  Object session,
  ExplorePageData data,
  int revision,
  int page,
) async {
  try {
    return await data.loadMixed!(ref, page);
  } catch (error, stack) {
    Log.e('加载混合探索页失败', error: error, stackTrace: stack);
    return Res.error(error.toString());
  }
}

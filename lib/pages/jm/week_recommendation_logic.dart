import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'week_recommendation_logic.g.dart';

Duration? _noRetry(int _, Object __) => null;

/// JM 每周推荐网络仓库。
abstract interface class JmWeekRecommendationRepository {
  /// 获取推荐分类。
  Future<Res<Map<String, String>>> getRecommendations();

  /// 获取指定分类的漫画。
  Future<Res<List<JmComicBrief>>> getComics(
    String id,
    WeekRecommendationType type,
  );
}

class _JmWeekRecommendationRepository
    implements JmWeekRecommendationRepository {
  @override
  Future<Res<Map<String, String>>> getRecommendations() {
    return JmNetwork().getWeekRecommendation();
  }

  @override
  Future<Res<List<JmComicBrief>>> getComics(
    String id,
    WeekRecommendationType type,
  ) {
    return JmNetwork().getWeekRecommendationComics(id, type);
  }
}

/// JM 每周推荐网络仓库 Provider，默认使用现有网络实现。
final jmWeekRecommendationRepositoryProvider =
    Provider<JmWeekRecommendationRepository>(
      (ref) => _JmWeekRecommendationRepository(),
    );

/// JM 每周推荐加载异常。
class JmWeekRecommendationException implements Exception {
  const JmWeekRecommendationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// JM 每周推荐分类状态。
class JmWeekRecommendationState {
  const JmWeekRecommendationState({
    required this.recommendations,
    required this.currentId,
    required this.currentName,
  });

  final Map<String, String> recommendations;
  final String currentId;
  final String currentName;

  /// 创建更新后的推荐分类状态。
  JmWeekRecommendationState copyWith({
    Map<String, String>? recommendations,
    String? currentId,
    String? currentName,
  }) {
    return JmWeekRecommendationState(
      recommendations: recommendations ?? this.recommendations,
      currentId: currentId ?? this.currentId,
      currentName: currentName ?? this.currentName,
    );
  }
}

/// JM 每周推荐分类 Provider。
@Riverpod(
  keepAlive: false,
  retry: _noRetry,
  name: 'jmWeekRecommendationProvider',
)
class JmWeekRecommendation extends _$JmWeekRecommendation {
  @override
  Future<JmWeekRecommendationState> build() async {
    final repository = ref.watch(jmWeekRecommendationRepositoryProvider);
    final res = await repository.getRecommendations();
    if (res.error) {
      throw JmWeekRecommendationException(res.errorMessageWithoutNull);
    }
    if (res.data.isEmpty) {
      throw const JmWeekRecommendationException('暂无每周推荐');
    }

    final recommendations = Map<String, String>.unmodifiable(res.data);
    final first = recommendations.entries.first;
    return JmWeekRecommendationState(
      recommendations: recommendations,
      currentId: first.key,
      currentName: first.value,
    );
  }

  /// 选择推荐分类。
  void select(String id) {
    final current = state.value;
    if (current == null) return;
    final name = current.recommendations[id];
    if (name == null) return;
    state = AsyncData(current.copyWith(currentId: id, currentName: name));
  }

  /// 重新加载推荐分类。
  void refresh() {
    ref.invalidateSelf();
  }
}

/// JM 每周推荐漫画 Provider。
@Riverpod(
  keepAlive: false,
  retry: _noRetry,
  name: 'jmWeekRecommendationComicsProvider',
)
Future<List<JmComicBrief>> jmWeekRecommendationComics(
  Ref ref,
  (String id, WeekRecommendationType type) key,
) async {
  final repository = ref.watch(jmWeekRecommendationRepositoryProvider);
  final res = await repository.getComics(key.$1, key.$2);
  if (res.error) {
    throw JmWeekRecommendationException(res.errorMessageWithoutNull);
  }
  return List.unmodifiable(res.data);
}

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'translation_result_replacer.dart';

part 'translation_result_replace_notifier.g.dart';

/// 翻译结果预览弹框的业务操作。
enum TranslationResultReplaceOperation {
  loading,
  idle,
  refreshing,
  cleaning,
  replacing,
}

/// 单个预览弹框使用的扫描和替换依赖。
class TranslationResultReplaceRequest {
  const TranslationResultReplaceRequest({
    required this.onLoad,
    required this.onRefresh,
    required this.replacer,
  });

  final Future<TranslationReplacementBatchPlan> Function() onLoad;
  final Future<TranslationReplacementBatchPlan> Function() onRefresh;
  final TranslationResultReplacer replacer;
}

/// 翻译结果预览弹框状态。
class TranslationResultReplaceState {
  const TranslationResultReplaceState({
    this.batchPlan,
    this.operation = TranslationResultReplaceOperation.loading,
    this.loadError,
    this.showSkippedOnly = false,
    this.skippedOriginalPaths = const <String>{},
    this.protectedOriginalPaths = const <String>{},
  });

  final TranslationReplacementBatchPlan? batchPlan;
  final TranslationResultReplaceOperation operation;
  final Object? loadError;
  final bool showSkippedOnly;
  final Set<String> skippedOriginalPaths;
  final Set<String> protectedOriginalPaths;

  bool get operationBusy =>
      operation == TranslationResultReplaceOperation.refreshing ||
      operation == TranslationResultReplaceOperation.cleaning ||
      operation == TranslationResultReplaceOperation.replacing;

  bool get busy => operation != TranslationResultReplaceOperation.idle;

  int get replacementCount {
    final plan = batchPlan;
    if (plan == null) return 0;
    return plan.pairCount - skippedOriginalPaths.length;
  }

  int get skippedPairCount => skippedOriginalPaths.length;

  int get protectedPairCount => protectedOriginalPaths.length;

  int get totalSkippedPairCount => skippedPairCount;

  int get untranslatablePairCount {
    final plan = batchPlan;
    if (plan == null) return 0;
    return plan.plans.fold(
      0,
      (total, item) =>
          total +
          item.pairs.where((pair) => pair.hasUntranslatableContent).length,
    );
  }

  List<TranslationReplacementPlan> get visiblePlans {
    final plan = batchPlan;
    if (plan == null || !showSkippedOnly) {
      return plan?.plans ?? const <TranslationReplacementPlan>[];
    }
    return plan.plans
        .where(
          (item) => item.pairs.any(
            (pair) =>
                skippedOriginalPaths.contains(pair.originalPath) ||
                protectedOriginalPaths.contains(pair.originalPath),
          ),
        )
        .toList(growable: false);
  }

  bool isPairSkipped(String originalPath) =>
      skippedOriginalPaths.contains(originalPath);

  bool isPairProtected(String originalPath) =>
      protectedOriginalPaths.contains(originalPath);

  bool isPlanFullySkipped(TranslationReplacementPlan plan) {
    return plan.pairs.isNotEmpty &&
        plan.pairs.every(
          (pair) => skippedOriginalPaths.contains(pair.originalPath),
        );
  }

  TranslationResultReplaceState copyWith({
    TranslationReplacementBatchPlan? batchPlan,
    TranslationResultReplaceOperation? operation,
    Object? loadError,
    bool clearLoadError = false,
    bool? showSkippedOnly,
    Set<String>? skippedOriginalPaths,
    Set<String>? protectedOriginalPaths,
  }) {
    return TranslationResultReplaceState(
      batchPlan: batchPlan ?? this.batchPlan,
      operation: operation ?? this.operation,
      loadError: clearLoadError ? null : loadError ?? this.loadError,
      showSkippedOnly: showSkippedOnly ?? this.showSkippedOnly,
      skippedOriginalPaths: skippedOriginalPaths ?? this.skippedOriginalPaths,
      protectedOriginalPaths:
          protectedOriginalPaths ?? this.protectedOriginalPaths,
    );
  }
}

@Riverpod(keepAlive: false)
class TranslationResultReplace extends _$TranslationResultReplace {
  late TranslationResultReplaceRequest _request;

  @override
  TranslationResultReplaceState build(TranslationResultReplaceRequest request) {
    _request = request;
    return const TranslationResultReplaceState();
  }

  /// 加载初始计划；返回 false 表示没有可替换结果。
  Future<bool?> load() async {
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.loading,
      clearLoadError: true,
    );
    try {
      final plan = await _request.onLoad();
      if (!ref.mounted) return null;
      if (plan.plans.isEmpty) {
        state = state.copyWith(
          batchPlan: plan,
          operation: TranslationResultReplaceOperation.idle,
        );
        return false;
      }
      state = _stateWithPlan(plan);
      return true;
    } catch (error) {
      if (!ref.mounted) return null;
      state = state.copyWith(
        operation: TranslationResultReplaceOperation.idle,
        loadError: error,
      );
      return null;
    }
  }

  /// 重新扫描当前弹框对应的漫画目录。
  Future<void> refresh() async {
    if (state.busy || state.batchPlan == null) return;
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.refreshing,
    );
    try {
      final plan = await _request.onRefresh();
      if (!ref.mounted) return;
      state = _stateWithPlan(plan);
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.refreshing) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  void setShowSkippedOnly(bool value) {
    if (state.busy) return;
    state = state.copyWith(showSkippedOnly: value);
  }

  void setPairSkipped(String originalPath, bool skipped) {
    if (state.busy || state.isPairProtected(originalPath)) return;
    final paths = Set<String>.from(state.skippedOriginalPaths);
    if (skipped) {
      paths.add(originalPath);
    } else {
      paths.remove(originalPath);
    }
    state = state.copyWith(skippedOriginalPaths: Set.unmodifiable(paths));
  }

  void setPlanSkipped(TranslationReplacementPlan plan, bool skipped) {
    if (state.busy || plan.hasUntranslatableContent) return;
    final paths = Set<String>.from(state.skippedOriginalPaths);
    for (final pair in plan.pairs) {
      if (skipped) {
        paths.add(pair.originalPath);
      } else {
        paths.remove(pair.originalPath);
      }
    }
    state = state.copyWith(skippedOriginalPaths: Set.unmodifiable(paths));
  }

  /// 删除拒译页面结果，并在弹框内重新扫描。
  Future<
    ({TranslationUntranslatableCleanupSummary summary, Object? refreshError})?
  >
  removeUntranslatableResults() async {
    final plan = state.batchPlan;
    if (state.busy || plan == null || state.untranslatablePairCount == 0) {
      return null;
    }
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.cleaning,
    );
    try {
      final summary = await _request.replacer.removeUntranslatableResultsBatch(
        plan,
      );
      TranslationReplacementBatchPlan? refreshedPlan;
      Object? refreshError;
      try {
        refreshedPlan = await _request.onRefresh();
      } catch (error) {
        refreshError = error;
      }
      if (ref.mounted && refreshedPlan != null) {
        state = _stateWithPlan(refreshedPlan);
      }
      if (!ref.mounted) return null;
      return (summary: summary, refreshError: refreshError);
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.cleaning) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  /// 批量替换原图。
  Future<TranslationReplacementBatchSummary?> replaceOriginals() async {
    final plan = state.batchPlan;
    if (state.busy || plan == null || plan.pairCount == 0) return null;
    state = state.copyWith(
      operation: TranslationResultReplaceOperation.replacing,
    );
    try {
      return await _request.replacer.applyBatch(
        plan,
        skippedOriginalPaths: state.skippedOriginalPaths,
      );
    } finally {
      if (ref.mounted &&
          state.operation == TranslationResultReplaceOperation.replacing) {
        state = state.copyWith(
          operation: TranslationResultReplaceOperation.idle,
        );
      }
    }
  }

  TranslationResultReplaceState _stateWithPlan(
    TranslationReplacementBatchPlan plan,
  ) {
    final skipped = <String>{};
    final protected = <String>{};
    for (final item in plan.plans) {
      skipped.addAll(item.defaultSkippedOriginalPaths);
      if (item.hasUntranslatableContent) {
        protected.addAll(item.pairs.map((pair) => pair.originalPath));
      }
    }
    skipped.addAll(protected);
    return state.copyWith(
      batchPlan: plan,
      operation: TranslationResultReplaceOperation.idle,
      clearLoadError: true,
      skippedOriginalPaths: Set.unmodifiable(skipped),
      protectedOriginalPaths: Set.unmodifiable(protected),
    );
  }
}

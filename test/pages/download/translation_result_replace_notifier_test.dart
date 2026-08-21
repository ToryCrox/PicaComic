import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/pages/download/translation_result_replace_notifier.dart';
import 'package:pica_comic/pages/download/translation_result_replacer.dart';

void main() {
  test('加载计划后初始化默认跳过和整本保护状态', () async {
    final replacer = _FakeReplacer();
    final plan = _batchPlan([
      _plan('/comic/normal', defaultSkipped: true),
      _plan('/comic/protected', protected: true),
    ]);
    final harness = _createHarness(
      replacer: replacer,
      load: () async => plan,
      refresh: () async => plan,
    );
    addTearDown(harness.container.dispose);

    final provider = translationResultReplaceProvider(harness.request);
    final result = await harness.container.read(provider.notifier).load();
    final state = harness.container.read(provider);

    expect(result, isTrue);
    expect(state.operation, TranslationResultReplaceOperation.idle);
    expect(state.skippedPairCount, 2);
    expect(state.protectedPairCount, 1);
    expect(state.untranslatablePairCount, 1);
    expect(state.replacementCount, 0);
  });

  test('刷新失败后恢复 idle 并保留原计划', () async {
    final replacer = _FakeReplacer();
    final plan = _batchPlan([_plan('/comic/normal')]);
    final harness = _createHarness(
      replacer: replacer,
      load: () async => plan,
      refresh: () async => throw StateError('刷新失败'),
    );
    addTearDown(harness.container.dispose);
    final provider = translationResultReplaceProvider(harness.request);
    final notifier = harness.container.read(provider.notifier);
    await notifier.load();

    await expectLater(notifier.refresh(), throwsStateError);
    final state = harness.container.read(provider);
    expect(state.operation, TranslationResultReplaceOperation.idle);
    expect(state.batchPlan, same(plan));
  });

  test('可以切换单图和整本跳过状态', () async {
    final replacer = _FakeReplacer();
    final plan = _plan('/comic/normal');
    final batchPlan = _batchPlan([plan]);
    final harness = _createHarness(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => batchPlan,
    );
    addTearDown(harness.container.dispose);
    final provider = translationResultReplaceProvider(harness.request);
    final notifier = harness.container.read(provider.notifier);
    await notifier.load();

    notifier.setPairSkipped('/comic/normal/1.webp', true);
    expect(harness.container.read(provider).replacementCount, 0);
    notifier.setPairSkipped('/comic/normal/1.webp', false);
    notifier.setPlanSkipped(plan, true);
    expect(harness.container.read(provider).isPlanFullySkipped(plan), isTrue);
  });

  test('可以独立切换目录折叠状态并在刷新后保留', () async {
    final replacer = _FakeReplacer();
    final plan = _plan('/comic/normal');
    final batchPlan = _batchPlan([plan]);
    final harness = _createHarness(
      replacer: replacer,
      load: () async => batchPlan,
      refresh: () async => batchPlan,
    );
    addTearDown(harness.container.dispose);
    final provider = translationResultReplaceProvider(harness.request);
    final notifier = harness.container.read(provider.notifier);
    await notifier.load();

    expect(harness.container.read(provider).isPlanCollapsed(plan), isFalse);
    notifier.togglePlanCollapsed(plan);
    expect(harness.container.read(provider).isPlanCollapsed(plan), isTrue);
    await notifier.refresh();
    expect(harness.container.read(provider).isPlanCollapsed(plan), isTrue);
    notifier.togglePlanCollapsed(plan);
    expect(harness.container.read(provider).isPlanCollapsed(plan), isFalse);
  });

  test('替换异常后恢复 idle', () async {
    final replacer = _FakeReplacer()..applyError = StateError('替换失败');
    final plan = _batchPlan([_plan('/comic/normal')]);
    final harness = _createHarness(
      replacer: replacer,
      load: () async => plan,
      refresh: () async => plan,
    );
    addTearDown(harness.container.dispose);
    final provider = translationResultReplaceProvider(harness.request);
    final notifier = harness.container.read(provider.notifier);
    await notifier.load();

    await expectLater(notifier.replaceOriginals(), throwsStateError);
    expect(
      harness.container.read(provider).operation,
      TranslationResultReplaceOperation.idle,
    );
  });
}

({ProviderContainer container, TranslationResultReplaceRequest request})
_createHarness({
  required _FakeReplacer replacer,
  required Future<TranslationReplacementBatchPlan> Function() load,
  required Future<TranslationReplacementBatchPlan> Function() refresh,
}) {
  final request = TranslationResultReplaceRequest(
    onLoad: load,
    onRefresh: refresh,
    replacer: replacer,
  );
  final container = ProviderContainer();
  container.listen(translationResultReplaceProvider(request), (_, _) {});
  return (container: container, request: request);
}

TranslationReplacementBatchPlan _batchPlan(
  List<TranslationReplacementPlan> plans,
) {
  return TranslationReplacementBatchPlan(
    selectedCount: plans.length,
    plans: plans,
  );
}

TranslationReplacementPlan _plan(
  String directory, {
  bool defaultSkipped = false,
  bool protected = false,
}) {
  final originalPath = '$directory/1.webp';
  final pair = TranslationReplacementPair(
    originalPath: originalPath,
    translatedPath: '$directory/result/1.png',
    originalSize: 100,
    translatedSize: 100,
    defaultSkipped: defaultSkipped,
    defaultSkipReason: defaultSkipped ? '默认跳过' : null,
    hasUntranslatableContent: protected,
  );
  return TranslationReplacementPlan(
    comicDirectory: directory,
    resultDirectories: {'$directory/result'},
    pairs: [pair],
    unmatched: const [],
    untranslatableOriginalPaths: protected
        ? <String>{originalPath}
        : const <String>{},
  );
}

class _FakeReplacer extends TranslationResultReplacer {
  Object? applyError;

  @override
  Future<TranslationReplacementBatchSummary> applyBatch(
    TranslationReplacementBatchPlan batchPlan, {
    Set<String> skippedOriginalPaths = const <String>{},
  }) async {
    final error = applyError;
    if (error != null) throw error;
    return TranslationReplacementBatchSummary(
      selectedCount: batchPlan.selectedCount,
      items: [
        for (final plan in batchPlan.plans)
          TranslationReplacementBatchItemSummary(
            plan: plan,
            summary: TranslationReplacementSummary(
              results: [TranslationReplacementResult(pair: plan.pairs.single)],
              intermediateDirectoriesCleaned: true,
            ),
          ),
      ],
    );
  }
}

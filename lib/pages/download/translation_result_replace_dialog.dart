import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/hover_scale_card.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/network_artifact_preview.dart';
import 'package:pica_comic/pages/local_image_viewer_page.dart';

import 'translation_result_replace_notifier.dart';
import 'translation_result_replacer.dart';

/// 预览并确认应用外部翻译工具生成的图片。
class TranslationResultReplaceDialog extends ConsumerStatefulWidget {
  const TranslationResultReplaceDialog({
    super.key,
    required this.comics,
    required this.translationResultRootDirectory,
    required this.onComplete,
    this.scanLegacyResultDirectories = false,
    this.request,
  });

  final List<DownloadedItem> comics;
  final String translationResultRootDirectory;
  final VoidCallback onComplete;
  final bool scanLegacyResultDirectories;
  final TranslationResultReplaceRequest? request;

  /// 打开单本或批量翻译结果预览弹框。
  static Future<bool?> show(
    BuildContext context, {
    required List<DownloadedItem> comics,
    required String translationResultRootDirectory,
    required VoidCallback onComplete,
    bool scanLegacyResultDirectories = false,
  }) {
    final selectedComics = List<DownloadedItem>.unmodifiable(comics);
    final replacer = TranslationResultReplacer();
    final request = TranslationResultReplaceRequest(
      replacer: replacer,
      onLoad: () => replacer.prepareBatch(
        selectedComics.map((comic) => comic.directoryPath),
        translationResultRootDirectory: translationResultRootDirectory,
        scanLegacyResultDirectories: scanLegacyResultDirectories,
      ),
      onRefresh: () => replacer.prepareBatch(
        selectedComics.map((comic) => comic.directoryPath),
        translationResultRootDirectory: translationResultRootDirectory,
        scanLegacyResultDirectories: scanLegacyResultDirectories,
      ),
    );
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => TranslationResultReplaceDialog(
        comics: selectedComics,
        translationResultRootDirectory: translationResultRootDirectory,
        onComplete: onComplete,
        scanLegacyResultDirectories: scanLegacyResultDirectories,
        request: request,
      ),
    );
  }

  @override
  ConsumerState<TranslationResultReplaceDialog> createState() =>
      _TranslationResultReplaceDialogState();
}

class _TranslationResultReplaceDialogState
    extends ConsumerState<TranslationResultReplaceDialog> {
  static const _dialogInset = EdgeInsets.symmetric(
    horizontal: 48,
    vertical: 24,
  );
  static const _gridMaxCrossAxisExtent = 460.0;
  static const _gridSpacing = 8.0;

  late final TranslationResultReplaceRequest _request;

  TranslationResultReplaceProvider get _provider =>
      translationResultReplaceProvider(_request);

  @override
  void initState() {
    super.initState();
    _request = widget.request ?? _createRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPlan();
    });
  }

  TranslationResultReplaceRequest _createRequest() {
    final replacer = TranslationResultReplacer();
    return TranslationResultReplaceRequest(
      replacer: replacer,
      onLoad: () => replacer.prepareBatch(
        widget.comics.map((comic) => comic.directoryPath),
        translationResultRootDirectory: widget.translationResultRootDirectory,
        scanLegacyResultDirectories: widget.scanLegacyResultDirectories,
      ),
      onRefresh: () => replacer.prepareBatch(
        widget.comics.map((comic) => comic.directoryPath),
        translationResultRootDirectory: widget.translationResultRootDirectory,
        scanLegacyResultDirectories: widget.scanLegacyResultDirectories,
      ),
    );
  }

  Future<void> _loadPlan() async {
    final result = await ref.read(_provider.notifier).load();
    if (!mounted || result != false) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _refreshPlan() async {
    if (ref.read(_provider).busy) return;
    try {
      await ref.read(_provider.notifier).refresh();
      if (mounted) showToast(message: '翻译结果预览已刷新');
    } catch (error) {
      if (mounted) showToast(message: '刷新翻译结果失败：$error');
    }
  }

  Future<bool> _confirmRemoveUntranslatableResults() async {
    final count = ref.read(_provider).untranslatablePairCount;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除拒译结果？'),
        content: Text(
          '将删除 $count 个拒译页面的输出图片、翻译 JSON 和 inpainted 图片。'
          '\n\n原图不会被删除；如果外部结果目录存在 translation_map.json，'
          '只会移除已删除译图对应的映射记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _removeUntranslatableResults() async {
    final state = ref.read(_provider);
    if (state.busy || state.untranslatablePairCount == 0) return;
    final oldPlan = state.batchPlan;
    if (oldPlan == null || !await _confirmRemoveUntranslatableResults()) return;

    try {
      final outcome = await ref
          .read(_provider.notifier)
          .removeUntranslatableResults();
      if (!mounted || outcome == null) return;
      for (final plan in oldPlan.plans) {
        for (final pair in plan.pairs.where(
          (pair) => pair.hasUntranslatableContent,
        )) {
          await FileImage(File(pair.translatedPath)).evict();
        }
      }
      final summary = outcome.summary;
      final refreshText = outcome.refreshError == null
          ? ''
          : '，刷新失败：${outcome.refreshError}';
      showToast(
        message:
            '已清理 ${summary.deletedPairCount} 个拒译页面、'
            '${summary.deletedFileCount} 个文件，'
            '移除 ${summary.removedTranslationMapEntryCount} 条映射'
            '${summary.failureCount == 0 ? '' : '，失败 ${summary.failureCount} 项'}'
            '$refreshText',
      );
    } catch (error) {
      if (mounted) showToast(message: '清理拒译结果失败：$error');
    }
  }

  Future<void> _replaceOriginals() async {
    final state = ref.read(_provider);
    final batchPlan = state.batchPlan;
    if (state.busy || batchPlan == null || batchPlan.pairCount == 0) return;
    final skippedOriginalPaths = state.skippedOriginalPaths;

    try {
      final summary = await ref.read(_provider.notifier).replaceOriginals();
      if (!mounted || summary == null) return;
      await _evictAppliedImages(summary, skippedOriginalPaths);
      await _updateComicStatuses(summary);
      widget.onComplete();

      final failureText = summary.failureCount == 0
          ? ''
          : '，${summary.failureCount} 张替换失败';
      final manuallySkippedCount =
          (summary.skippedCount - summary.protectedPairCount).clamp(0, 1 << 30);
      final skippedText = manuallySkippedCount == 0
          ? ''
          : '，跳过 $manuallySkippedCount 张';
      final protectedText = summary.protectedPairCount == 0
          ? ''
          : '，保护跳过 ${summary.protectedPairCount} 张';
      final failedPlanText = summary.failedPlanCount == 0
          ? ''
          : '，${summary.failedPlanCount} 个目录处理失败';
      final cleanedText = summary.cleanedPlanCount == 0
          ? ''
          : '，清理 ${summary.cleanedPlanCount} 个结果目录';
      showToast(
        message:
            '已替换 ${summary.successCount} 张图片$failureText'
            '$failedPlanText$skippedText$protectedText$cleanedText',
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showToast(message: '批量替换失败：$error');
    }
  }

  Future<void> _evictAppliedImages(
    TranslationReplacementBatchSummary summary,
    Set<String> skippedOriginalPaths,
  ) async {
    for (final item in summary.items) {
      final itemSummary = item.summary;
      if (itemSummary == null) continue;
      for (final result in itemSummary.results.where(
        (result) => result.isSuccess,
      )) {
        final pair = result.pair;
        await FileImage(File(pair.originalPath)).evict();
        await FileImage(File(pair.translatedPath)).evict();
        await FileImage(File(pair.destinationPath)).evict();
      }
      for (final pair in item.plan.pairs.where(
        (pair) => skippedOriginalPaths.contains(pair.originalPath),
      )) {
        await FileImage(File(pair.translatedPath)).evict();
      }
    }
  }

  Future<void> _updateComicStatuses(
    TranslationReplacementBatchSummary summary,
  ) async {
    for (final item in summary.items) {
      final comic = _comicForDirectory(item.plan.comicDirectory);
      if (comic == null) continue;
      if (item.summary == null) {
        await downloadManager.clearAiTranslationCompleted(comic.id);
        continue;
      }
      final itemSummary = item.summary!;
      if (itemSummary.protectedByUntranslatableContent) continue;
      await downloadManager.updateComicSize(comic);
      if (itemSummary.failureCount > 0 || itemSummary.successCount == 0) {
        await downloadManager.clearAiTranslationCompleted(comic.id);
      } else {
        await downloadManager.markAiTranslationCompleted(comic.id);
      }
    }
  }

  DownloadedItem? _comicForDirectory(String directory) {
    for (final comic in widget.comics) {
      if (path.equals(comic.directoryPath, directory)) return comic;
    }
    return null;
  }

  void _close() {
    if (!ref.read(_provider).operationBusy) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final batchPlan = state.batchPlan;
    return PopScope(
      canPop: !state.operationBusy,
      child: Dialog(
        insetPadding: _dialogInset,
        constraints: const BoxConstraints.expand(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(state, batchPlan),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: _buildContent(state),
              ),
            ),
            _buildFooter(state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    TranslationResultReplaceState state,
    TranslationReplacementBatchPlan? batchPlan,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              batchPlan == null
                  ? '翻译结果预览'
                  : '翻译结果预览（${batchPlan.plans.length} 个目录）',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (batchPlan != null && state.loadError == null) ...[
            FilterChip(
              mouseCursor: appClickableMouseCursor,
              label: Text('仅显示已跳过/保护 (${state.totalSkippedPairCount})'),
              selected: state.showSkippedOnly,
              visualDensity: VisualDensity.compact,
              onSelected: state.busy
                  ? null
                  : (selected) => ref
                        .read(_provider.notifier)
                        .setShowSkippedOnly(selected),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: state.busy ? null : _refreshPlan,
              icon:
                  state.operation ==
                      TranslationResultReplaceOperation.refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                state.operation == TranslationResultReplaceOperation.refreshing
                    ? '刷新中…'
                    : '刷新预览',
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: '关闭',
            onPressed: state.operationBusy ? null : _close,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(TranslationResultReplaceState state) {
    final actions = _buildActions(state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _buildFooterStatus(state)),
          const SizedBox(width: 16),
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            actions[index],
          ],
        ],
      ),
    );
  }

  Widget _buildFooterStatus(TranslationResultReplaceState state) {
    final batchPlan = state.batchPlan;
    final text = state.loadError != null
        ? '翻译结果读取失败'
        : state.operation == TranslationResultReplaceOperation.loading
        ? '正在读取翻译结果…'
        : batchPlan == null
        ? ''
        : '共 ${batchPlan.pairCount} 张 · 已跳过 ${state.totalSkippedPairCount} 张 · '
              '待替换 ${state.replacementCount} 张';
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  List<Widget> _buildActions(TranslationResultReplaceState state) {
    if (state.loadError != null) {
      return [
        FilledButton.icon(
          onPressed: state.busy ? null : _loadPlan,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ];
    }
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return const [];
    }
    return [
      if (state.untranslatablePairCount > 0)
        OutlinedButton.icon(
          onPressed: state.busy ? null : _removeUntranslatableResults,
          icon: state.operation == TranslationResultReplaceOperation.cleaning
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_sweep_outlined),
          label: Text(
            state.operation == TranslationResultReplaceOperation.cleaning
                ? '正在清理…'
                : '删除拒译结果（${state.untranslatablePairCount}）',
          ),
        ),
      FilledButton.icon(
        onPressed: state.busy ? null : _replaceOriginals,
        icon: state.operation == TranslationResultReplaceOperation.replacing
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.swap_horiz),
        label: Text(
          state.operation == TranslationResultReplaceOperation.replacing
              ? '正在替换…'
              : '替换原图（${state.replacementCount}）',
        ),
      ),
    ];
  }

  Widget _buildContent(TranslationResultReplaceState state) {
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在读取翻译结果…'),
          ],
        ),
      );
    }
    final loadError = state.loadError;
    if (loadError != null) {
      return Center(
        child: Text('读取翻译结果失败：$loadError', textAlign: TextAlign.center),
      );
    }
    final batchPlan = state.batchPlan;
    if (batchPlan == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: _buildSummaryStats(batchPlan, state),
        ),
        if (batchPlan.unmatchedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '未匹配文件不会参与替换；每个目录的翻译结果全部处理完成后，对应结果目录会被清理。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
            ),
          ),
        Expanded(
          child: state.visiblePlans.isEmpty
              ? Center(
                  child: Text(
                    state.showSkippedOnly ? '没有已跳过的图片' : '没有可显示的翻译结果',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: ScrollConfiguration.of(context).dragDevices
                        .where((kind) => kind != PointerDeviceKind.mouse)
                        .toSet(),
                  ),
                  child: CustomScrollView(
                    slivers: [
                      for (
                        var index = 0;
                        index < state.visiblePlans.length;
                        index++
                      )
                        ..._buildPlanSlivers(
                          state.visiblePlans[index],
                          state,
                          first: index == 0,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryStats(
    TranslationReplacementBatchPlan batchPlan,
    TranslationResultReplaceState state,
  ) {
    final protectedPaths = state.protectedOriginalPaths;
    final skippedCount = state.skippedOriginalPaths
        .difference(protectedPaths)
        .length;
    final protectedCount = protectedPaths.length;
    final translatedCount =
        (batchPlan.pairCount - skippedCount - protectedCount)
            .clamp(0, batchPlan.pairCount)
            .toInt();
    final theme = Theme.of(context);

    return Wrap(
      spacing: 28,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildSummaryStat(
          icon: Icons.image_outlined,
          label: '总页数',
          value: batchPlan.pairCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryStat(
          icon: Icons.check_circle_outline,
          label: '已翻译',
          value: translatedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryStat(
          icon: Icons.remove_circle_outline,
          label: '已跳过',
          value: skippedCount,
          color: Colors.orange.shade800,
        ),
        _buildSummaryStat(
          icon: Icons.shield_outlined,
          label: '已保护',
          value: protectedCount,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        _buildSummaryFileSize(batchPlan),
      ],
    );
  }

  Widget _buildSummaryStat({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(label, style: textTheme.bodyMedium),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildSummaryFileSize(TranslationReplacementBatchPlan batchPlan) {
    final delta = batchPlan.translatedTotalSize - batchPlan.originalTotalSize;
    final deltaColor = delta > 0 ? Colors.orange.shade800 : Colors.green;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.storage_outlined,
          size: 20,
          color: textTheme.bodyMedium?.color,
        ),
        const SizedBox(width: 8),
        Text('文件大小', style: textTheme.bodyMedium),
        const SizedBox(width: 8),
        Text(
          '${_formatSize(batchPlan.originalTotalSize)} → '
          '${_formatSize(batchPlan.translatedTotalSize)}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(width: 6),
        Text(
          '(${_formatDelta(delta)})',
          style: textTheme.bodySmall?.copyWith(color: deltaColor),
        ),
      ],
    );
  }

  List<Widget> _buildPlanSlivers(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state, {
    required bool first,
  }) {
    final visiblePairs = _visiblePairs(plan, state);
    final collapsed = state.isPlanCollapsed(plan);
    return [
      if (!first)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Divider(height: 1),
          ),
        ),
      SliverToBoxAdapter(child: _buildPlanHeader(plan, state)),
      SliverToBoxAdapter(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: collapsed
              ? const SizedBox.shrink()
              : _buildExpandedPlanContent(plan, visiblePairs, state),
        ),
      ),
    ];
  }

  List<TranslationReplacementPair> _visiblePairs(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    if (!state.showSkippedOnly) return plan.pairs;
    return plan.pairs
        .where(
          (pair) =>
              state.isPairSkipped(pair.originalPath) ||
              state.isPairProtected(pair.originalPath),
        )
        .toList(growable: false);
  }

  Widget _buildPlanHeader(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final directoryName = path.basename(plan.comicDirectory);
    final comic = _comicForDirectory(plan.comicDirectory);
    final title = comic?.name.trim() ?? '';
    final groupTitle = title.isEmpty ? directoryName : title;
    final visiblePairs = _visiblePairs(plan, state);
    final subtitle = state.showSkippedOnly
        ? '$directoryName · ${visiblePairs.length} 张已跳过/保护'
        : '$directoryName · ${plan.pairs.length} 张匹配'
              '${plan.unmatched.isEmpty ? '' : ' · ${plan.unmatched.length} 项未匹配'}'
              '${plan.hasUntranslatableContent ? ' · 存在无法翻译内容，本次整部插画已保护' : ''}';
    final titleColor = plan.hasUntranslatableContent
        ? Theme.of(context).colorScheme.error
        : null;
    final collapsed = state.isPlanCollapsed(plan);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              mouseCursor: appClickableMouseCursor,
              onTap: state.busy
                  ? null
                  : () =>
                        ref.read(_provider.notifier).togglePlanCollapsed(plan),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: const Icon(Icons.expand_more, size: 20),
                    ),
                    const SizedBox(width: 2),
                    _buildFolderDragHandle(plan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            groupTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(color: titleColor),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildPlanSkipControl(plan, state),
        ],
      ),
    );
  }

  Widget _buildPlanSkipControl(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final protected = plan.hasUntranslatableContent;
    final selected = protected || state.isPlanFullySkipped(plan);
    final disabled = state.busy || protected;

    void setSkipped(bool value) {
      ref.read(_provider.notifier).setPlanSkipped(plan, value);
    }

    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: disabled ? null : () => setSkipped(!selected),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled ? null : (value) => setSkipped(value == true),
            ),
            Text(protected ? '整部已保护' : '全部跳过'),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPlanContent(
    TranslationReplacementPlan plan,
    List<TranslationReplacementPair> visiblePairs,
    TranslationResultReplaceState state,
  ) {
    final children = <Widget>[];
    if (visiblePairs.isNotEmpty) {
      children.add(
        GridView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: _gridMaxCrossAxisExtent,
            crossAxisSpacing: _gridSpacing,
            mainAxisSpacing: _gridSpacing,
            childAspectRatio: 1.75,
          ),
          itemCount: visiblePairs.length,
          itemBuilder: (context, index) =>
              _buildPairCard(plan, visiblePairs[index], state),
        ),
      );
    }
    if (!state.showSkippedOnly) {
      children.addAll(
        plan.unmatched.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildUnmatchedRow(item),
          ),
        ),
      );
    }
    return Column(children: children);
  }

  Widget _buildFolderDragHandle(TranslationReplacementPlan plan) {
    final directoryName = path.basename(plan.comicDirectory);
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final directoryPath = plan.comicDirectory;
        if (directoryPath.isEmpty) return null;
        final directory = Directory(directoryPath);
        if (!await directory.exists()) return null;

        final item = DragItem(suggestedName: directoryName);
        item.add(Formats.fileUri(Uri.file(directory.path)));
        return item;
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.opaque,
        isLocationDraggable: (_) => true,
        child: Tooltip(
          message: '拖动目录',
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.folder_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPairCard(
    TranslationReplacementPlan plan,
    TranslationReplacementPair pair,
    TranslationResultReplaceState state,
  ) {
    final delta = pair.translatedSize - pair.originalSize;
    final ratio = pair.originalSize == 0 ? 0 : delta / pair.originalSize * 100;
    final deltaColor = delta > 0 ? Colors.orange : Colors.green;
    final initialIndex = plan.pairs.indexOf(pair);
    final protected = plan.hasUntranslatableContent;
    final titleColor = pair.hasUntranslatableContent
        ? Theme.of(context).colorScheme.error
        : null;
    return HoverScaleCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'P${initialIndex + 1} · ${pair.baseName}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: titleColor),
                      children: [
                        if (pair.hasUntranslatableContent)
                          TextSpan(
                            text: ' · 包含无法翻译内容',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: deltaColor),
                ),
                const SizedBox(width: 6),
                _buildPairSkipControl(pair, state, protected),
              ],
            ),
            const SizedBox(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildPreviewTile(
                      plan: plan,
                      pair: pair,
                      filePath: pair.originalPath,
                      label: '原图',
                      translated: false,
                      initialIndex: initialIndex,
                    ),
                  ),
                  SizedBox(
                    width: 16,
                    child: Center(
                      child: Icon(
                        Icons.compare_arrows,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildPreviewTile(
                      plan: plan,
                      pair: pair,
                      filePath: pair.translatedPath,
                      label: '翻译后',
                      translated: true,
                      initialIndex: initialIndex,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairSkipControl(
    TranslationReplacementPair pair,
    TranslationResultReplaceState state,
    bool isProtected,
  ) {
    final selected = isProtected || state.isPairSkipped(pair.originalPath);
    final disabled = state.busy || isProtected;

    void setSkipped(bool value) {
      ref.read(_provider.notifier).setPairSkipped(pair.originalPath, value);
    }

    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: disabled ? null : () => setSkipped(!selected),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled ? null : (value) => setSkipped(value == true),
            ),
            Text(isProtected ? '整部保护' : '跳过'),
          ],
        ),
      ),
    );
  }

  Widget _buildUnmatchedRow(TranslationUnmatchedFile item) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
        title: Text(
          '${item.isOriginal ? '原图' : '译图'}：${path.basename(item.filePath)}',
        ),
        subtitle: Text(item.reason),
      ),
    );
  }

  Widget _buildPreviewTile({
    required TranslationReplacementPlan plan,
    required TranslationReplacementPair pair,
    required String filePath,
    required String label,
    required bool translated,
    required int initialIndex,
  }) {
    final detail = translated
        ? _compactDetail(pair.translatedDimensions, pair.translatedSize)
        : _compactDetail(pair.originalDimensions, pair.originalSize);
    return InkWell(
      mouseCursor: appClickableMouseCursor,
      onTap: () =>
          _openPairViewer(plan, filePath, label, translated, initialIndex),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: label,
                style: Theme.of(context).textTheme.labelMedium,
                children: pair.defaultSkipped && translated
                    ? [
                        TextSpan(
                          text: ' · 默认跳过',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.orange.shade800),
                        ),
                      ]
                    : const [],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SizedBox.expand(
                    child: PicaImage(
                      url: Uri.file(filePath).toString(),
                      fit: BoxFit.cover,
                      memCacheWidth: networkArtifactPreviewMemCacheWidth,
                      fade: false,
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  void _openPairViewer(
    TranslationReplacementPlan plan,
    String filePath,
    String label,
    bool translated,
    int initialIndex,
  ) {
    final originalDetail = _detail(
      plan.pairs[initialIndex].originalDimensions,
      plan.pairs[initialIndex].originalSize,
    );
    final translatedDetail = _detail(
      plan.pairs[initialIndex].translatedDimensions,
      plan.pairs[initialIndex].translatedSize,
    );
    LocalImageViewerPage.open(
      context,
      imagePath: filePath,
      title: label,
      subtitle: translated ? translatedDetail : originalDetail,
      gallery: _buildGallery(plan, translated),
      initialIndex: initialIndex,
      comparison: _comparisonForPair(plan.pairs[initialIndex], initialIndex),
      bottomBuilder: (context, _, index) {
        final currentPair = plan.pairs[index];
        final protected = ref
            .read(_provider)
            .isPairProtected(currentPair.originalPath);
        var skipped = ref
            .read(_provider)
            .isPairSkipped(currentPair.originalPath);
        return StatefulBuilder(
          builder: (context, setLocalState) => _ViewerSkipControl(
            skipped: skipped,
            protected: protected,
            onChanged: (value) {
              if (protected) return;
              ref
                  .read(_provider.notifier)
                  .setPairSkipped(currentPair.originalPath, value);
              setLocalState(() => skipped = value);
            },
          ),
        );
      },
    );
  }

  List<LocalImageViewerItem> _buildGallery(
    TranslationReplacementPlan plan,
    bool translated,
  ) {
    return [
      for (var index = 0; index < plan.pairs.length; index++)
        LocalImageViewerItem(
          imagePath: translated
              ? plan.pairs[index].translatedPath
              : plan.pairs[index].originalPath,
          title: translated ? '翻译后' : '原图',
          subtitle: '${index + 1}/${plan.pairs.length}',
          comparison: _comparisonForPair(plan.pairs[index], index),
        ),
    ];
  }

  LocalImageViewerComparison _comparisonForPair(
    TranslationReplacementPair pair,
    int index,
  ) {
    final originalDetail = _detail(pair.originalDimensions, pair.originalSize);
    final translatedDetail = _detail(
      pair.translatedDimensions,
      pair.translatedSize,
    );
    return LocalImageViewerComparison(
      leftImagePath: pair.originalPath,
      rightImagePath: pair.translatedPath,
      leftTitle: '原图',
      rightTitle: '翻译后',
      leftSubtitle: 'P${index + 1}\n$originalDetail',
      rightSubtitle: 'P${index + 1}\n$translatedDetail',
    );
  }

  String _detail(TranslationImageDimensions? dimensions, int fileSize) {
    return '${dimensions?.toString() ?? '尺寸未知'}\n${_formatSize(fileSize)}';
  }

  String _compactDetail(TranslationImageDimensions? dimensions, int fileSize) {
    final dimensionText = dimensions == null
        ? '尺寸未知'
        : '${dimensions.width}×${dimensions.height}';
    return '$dimensionText · ${_formatSize(fileSize)}';
  }
}

class _ViewerSkipControl extends StatelessWidget {
  const _ViewerSkipControl({
    required this.skipped,
    required this.protected,
    required this.onChanged,
  });

  final bool skipped;
  final bool protected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            protected
                ? '当前图片：保护跳过'
                : skipped
                ? '当前图片：跳过替换'
                : '当前图片：将替换',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Checkbox(
            value: skipped,
            activeColor: Colors.orange,
            onChanged: protected ? null : (value) => onChanged(value == true),
          ),
        ],
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

String _formatDelta(int bytes) =>
    '${bytes >= 0 ? '+' : ''}${_formatSize(bytes.abs())}';

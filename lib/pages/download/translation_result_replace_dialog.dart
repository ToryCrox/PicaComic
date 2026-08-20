import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/download/download_model.dart';
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
  static const _dialogWidth = 1200.0;
  static const _dialogHeight = 800.0;
  static const _thumbnailExtent = 67.2;

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
    final size = MediaQuery.sizeOf(context);
    final width = math.min(_dialogWidth, size.width - 80);
    final height = math.min(_dialogHeight, size.height - 160);
    final batchPlan = state.batchPlan;
    return PopScope(
      canPop: !state.operationBusy,
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                batchPlan == null
                    ? '翻译结果预览'
                    : '翻译结果预览（${batchPlan.plans.length} 个目录）',
              ),
            ),
            if (batchPlan != null && state.loadError == null)
              IconButton(
                tooltip:
                    state.operation ==
                        TranslationResultReplaceOperation.refreshing
                    ? '刷新中…'
                    : '刷新预览',
                onPressed: state.busy ? null : _refreshPlan,
                icon:
                    state.operation ==
                        TranslationResultReplaceOperation.refreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
          ],
        ),
        content: SizedBox(
          width: width,
          height: height,
          child: _buildContent(state),
        ),
        actions: _buildActions(state),
      ),
    );
  }

  List<Widget> _buildActions(TranslationResultReplaceState state) {
    if (state.loadError != null) {
      return [
        TextButton(onPressed: _close, child: const Text('取消')),
        FilledButton.icon(
          onPressed: state.busy ? null : _loadPlan,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ];
    }
    if (state.operation == TranslationResultReplaceOperation.loading) {
      return [TextButton(onPressed: _close, child: const Text('取消'))];
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
      TextButton(
        onPressed: state.operationBusy ? null : _close,
        child: const Text('取消'),
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
    if (state.loadError != null) {
      return Center(
        child: Text('读取翻译结果失败：${state.loadError}', textAlign: TextAlign.center),
      );
    }
    final batchPlan = state.batchPlan;
    if (batchPlan == null) return const SizedBox.shrink();
    final delta = batchPlan.translatedTotalSize - batchPlan.originalTotalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '选中 ${batchPlan.selectedCount} 个目录，发现 ${batchPlan.plans.length} 个可替换目录；'
                '共匹配 ${batchPlan.pairCount} 张；总大小 '
                '${_formatSize(batchPlan.originalTotalSize)} → '
                '${_formatSize(batchPlan.translatedTotalSize)}（${_formatDelta(delta)}）'
                '${batchPlan.noResultCount == 0 ? '' : '；无结果 ${batchPlan.noResultCount} 个目录'}'
                '${batchPlan.unmatchedCount == 0 ? '' : '；未匹配 ${batchPlan.unmatchedCount} 项'}'
                '${state.skippedPairCount == 0 ? '' : '；已跳过 ${state.skippedPairCount} 张'}'
                '${state.protectedPairCount == 0 ? '' : '；已保护 ${state.protectedPairCount} 张'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text('仅显示已跳过/保护 (${state.totalSkippedPairCount})'),
              selected: state.showSkippedOnly,
              onSelected: state.busy
                  ? null
                  : (selected) => ref
                        .read(_provider.notifier)
                        .setShowSkippedOnly(selected),
            ),
          ],
        ),
        if (batchPlan.unmatchedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '未匹配文件不会参与替换；结果目录会在对应漫画处理完成后清理。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: state.visiblePlans.isEmpty
              ? Center(
                  child: Text(
                    state.showSkippedOnly ? '没有已跳过的图片' : '没有可显示的翻译结果',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.separated(
                  itemCount: state.visiblePlans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildPlanGroup(state.visiblePlans[index], state),
                ),
        ),
      ],
    );
  }

  Widget _buildPlanGroup(
    TranslationReplacementPlan plan,
    TranslationResultReplaceState state,
  ) {
    final directoryName = path.basename(plan.comicDirectory);
    final comic = _comicForDirectory(plan.comicDirectory);
    final title = comic?.name.trim() ?? '';
    final groupTitle = title.isEmpty ? directoryName : title;
    final visiblePairs = state.showSkippedOnly
        ? plan.pairs
              .where((pair) => state.isPairSkipped(pair.originalPath))
              .toList(growable: false)
        : plan.pairs;
    final subtitle = state.showSkippedOnly
        ? '$directoryName · ${visiblePairs.length} 张已跳过/保护'
        : '$directoryName · ${plan.pairs.length} 张匹配'
              '${plan.unmatched.isEmpty ? '' : ' · ${plan.unmatched.length} 项未匹配'}'
              '${plan.hasUntranslatableContent ? ' · 存在无法翻译内容，本次整部插画已保护' : ''}';
    final titleColor = plan.hasUntranslatableContent
        ? Theme.of(context).colorScheme.error
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(groupTitle, style: TextStyle(color: titleColor)),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(plan.hasUntranslatableContent ? '整部已保护' : '全部跳过'),
              selected:
                  plan.hasUntranslatableContent ||
                  state.isPlanFullySkipped(plan),
              onSelected: state.busy || plan.hasUntranslatableContent
                  ? null
                  : (selected) => ref
                        .read(_provider.notifier)
                        .setPlanSkipped(plan, selected),
            ),
          ],
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          for (final pair in visiblePairs) _buildPairRow(plan, pair, state),
          if (!state.showSkippedOnly)
            for (final item in plan.unmatched) _buildUnmatchedRow(item),
        ],
      ),
    );
  }

  Widget _buildPairRow(
    TranslationReplacementPlan plan,
    TranslationReplacementPair pair,
    TranslationResultReplaceState state,
  ) {
    final delta = pair.translatedSize - pair.originalSize;
    final ratio = pair.originalSize == 0 ? 0 : delta / pair.originalSize * 100;
    final deltaColor = delta > 0 ? Colors.orange : Colors.green;
    final initialIndex = plan.pairs.indexOf(pair);
    final protected = state.isPairProtected(pair.originalPath);
    final titleColor = pair.hasUntranslatableContent
        ? Theme.of(context).colorScheme.error
        : null;
    final skipped = state.isPairSkipped(pair.originalPath);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        if (pair.defaultSkipped &&
                            pair.defaultSkipReason != null)
                          TextSpan(
                            text: ' · ${pair.defaultSkipReason}',
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${_formatDelta(delta)}（${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%）',
                  style: TextStyle(color: deltaColor),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: protected || state.busy
                      ? null
                      : () => ref
                            .read(_provider.notifier)
                            .setPairSkipped(pair.originalPath, !skipped),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    protected
                        ? '保护跳过'
                        : skipped
                        ? '恢复替换'
                        : '跳过替换',
                  ),
                ),
                Checkbox(
                  value: protected || skipped,
                  onChanged: protected || state.busy
                      ? null
                      : (value) => ref
                            .read(_provider.notifier)
                            .setPairSkipped(pair.originalPath, value == true),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _preview(
                    plan,
                    pair.originalPath,
                    '原图',
                    _detail(pair.originalDimensions, pair.originalSize),
                    translated: false,
                    initialIndex: initialIndex,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: _preview(
                    plan,
                    pair.translatedPath,
                    '翻译后',
                    _detail(pair.translatedDimensions, pair.translatedSize),
                    translated: true,
                    initialIndex: initialIndex,
                  ),
                ),
              ],
            ),
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

  Widget _preview(
    TranslationReplacementPlan plan,
    String filePath,
    String label,
    String detail, {
    required bool translated,
    required int initialIndex,
  }) {
    return InkWell(
      onTap: () => LocalImageViewerPage.open(
        context,
        imagePath: filePath,
        title: label,
        subtitle: detail,
        gallery: _buildGallery(plan, translated),
        initialIndex: initialIndex,
        comparison: _comparisonForPair(plan.pairs[initialIndex], initialIndex),
        bottomBuilder: (context, _, index) {
          final pair = plan.pairs[index];
          final protected = ref
              .read(_provider)
              .isPairProtected(pair.originalPath);
          var skipped = ref.read(_provider).isPairSkipped(pair.originalPath);
          return StatefulBuilder(
            builder: (context, setLocalState) => _ViewerSkipControl(
              skipped: skipped,
              protected: protected,
              onChanged: (value) {
                ref
                    .read(_provider.notifier)
                    .setPairSkipped(pair.originalPath, value);
                setLocalState(() => skipped = value);
              },
            ),
          );
        },
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(filePath),
              width: _thumbnailExtent,
              height: _thumbnailExtent,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.square(
                dimension: _thumbnailExtent,
                child: Icon(Icons.broken_image),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label\n$detail',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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

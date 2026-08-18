import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/local_image_viewer_page.dart';
import 'package:pica_comic/pages/download/translation_result_replacer.dart';
import 'package:pica_comic/tools/translations.dart';

/// 预览并确认应用外部翻译工具生成的图片。
class TranslationResultReplaceDialog extends StatefulWidget {
  const TranslationResultReplaceDialog({
    super.key,
    required this.comic,
    required this.translationResultRootDirectory,
    required this.onComplete,
    this.scanLegacyResultDirectories = false,
  });

  final DownloadedItem comic;
  final String translationResultRootDirectory;
  final VoidCallback onComplete;
  final bool scanLegacyResultDirectories;

  @override
  State<TranslationResultReplaceDialog> createState() =>
      _TranslationResultReplaceDialogState();
}

class _TranslationResultReplaceDialogState
    extends State<TranslationResultReplaceDialog> {
  final _replacer = TranslationResultReplacer();
  TranslationReplacementPlan? _plan;
  TranslationReplacementSummary? _summary;
  Object? _loadError;
  bool _isApplying = false;
  int _appliedSkippedPairCount = 0;
  final _skippedPairPaths = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await _replacer.prepare(
        widget.comic.directoryPath,
        translationResultRootDirectory: widget.translationResultRootDirectory,
        scanLegacyResultDirectories: widget.scanLegacyResultDirectories,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null) return;
    final activePlan = _activePlan(plan);
    final skippedPairs = plan.pairs
        .where((pair) => _skippedPairPaths.contains(pair.originalPath))
        .toList(growable: false);
    if (activePlan.pairs.isEmpty && skippedPairs.isEmpty) return;
    setState(() => _isApplying = true);
    final summary = await _replacer.apply(
      activePlan,
      skippedPairs: skippedPairs,
    );
    for (final result in summary.results.where((result) => result.isSuccess)) {
      await FileImage(File(result.pair.originalPath)).evict();
      await FileImage(File(result.pair.translatedPath)).evict();
      await FileImage(File(result.pair.destinationPath)).evict();
    }
    await downloadManager.updateComicSize(widget.comic);
    if (summary.failureCount > 0) {
      // 替换失败时不能保留“已完成”状态，避免卡片显示错误信息。
      await downloadManager.clearAiTranslationCompleted(widget.comic.id);
    } else if (summary.successCount > 0) {
      // 跳过的图片不影响完成标记；只要实际替换的图片全部成功即可。
      await downloadManager.markAiTranslationCompleted(widget.comic.id);
    }
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _appliedSkippedPairCount = skippedPairs.length;
      _isApplying = false;
    });
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final contentWidth = screenSize.width * 0.92 > 1200
        ? 1200.0
        : screenSize.width * 0.92;
    final contentHeight = (screenSize.height - 220)
        .clamp(360.0, 760.0)
        .toDouble();
    final plan = _plan;
    final activePairCount = plan == null ? 0 : _activePairs(plan).length;
    final skippedPairCount = plan == null
        ? 0
        : plan.pairs.length - activePairCount;
    return AlertDialog(
      title: Text('应用翻译结果'.tl),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: _buildContent(context, plan),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying ? null : () => Navigator.pop(context),
          child: Text(_summary == null ? '取消'.tl : '关闭'.tl),
        ),
        if (_summary == null)
          FilledButton(
            onPressed:
                plan == null ||
                    (activePairCount == 0 && skippedPairCount == 0) ||
                    _isApplying
                ? null
                : _apply,
            child: Text(
              _isApplying
                  ? '处理中'.tl
                  : activePairCount > 0
                  ? '替换原图 ($activePairCount)'.tl
                  : '清理跳过结果 ($skippedPairCount)'.tl,
            ),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, TranslationReplacementPlan? plan) {
    if (_loadError != null) {
      return Center(child: Text('读取翻译结果失败：$_loadError'));
    }
    if (plan == null) return const Center(child: CircularProgressIndicator());
    if (_summary case final summary?) return _buildSummary(context, summary);
    if (plan.pairs.isEmpty) {
      return const Center(child: Text('没有可应用的翻译图片'));
    }
    final activePairs = _activePairs(plan);
    final skippedCount = plan.pairs.length - activePairs.length;
    final originalTotalSize = activePairs.fold(
      0,
      (total, pair) => total + pair.originalSize,
    );
    final translatedTotalSize = activePairs.fold(
      0,
      (total, pair) => total + pair.translatedSize,
    );
    final delta = translatedTotalSize - originalTotalSize;
    final originalPaths = plan.pairs
        .map((pair) => pair.originalPath)
        .toList(growable: false);
    final translatedPaths = plan.pairs
        .map((pair) => pair.translatedPath)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '将替换 ${activePairs.length} 张图片，扫描到 ${plan.resultDirectories.length} 个翻译结果目录。',
        ),
        if (skippedCount > 0) Text('已跳过 $skippedCount 张图片，可在列表中恢复。'),
        const SizedBox(height: 4),
        Text(
          '总文件大小：${_formatSize(originalTotalSize)} → ${_formatSize(translatedTotalSize)}（${_formatDelta(delta)}）',
          style: TextStyle(color: delta > 0 ? Colors.orange : Colors.green),
        ),
        if (plan.unmatched.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${plan.unmatched.length} 个文件未匹配；未匹配译图会保留中间目录，未匹配原图会被视为无需翻译。',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: plan.pairs.length + (plan.unmatched.isEmpty ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              if (index == plan.pairs.length) {
                return _UnmatchedCard(files: plan.unmatched);
              }
              final pair = plan.pairs[index];
              return _PairCard(
                pair: pair,
                skipped: _skippedPairPaths.contains(pair.originalPath),
                onToggleSkipped: () => _toggleSkipped(pair.originalPath),
                onShowSkipMenu: (position) => _showSkipMenu(
                  context: context,
                  position: position,
                  pairIndex: index,
                ),
                originalPaths: originalPaths,
                translatedPaths: translatedPaths,
                pairIndex: index,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(
    BuildContext context,
    TranslationReplacementSummary summary,
  ) {
    final color = summary.failureCount == 0
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            summary.failureCount == 0 ? Icons.check_circle : Icons.error,
            color: color,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            '成功替换 ${summary.successCount} 张，'
            '${_appliedSkippedPairCount > 0 ? '已删除跳过结果 $_appliedSkippedPairCount 张，' : ''}'
            '失败 ${summary.failureCount} 张。',
          ),
          const SizedBox(height: 8),
          Text(
            summary.intermediateDirectoriesCleaned
                ? '已清理翻译结果、inpainted、mask 和 manga_translator_work 中间目录。'
                : '保留中间目录，方便继续处理未匹配译图或替换失败的图片。',
            textAlign: TextAlign.center,
          ),
          if (summary.failureCount > 0) ...[
            const SizedBox(height: 16),
            ...summary.results
                .where((result) => !result.isSuccess)
                .map(
                  (result) => Text(
                    '${result.pair.baseName}: ${result.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  List<TranslationReplacementPair> _activePairs(
    TranslationReplacementPlan plan,
  ) {
    return plan.pairs
        .where((pair) => !_skippedPairPaths.contains(pair.originalPath))
        .toList(growable: false);
  }

  TranslationReplacementPlan _activePlan(TranslationReplacementPlan plan) {
    return TranslationReplacementPlan(
      comicDirectory: plan.comicDirectory,
      resultDirectories: plan.resultDirectories,
      pairs: _activePairs(plan),
      unmatched: plan.unmatched,
    );
  }

  void _toggleSkipped(String originalPath) {
    setState(() {
      if (!_skippedPairPaths.add(originalPath)) {
        _skippedPairPaths.remove(originalPath);
      }
    });
  }

  Future<void> _showSkipMenu({
    required BuildContext context,
    required Offset position,
    required int pairIndex,
  }) async {
    final action = await showMenu<_SkipMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _SkipMenuAction.skipFromHere,
          child: Text('跳过此图片及之后的所有图片'),
        ),
      ],
    );
    if (action != _SkipMenuAction.skipFromHere || !mounted) return;
    final plan = _plan;
    if (plan == null) return;
    setState(() {
      for (final pair in plan.pairs.skip(pairIndex)) {
        _skippedPairPaths.add(pair.originalPath);
      }
    });
  }
}

enum _SkipMenuAction { skipFromHere }

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.pair,
    required this.skipped,
    required this.onToggleSkipped,
    required this.onShowSkipMenu,
    required this.originalPaths,
    required this.translatedPaths,
    required this.pairIndex,
  });

  final TranslationReplacementPair pair;
  final bool skipped;
  final VoidCallback onToggleSkipped;
  final ValueChanged<Offset> onShowSkipMenu;
  final List<String> originalPaths;
  final List<String> translatedPaths;
  final int pairIndex;

  @override
  Widget build(BuildContext context) {
    final delta = pair.translatedSize - pair.originalSize;
    return Card(
      margin: EdgeInsets.zero,
      color: skipped
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pair.baseName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '文件大小变化：${_formatDelta(delta)}',
                  style: TextStyle(
                    color: delta > 0 ? Colors.orange : Colors.green,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onSecondaryTapUp: (details) =>
                      onShowSkipMenu(details.globalPosition),
                  child: TextButton.icon(
                    onPressed: onToggleSkipped,
                    icon: Icon(skipped ? Icons.restore : Icons.skip_next),
                    label: Text(skipped ? '恢复替换' : '跳过替换'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ImageInfo(
                    label: '原图',
                    path: pair.originalPath,
                    size: pair.originalSize,
                    dimensions: pair.originalDimensions,
                    previewPaths: originalPaths,
                    previewIndex: pairIndex,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: _ImageInfo(
                    label: '翻译后',
                    path: pair.translatedPath,
                    size: pair.translatedSize,
                    dimensions: pair.translatedDimensions,
                    previewPaths: translatedPaths,
                    previewIndex: pairIndex,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageInfo extends StatelessWidget {
  const _ImageInfo({
    required this.label,
    required this.path,
    required this.size,
    required this.dimensions,
    required this.previewPaths,
    required this.previewIndex,
  });

  final String label;
  final String path;
  final int size;
  final TranslationImageDimensions? dimensions;
  final List<String> previewPaths;
  final int previewIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: '点击放大',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _showImagePreview(
              context,
              filePaths: previewPaths,
              initialIndex: previewIndex,
              title: label,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(path),
                width: 76,
                height: 76,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 76,
                  height: 76,
                  child: Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(
                path.split(Platform.pathSeparator).last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(dimensions?.toString() ?? '无法读取尺寸'),
              Text(_formatSize(size)),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnmatchedCard extends StatelessWidget {
  const _UnmatchedCard({required this.files});

  final List<TranslationUnmatchedFile> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        title: Text('未匹配文件 (${files.length})'),
        children: files
            .map(
              (file) => ListTile(
                dense: true,
                title: Text(file.filePath.split(Platform.pathSeparator).last),
                subtitle: Text(
                  '${file.isOriginal ? '原图' : '译图'}：${file.reason}',
                ),
              ),
            )
            .toList(),
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

Future<void> _showImagePreview(
  BuildContext context, {
  required List<String> filePaths,
  required int initialIndex,
  required String title,
}) {
  if (filePaths.isEmpty) return Future<void>.value();
  final safeIndex = initialIndex.clamp(0, filePaths.length - 1).toInt();
  final gallery = [
    for (var index = 0; index < filePaths.length; index++)
      LocalImageViewerItem(
        imagePath: filePaths[index],
        title: title,
        subtitle:
            '${index + 1}/${filePaths.length} · '
            '${File(filePaths[index]).path.split(Platform.pathSeparator).last}',
      ),
  ];
  return LocalImageViewerPage.open<void>(
    context,
    imagePath: filePaths[safeIndex],
    gallery: gallery,
    initialIndex: safeIndex,
  );
}

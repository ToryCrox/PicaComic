import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_model.dart';
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
    final plan = _plan;
    final activePairCount = plan == null ? 0 : _activePairs(plan).length;
    final skippedPairCount = plan == null
        ? 0
        : plan.pairs.length - activePairCount;
    return AlertDialog(
      title: Text('应用翻译结果'.tl),
      content: SizedBox(
        width: 1000,
        height: 620,
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
          child: ListView(
            children: [
              for (var index = 0; index < plan.pairs.length; index++)
                _PairCard(
                  pair: plan.pairs[index],
                  skipped: _skippedPairPaths.contains(
                    plan.pairs[index].originalPath,
                  ),
                  onToggleSkipped: () =>
                      _toggleSkipped(plan.pairs[index].originalPath),
                  originalPaths: originalPaths,
                  translatedPaths: translatedPaths,
                  pairIndex: index,
                ),
              if (plan.unmatched.isNotEmpty)
                _UnmatchedCard(files: plan.unmatched),
            ],
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
}

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.pair,
    required this.skipped,
    required this.onToggleSkipped,
    required this.originalPaths,
    required this.translatedPaths,
    required this.pairIndex,
  });

  final TranslationReplacementPair pair;
  final bool skipped;
  final VoidCallback onToggleSkipped;
  final List<String> originalPaths;
  final List<String> translatedPaths;
  final int pairIndex;

  @override
  Widget build(BuildContext context) {
    final delta = pair.translatedSize - pair.originalSize;
    return Card(
      color: skipped
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                TextButton.icon(
                  onPressed: onToggleSkipped,
                  icon: Icon(skipped ? Icons.restore : Icons.skip_next),
                  label: Text(skipped ? '恢复替换' : '跳过替换'),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  padding: EdgeInsets.symmetric(horizontal: 12),
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
            const SizedBox(height: 6),
            Text(
              '文件大小变化：${_formatDelta(delta)}',
              style: TextStyle(color: delta > 0 ? Colors.orange : Colors.green),
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
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(path),
                width: 96,
                height: 96,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 96,
                  height: 96,
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
}) {
  if (filePaths.isEmpty) return Future<void>.value();
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    builder: (context) => _ImagePreviewDialog(
      filePaths: filePaths,
      initialIndex: initialIndex,
      width: size.width * 0.9,
      height: size.height * 0.9,
    ),
  );
}

class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.filePaths,
    required this.initialIndex,
    required this.width,
    required this.height,
  });

  final List<String> filePaths;
  final int initialIndex;
  final double width;
  final double height;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late final FocusNode _focusNode;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'translation-image-preview');
    final lastIndex = widget.filePaths.length - 1;
    _currentIndex = widget.initialIndex < 0
        ? 0
        : widget.initialIndex > lastIndex
        ? lastIndex
        : widget.initialIndex;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.filePaths[_currentIndex];
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowLeft:
            case LogicalKeyboardKey.arrowUp:
              _move(-1);
              return KeyEventResult.handled;
            case LogicalKeyboardKey.arrowRight:
            case LogicalKeyboardKey.arrowDown:
              _move(1);
              return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            children: [
              PhotoView(
                key: ValueKey(filePath),
                imageProvider: FileImage(File(filePath)),
                minScale: PhotoViewComputedScale.contained,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                loadingBuilder: (_, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, _, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    onPressed: _currentIndex > 0 ? () => _move(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '上一张'.tl,
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    onPressed: _currentIndex < widget.filePaths.length - 1
                        ? () => _move(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '下一张'.tl,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭'.tl,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        '${_currentIndex + 1}/${widget.filePaths.length}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _move(int offset) {
    final nextIndex = _currentIndex + offset;
    if (nextIndex < 0 || nextIndex >= widget.filePaths.length) {
      _focusNode.requestFocus();
      return;
    }
    setState(() => _currentIndex = nextIndex);
    _focusNode.requestFocus();
  }
}

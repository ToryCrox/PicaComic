import 'dart:io';

import 'package:flutter/material.dart';
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
    required this.onComplete,
  });

  final DownloadedItem comic;
  final VoidCallback onComplete;

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

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await _replacer.prepare(widget.comic.directoryPath);
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || plan.pairs.isEmpty) return;
    setState(() => _isApplying = true);
    final summary = await _replacer.apply(plan);
    for (final result in summary.results.where((result) => result.isSuccess)) {
      await FileImage(File(result.pair.originalPath)).evict();
      await FileImage(File(result.pair.translatedPath)).evict();
      await FileImage(File(result.pair.destinationPath)).evict();
    }
    await downloadManager.updateComicSize(widget.comic);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _isApplying = false;
    });
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
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
            onPressed: plan == null || plan.pairs.isEmpty || _isApplying
                ? null
                : _apply,
            child: Text(
              _isApplying ? '处理中'.tl : '替换原图 (${plan?.pairs.length ?? 0})'.tl,
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
    final delta = plan.translatedTotalSize - plan.originalTotalSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '将替换 ${plan.pairs.length} 张图片，扫描到 ${plan.resultDirectories.length} 个 result 目录。',
        ),
        const SizedBox(height: 4),
        Text(
          '总文件大小：${_formatSize(plan.originalTotalSize)} → ${_formatSize(plan.translatedTotalSize)}（${_formatDelta(delta)}）',
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
              ...plan.pairs.map((pair) => _PairCard(pair: pair)),
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
          Text('成功替换 ${summary.successCount} 张，失败 ${summary.failureCount} 张。'),
          const SizedBox(height: 8),
          Text(
            summary.intermediateDirectoriesCleaned
                ? '已清理 result、inpainted 和 mask 中间目录。'
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
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair});

  final TranslationReplacementPair pair;

  @override
  Widget build(BuildContext context) {
    final delta = pair.translatedSize - pair.originalSize;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pair.baseName, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ImageInfo(
                    label: '原图',
                    path: pair.originalPath,
                    size: pair.originalSize,
                    dimensions: pair.originalDimensions,
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
  });

  final String label;
  final String path;
  final int size;
  final TranslationImageDimensions? dimensions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: '点击放大',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _showImagePreview(context, path),
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

Future<void> _showImagePreview(BuildContext context, String filePath) {
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: size.width * 0.9,
        height: size.height * 0.9,
        child: Stack(
          children: [
            PhotoView(
              imageProvider: FileImage(File(filePath)),
              minScale: PhotoViewComputedScale.contained,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              loadingBuilder: (_, _) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _, _) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white, size: 48),
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
          ],
        ),
      ),
    ),
  );
}

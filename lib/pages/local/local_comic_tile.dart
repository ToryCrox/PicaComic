import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:signals/signals_flutter.dart';
import 'dart:io';
import 'local_comic_page.dart';
import '../reader/comic_reading_page.dart';

import 'package:pica_comic/foundation/file_utils.dart';
import '../../tools/image_utils.dart';
import 'package:pica_comic/tools/time.dart';

class LocalComicTile extends StatefulWidget {
  final LocalComicModel model;
  final VoidCallback onReload;
  final List<String> allDirPaths;
  final Future<void> Function(Map<String, dynamic>? history) onTap;
  final void Function(TapDownDetails details)? onSecondaryTap;
  final VoidCallback? onLongPress;
  final Map<String, dynamic>? initialHistory;

  const LocalComicTile({
    super.key,
    required this.model,
    required this.onReload,
    this.allDirPaths = const [],
    required this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.initialHistory,
  });

  @override
  State<LocalComicTile> createState() => _LocalComicTileState();
}

class _LocalComicTileState extends State<LocalComicTile> {
  // 封面路径
  String? _coverPath;

  TapDownDetails? _tapDownDetails;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant LocalComicTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _loadData();
    }
  }

  // 加载显示所需数据
  Future<void> _loadData() async {
    _coverPath = widget.model.cover;

    // 如果没有预设封面，则尝试异步加载
    String? coverPath = widget.model.cover;
    if (coverPath.isEmpty) {
      coverPath = await _getCoverImage(widget.model.path);
      if (mounted) {
        setState(() {
          _coverPath = coverPath;
        });
      }
    }
  }

  Future<String> _getCoverImage(String directory) async {
    final dir = Directory(directory);
    try {
      if (!dir.existsSync()) return '';
      final file = await dir.list(recursive: true).firstWhere(predictImageFile);
      Log.d('cover path: ${file.path}');
      return file.path;
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    //if (_loading) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final historyMap = LocalHistoryManager()
              .findInCache(widget.model.path)
              ?.toMap();
          await widget.onTap(historyMap);
          _loadData();
        },
        onSecondaryTapDown: (details) => _tapDownDetails = details,
        onSecondaryTap: () {
          if (_tapDownDetails != null) {
            widget.onSecondaryTap?.call(_tapDownDetails!);
          }
        },
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCover(colorScheme),
                    _buildFavoriteButton(),
                    _buildReadButton(colorScheme),
                    _buildFolderButton(colorScheme),
                    // _buildProgressBar(colorScheme), // Move out of cover stack
                  ],
                ),
              ),
              _buildTitle(),
              _buildProgressBar(colorScheme), // Move to here
            ],
          ),
        ),
      ),
    );
  }

  // 构建封面
  Widget _buildCover(ColorScheme colorScheme) {
    if (_coverPath != null && _coverPath!.isNotEmpty) {
      return Image.file(
        File(_coverPath!),
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (context, error, stackTrace) =>
            _buildFolderIcon(colorScheme),
      );
    }
    return _buildFolderIcon(colorScheme);
  }

  Widget _buildFolderIcon(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.folder, size: 48, color: colorScheme.onSurfaceVariant),
    );
  }

  // 构建收藏按钮
  Widget _buildFavoriteButton() {
    return Positioned(
      top: 4,
      right: 4,
      child: Material(
        color: Colors.transparent,
        child: Watch.builder(
          builder: (context) {
            final favorite = downloadManager.findLocalFavoriteInCache(
              widget.model.path,
            );
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                if (favorite != null) {
                  await downloadManager.deleteLocalFavorite(widget.model.path);
                } else {
                  await downloadManager.addLocalFavorite(widget.model.path);
                }
                widget.onReload();
              },
              onLongPress: () {
                if (favorite != null) {
                  _showWeightDialog(favorite.sortOrder.toDouble());
                }
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  favorite != null ? Icons.bookmark : Icons.bookmark_border,
                  color: favorite != null ? Colors.orange : Colors.white,
                  size: 20,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 构建阅读按钮
  Widget _buildReadButton(ColorScheme colorScheme) {
    return Positioned(
      right: 4,
      bottom: 4,
      child: Watch.builder(
        builder: (context) {
          final history = LocalHistoryManager().findInCache(widget.model.path);

          Widget child;
          if (history != null && history.time > 0) {
            final time = DateTime.fromMillisecondsSinceEpoch(history.time);
            child = Text(
              time.toCompareString,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            );
          } else {
            child = Icon(
              Icons.menu_book,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            );
          }

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _read,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  // 构建文件夹按钮
  Widget _buildFolderButton(ColorScheme colorScheme) {
    return Positioned(
      left: 4,
      bottom: 4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => FileUtils.openFileOrDirectory(widget.model.path),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // 构建进度条
  Widget _buildProgressBar(ColorScheme colorScheme) {
    return Watch.builder(
      builder: (context) {
        final history = LocalHistoryManager().findInCache(widget.model.path);
        if (history == null) return const SizedBox(height: 3);

        final pageIndex = history.pageIndex;
        final totalPages = history.totalPages;
        double value = 0.0;
        if (totalPages > 0) {
          value = (pageIndex / totalPages).clamp(0.0, 1.0);
        }

        return LinearProgressIndicator(
          value: value,
          backgroundColor: colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          minHeight: 3,
        );
      },
    );
  }

  // 构建标题
  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        widget.model.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  // 开始阅读
  void _read() {
    final history = LocalHistoryManager().findInCache(widget.model.path);
    final initIndex = history?.pageIndex ?? 1;
    final isReversed = history?.isReversed == 1;
    App.globalTo(
      () => ComicReadingPage.localComic(
        widget.model.path,
        widget.model.title,
        allDirPaths: widget.allDirPaths.isEmpty
            ? [widget.model.path]
            : widget.allDirPaths,
        initialPage: initIndex,
        isReversed: isReversed,
      ),
    ).then((v) => _loadData());
  }

  void _showWeightDialog(double currentWeight) {
    showDialog(
      context: context,
      builder: (context) => _WeightDialog(
        initialValue: currentWeight,
        onChanged: (val) async {
          await downloadManager.updateLocalFavoriteSortOrder(
            widget.model.path,
            val.toInt(),
          );
          widget.onReload();
        },
      ),
    );
  }
}

class _WeightDialog extends StatefulWidget {
  final double initialValue;
  final Function(double) onChanged;
  const _WeightDialog({required this.initialValue, required this.onChanged});

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("调整收藏权重"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("权重越大越靠前: ${_value.toInt()}"),
          Slider(
            value: _value,
            min: 0,
            max: 99,
            divisions: 99,
            onChanged: (val) {
              setState(() {
                _value = val;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: () {
            widget.onChanged(_value);
            Navigator.pop(context);
          },
          child: const Text("确定"),
        ),
      ],
    );
  }
}

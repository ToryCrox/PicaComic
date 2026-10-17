import 'package:pica_comic/components/components.dart' show showToast;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:pica_comic/foundation/directory_favorites_providers.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'dart:io';
import 'local_comic_page.dart';
import '../reader/comic_reading_page.dart';

import 'package:pica_comic/foundation/file_utils.dart';
import 'package:pica_comic/tools/time.dart';

class LocalComicTile extends ConsumerStatefulWidget {
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
  ConsumerState<LocalComicTile> createState() => _LocalComicTileState();
}

class _LocalComicTileState extends ConsumerState<LocalComicTile> {
  TapDownDetails? _tapDownDetails;

  @override
  Widget build(BuildContext context) {
    //if (_loading) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: appClickableMouseCursor,
        onTap: () async {
          try {
            final history = await ref.read(
              localHistoryEntryProvider(widget.model.path).future,
            );
            if (!mounted) return;
            await widget.onTap(history?.toMap());
          } catch (error) {
            if (mounted)
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('读取进度失败: $error')));
          }
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
    final coverPath = widget.model.cover.isNotEmpty
        ? widget.model.cover
        : ref
              .watch(comicDirectoryCoverProvider(widget.model.path))
              .asData
              ?.value;
    if (coverPath != null && coverPath.isNotEmpty) {
      return Image.file(
        File(coverPath),
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
        child: Consumer(
          builder: (context, ref, _) {
            final engine = ref.read(directoryFavoritesProvider.notifier);
            final status = ref.watch(
              directoryFavoriteProvider(widget.model.path),
            );
            final favorite = status.asData?.value;
            return InkWell(
              mouseCursor: appClickableMouseCursor,
              borderRadius: BorderRadius.circular(20),
              onTap: status.isLoading
                  ? null
                  : () async {
                      try {
                        if (favorite != null) {
                          await engine.remove(widget.model.path);
                        } else {
                          await engine.add(widget.model.path);
                        }
                      } catch (error) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('收藏操作失败: $error')),
                          );
                      }
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
      child: Consumer(
        builder: (context, ref, _) {
          final lookup = ref.watch(
            localHistoryEntryProvider(widget.model.path),
          );
          if (lookup.hasError) {
            return IconButton(
              tooltip: '历史加载失败，点击重试',
              onPressed: () =>
                  ref.invalidate(localHistoryEntryProvider(widget.model.path)),
              icon: const Icon(Icons.refresh, size: 18),
            );
          }
          if (lookup.isLoading && !lookup.hasValue) {
            return const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final history = lookup.asData?.value;

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
              mouseCursor: appClickableMouseCursor,
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
          mouseCursor: appClickableMouseCursor,
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
    return Consumer(
      builder: (context, ref, _) {
        final history = ref
            .watch(localHistoryEntryProvider(widget.model.path))
            .asData
            ?.value;
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
  Future<void> _read() async {
    try {
      final history = await ref.read(
        localHistoryEntryProvider(widget.model.path).future,
      );
      if (!mounted) return;
      final initIndex = history?.pageIndex ?? 1;
      final isReversed = history?.isReversed == 1;
      await App.globalTo(
        () => ComicReadingPage.localComic(
          widget.model.path,
          widget.model.title,
          allDirPaths: widget.allDirPaths.isEmpty
              ? [widget.model.path]
              : widget.allDirPaths,
          initialPage: initIndex,
          isReversed: isReversed,
        ),
      );
    } catch (error) {
      showToast(message: '读取历史失败: $error');
    }
  }

  void _showWeightDialog(double currentWeight) {
    showDialog(
      context: context,
      builder: (context) => _WeightDialog(
        initialValue: currentWeight,
        onChanged: (val) async {
          try {
            await ref
                .read(directoryFavoritesProvider.notifier)
                .reorder(widget.model.path, val.toInt());
          } catch (error) {
            showToast(message: '保存权重失败: $error');
          }
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

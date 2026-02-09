import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'dart:io';
import 'local_comic_page.dart';
import '../reader/comic_reading_page.dart';
import 'package:pica_comic/tools/map_extension.dart';

import '../../tools/image_utils.dart';

class LocalComicTile extends StatefulWidget {
  final LocalComicModel model;
  final VoidCallback onReload;
  final List<String> allDirPaths;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTap;
  final VoidCallback? onLongPress;

  const LocalComicTile({
    super.key, 
    required this.model, 
    required this.onReload, 
    this.allDirPaths = const [],
    required this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
  });

  @override
  State<LocalComicTile> createState() => _LocalComicTileState();
}

class _LocalComicTileState extends State<LocalComicTile> {
  // ...
  // 阅读历史
  Map<String, dynamic>? _history;
  // 收藏状态
  Map<String, dynamic>? _favorite;
  // 是否正在加载
  bool _loading = true;
  // 总页数
  int _totalPages = 0;
  
  TapDownDetails? _tapDownDetails;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // 加载显示所需数据
  Future<void> _loadData() async {
    final history = await downloadManager.getLocalHistory(widget.model.path);
    final favorite = await downloadManager.getLocalFavorite(widget.model.path);
    
    int total = 0;
    try {
      final dir = Directory(widget.model.path);
      await for (var entity in dir.list(recursive: true)) {
        if (entity is File && predictImageFile(entity)) {
          total++;
        }
      }
    } catch (e) {
      // ignore
    }

    if (mounted) {
      setState(() {
        _history = history;
        _favorite = favorite;
        _totalPages = total;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    //if (_loading) return const SizedBox.shrink();
    
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
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
                    _buildProgressBar(colorScheme),
                  ],
                ),
              ),
              _buildTitle(),
            ],
          ),
        ),
      ),
    );
  }

  // 构建封面
  Widget _buildCover(ColorScheme colorScheme) {
    if (widget.model.cover.isNotEmpty) {
      return Image.file(
        File(widget.model.cover),
        fit: BoxFit.cover,
        cacheWidth: 300,
      );
    }
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
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _toggleFavorite,
          onLongPress: _showWeightDialog,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _favorite != null ? Icons.bookmark : Icons.bookmark_border,
              color: _favorite != null ? Colors.orange : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  // 构建阅读按钮
  Widget _buildReadButton(ColorScheme colorScheme) {
    return Positioned(
      right: 4,
      bottom: 4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _read,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.menu_book,
              size: 18,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }

  // 构建进度条
  Widget _buildProgressBar(ColorScheme colorScheme) {
    if (_history == null) return const SizedBox.shrink();
    
    final pageIndex = _history?.optInt('pageIndex', 1) ?? 1;
    double value = 0.0;
    if (_totalPages > 0) {
      value = (pageIndex / _totalPages).clamp(0.0, 1.0);
    }
    
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: LinearProgressIndicator(
        value: value,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
        minHeight: 4,
      ),
    );
  }

  // 构建标题
  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        widget.model.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  // 开始阅读
  void _read() {
     final initIndex = _history?.optInt('pageIndex', 1) ?? 1;
     final isReversed = _history?.optInt('isReversed') == 1;
     App.globalTo(() => ComicReadingPage.localComic(
          widget.model.path,
          widget.model.title,
          allDirPaths: widget.allDirPaths.isEmpty ? [widget.model.path] : widget.allDirPaths,
          initialPage: initIndex,
          isReversed: isReversed,
        ));
  }

  Future<void> _toggleFavorite() async {
    if (_favorite != null) {
      await downloadManager.deleteLocalFavorite(widget.model.path);
    } else {
      await downloadManager.addLocalFavorite(widget.model.path);
    }
    _loadData();
    widget.onReload();
  }

  void _showWeightDialog() {
    showDialog(
      context: context,
      builder: (context) => _WeightDialog(
        initialValue: (_favorite?['sort_order'] as int?)?.toDouble() ?? 0,
        onChanged: (val) async {
          await downloadManager.updateLocalFavoriteSortOrder(widget.model.path, val.toInt());
          _loadData();
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
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

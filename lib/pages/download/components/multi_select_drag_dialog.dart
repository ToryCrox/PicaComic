import 'dart:io';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;

class MultiSelectDragDialog extends StatefulWidget {
  final List<DownloadedItem> selectedItems;

  const MultiSelectDragDialog({super.key, required this.selectedItems});

  @override
  State<MultiSelectDragDialog> createState() => _MultiSelectDragDialogState();
}

class _MultiSelectDragDialogState extends State<MultiSelectDragDialog> {
  List<File> _allImageFiles = [];
  List<DragItem> _allDragItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllImages();
  }

  Future<void> _loadAllImages() async {
    List<File> allFiles = [];
    List<DragItem> allDragItems = [];
    int count = 0;

    for (var item in widget.selectedItems) {
      final dirPath = item.directoryPath;
      if (dirPath.isEmpty) continue;

      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      await for (var entity in dir.list(recursive: true)) {
        if (!mounted) return;
        if (entity is! File) continue;

        final fileName = Path.basename(entity.path);

        // 排除封面文件
        if (fileName == 'cover.jpg' ||
            fileName == 'cover.webp' ||
            fileName == 'cover.png') {
          continue;
        }

        // 检查是否为图片文件
        final ext = Path.extension(fileName).toLowerCase();
        if (const {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}.contains(ext)) {
          final dragItem = DragItem(suggestedName: fileName);
          dragItem.add(Formats.fileUri(Uri.file(entity.path)));
          
          allFiles.add(entity);
          allDragItems.add(dragItem);
          count++;

          // 节流刷新：每 50 个文件刷新一次 UI
          if (count % 50 == 0) {
            setState(() {
              _allImageFiles = List.from(allFiles);
              _allDragItems = List.from(allDragItems);
            });
            // 出让执行权，防止密集的微任务阻塞 UI 渲染
            await Future.delayed(Duration.zero);
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _allImageFiles = allFiles;
        _allDragItems = allDragItems;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("批量拖拽".tl),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCoverStack(),
            const SizedBox(height: 16),
            Text("已选中 ${widget.selectedItems.length} 个漫画".tl),
            const SizedBox(height: 8),
            if (_isLoading)
              Column(
                children: [
                   const LinearProgressIndicator(),
                   const SizedBox(height: 8),
                   Text("正在加载图片: ${_allImageFiles.length}".tl),
                ],
              )
            else
              Text("共加载到 ${_allImageFiles.length} 张图片".tl),
            const SizedBox(height: 16),
            if (!_isLoading && _allImageFiles.isNotEmpty)
              _buildDragSource()
            else if (!_isLoading && _allImageFiles.isEmpty)
              Text("未找到可拖拽的图片".tl, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("关闭".tl),
        ),
      ],
    );
  }

  Widget _buildCoverStack() {
    final displayItems = widget.selectedItems.take(5).toList();
    final stack = Center(
      child: SizedBox(
        height: 150,
        width: 120 + (displayItems.length - 1) * 10,
        child: Stack(
          children: [
            for (int i = 0; i < displayItems.length; i++)
              Positioned(
                left: i * 10.0,
                top: (displayItems.length - 1 - i) * 5.0,
                child: Container(
                  width: 100,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(displayItems[i].coverPath ?? ""),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey,
                        child: const Icon(Icons.broken_image, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return _BulkDragWrapper(
      isLoading: _isLoading,
      allDragItems: _allDragItems,
      child: stack,
    );
  }

  Widget _buildDragSource() {
    return _BulkDragWrapper(
      isLoading: _isLoading,
      allDragItems: _allDragItems,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.drag_indicator),
            const SizedBox(width: 8),
            Text("按住并拖拽图片".tl, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// 批量拖拽包装组件，封装了重复的拖拽逻辑
class _BulkDragWrapper extends StatelessWidget {
  final bool isLoading;
  final List<DragItem> allDragItems;
  final Widget child;

  const _BulkDragWrapper({
    required this.isLoading,
    required this.allDragItems,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading || allDragItems.isEmpty) {
      return child;
    }

    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      dragItemProvider: (request) {
        if (allDragItems.isEmpty) return null;
        return allDragItems[0];
      },
      child: DraggableWidget(
        onDragConfiguration: (configuration, session) {
          final items = <DragConfigurationItem>[];
          final refCountingImage = _RefCountingSnapshot(
            configuration.items[0].image.snapshot,
            configuration.items[0].image.rect,
            allDragItems.length,
          );
          for (int i = 0; i < allDragItems.length; i++) {
            items.add(DragConfigurationItem(
              item: allDragItems[i],
              image: refCountingImage,
            ));
          }
          return DragConfiguration(
            items: items,
            allowedOperations: [DropOperation.copy],
          );
        },
        child: child,
      ),
    );
  }
}

/// 引用计数镜像包装器，用于解决批量拖拽时共享镜像导致的重复释放问题
class _RefCountingSnapshot extends raw.TargetedWidgetSnapshot {
  int _count;
  _RefCountingSnapshot(WidgetSnapshot snapshot, Rect rect, this._count) : super(snapshot, rect);

  @override
  void dispose() {
    _count--;
    if (_count <= 0) {
      super.dispose();
    }
  }
}

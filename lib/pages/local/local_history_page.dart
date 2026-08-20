import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_history.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:path/path.dart' as Path;
import '../reader/comic_reading_page.dart';
import 'local_thumbs_page.dart';
import 'local_comic_tile.dart';
import 'local_comic_page.dart';
import 'dart:io';
import '../../foundation/file_utils.dart';
import '../../components/components.dart';

class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    final history = await LocalHistoryManager().getAll();
    // 转换为 Map 以便修改
    final items = history.map((e) => e.toMap()).toList();

    if (mounted) {
      setState(() {
        _history = items;
        _loading = false;
      });
    }
  }

  Future<void> _clearInvalidHistory() async {
    showLoadingDialog(context);
    int clearedCount = 0;

    final history = List<Map<String, dynamic>>.from(_history);
    for (var item in history) {
      final path = item['path'] as String;
      if (!Directory(path).existsSync()) {
        await LocalHistoryManager().remove(path);
        clearedCount++;
      }
    }

    if (mounted) {
      App.back(context); // 关闭加载对话框
      if (clearedCount > 0) {
        showToast(message: "已清理 $clearedCount 条失效记录".tl);
        _loadHistory();
      } else {
        showToast(message: "未发现失效记录".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("历史记录".tl),
        actions: [
          IconButton(
            onPressed: _clearInvalidHistory,
            tooltip: "清理失效记录".tl,
            icon: const Icon(Icons.cleaning_services),
          ),
          IconButton(
            onPressed: () {
              showConfirmDialog(
                context,
                "清除历史记录".tl,
                "确认清除所有历史记录?".tl,
                () async {
                  for (var item in _history) {
                    await LocalHistoryManager().remove(item['path'] as String);
                  }
                  _loadHistory();
                },
              );
            },
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? Center(child: Text("暂无记录".tl))
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                int crossAxisCount = (width / 180).floor();
                if (crossAxisCount < 2) crossAxisCount = 2;

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.7,
                  ),
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    final path = item['path'] as String;
                    final title = Path.basename(path);
                    final cover = item['cover'] as String? ?? '';

                    final model = LocalComicModel(
                      path: path,
                      title: title,
                      cover: cover,
                    );

                    return LocalComicTile(
                      model: model,
                      onReload: _loadHistory,
                      allDirPaths: _history
                          .map((e) => e['path'] as String)
                          .toList(),
                      onTap: (historyMap) async {
                        final history = await LocalHistoryManager().find(path);
                        final initIndex = history?.pageIndex ?? 1;
                        final isReversed = history?.isReversed == 1;
                        await App.globalTo(
                          () => ComicReadingPage.localComic(
                            path,
                            title,
                            initialPage: initIndex,
                            isReversed: isReversed,
                          ),
                        );
                        _loadHistory();
                      },
                      onSecondaryTap: (details) =>
                          _showComicMenu(context, model, details),
                      onLongPress: () => _showComicMenu(context, model, null),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showComicMenu(
    BuildContext context,
    LocalComicModel model,
    TapDownDetails? details,
  ) {
    final globalPosition = details?.globalPosition;
    if (globalPosition == null) return;

    showContextMenu(
      context: App.globalContext!,
      globalPosition: globalPosition,
      items: [
        popupMenuItem(
          text: "查看详情".tl,
          icon: Icons.info_outline,
          onTap: () {
            App.globalTo(
              () => LocalThumbsPage(
                dirPath: model.path,
                allDirPaths: _history.map((e) => e['path'] as String).toList(),
              ),
            );
          },
        ),
        popupMenuItem(
          text: "清除此条历史记录".tl,
          icon: Icons.history_toggle_off,
          onTap: () async {
            await LocalHistoryManager().remove(model.path);
            _loadHistory();
          },
        ),
        popupMenuItem(
          text: "打开文件夹".tl,
          icon: Icons.folder_open,
          onTap: () {
            FileUtils.openFileOrDirectory(model.path);
          },
        ),
      ],
    );
  }
}

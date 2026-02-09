import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:path/path.dart' as Path;
import '../reader/comic_reading_page.dart';
import 'local_thumbs_page.dart';
import 'local_comic_tile.dart';
import 'local_comic_page.dart';
import 'dart:io';
import '../../foundation/file_utils.dart';
import '../../tools/map_extension.dart';
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
    
    final history = await downloadManager.getAllLocalHistory();
    // 转换为 Map 以便修改
    final items = history.map((e) => Map<String, dynamic>.from(e)).toList();

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
        await downloadManager.deleteLocalHistory(path);
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
              showConfirmDialog(context, "清除历史记录".tl, "确认清除所有历史记录?".tl, () async {
                for (var item in _history) {
                  await downloadManager.deleteLocalHistory(item['path'] as String);
                }
                _loadHistory();
              });
            },
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(child: Text("暂无记录".tl))
              : LayoutBuilder(builder: (context, constraints) {
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
                        initialHistory: item,
                        onReload: _loadHistory,
                        allDirPaths: _history.map((e) => e['path'] as String).toList(),
                        onTap: (history) async {
                           final initIndex = history?.optInt('pageIndex', 1) ?? 1;
                           final isReversed = history?.optInt('isReversed') == 1;
                           await App.globalTo(() => ComicReadingPage.localComic(
                                path,
                                title,
                                initialPage: initIndex,
                                isReversed: isReversed,
                              ));
                           _loadHistory();
                        },
                        onSecondaryTap: (details) => _showComicMenu(context, model, details),
                        onLongPress: () => _showComicMenu(context, model, null),
                      );
                    },
                  );
                }),
    );
  }

  void _showComicMenu(BuildContext context, LocalComicModel model, TapDownDetails? details) {
    showDesktopMenu(
      App.globalContext!,
      details?.globalPosition ?? Offset.zero,
      [
        DesktopMenuEntry(
          text: "查看详情".tl,
          onClick: () async {
            App.globalTo(() => LocalThumbsPage(
                  dirPath: model.path,
                  allDirPaths: _history.map((e) => e['path'] as String).toList(),
                ));
          },
        ),
        DesktopMenuEntry(
          text: "清除此条历史记录".tl,
          onClick: () async {
            await downloadManager.deleteLocalHistory(model.path);
            _loadHistory();
          },
        ),
        DesktopMenuEntry(
          text: "打开文件夹".tl,
          onClick: () {
            FileUtils.openFileOrDirectory(model.path);
          },
        ),
      ],
    );
  }
}

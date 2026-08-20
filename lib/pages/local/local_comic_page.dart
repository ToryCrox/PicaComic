import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/components/components.dart';
import 'dart:io';

import '../../foundation/app.dart';
import '../../foundation/local_history.dart';

import '../../tools/image_utils.dart';
import '../../tools/type_util.dart';
import '../reader/comic_reading_page.dart';
import './local_thumbs_page.dart';
import 'pick_out_nyako_dialog.dart';
import 'local_history_page.dart';
import 'local_favorites_page.dart';
import 'local_comic_tile.dart';

class LocalComicPage extends StatefulWidget {
  final String? parentPath;

  const LocalComicPage({Key? key, this.parentPath}) : super(key: key);

  @override
  State<LocalComicPage> createState() => _LocalComicPageState();
}

class _LocalComicPageState extends State<LocalComicPage> {
  // 本地漫画列表
  final List<LocalComicModel> _localComics = [];
  // 当前目录文件总大小
  String _fileSize = '';

  // 文件排序方式
  late ComicFileSort _fileSort =
      ComicFileSort.values.asNameMap()[PrefsHelper.getString(
        'local_comic_folder_sort',
      )] ??
      ComicFileSort.asc;

  // 是否倒序
  bool get isReversed => _fileSort == ComicFileSort.desc;

  @override
  void initState() {
    super.initState();
    _loadLocalComics();
  }

  // 加载本地漫画列表
  Future<void> _loadLocalComics() async {
    final parentPath = widget.parentPath;
    if (parentPath == null) {
      // 加载根目录（已添加的本地漫画）
      final localComics = await downloadManager.getAllLocal();
      final list = <LocalComicModel>[];
      for (final map in localComics) {
        final m = LocalComicModel.fromMap(map);
        final imagePath = await _getCoverImage(m.path);
        list.add(m.copyWith(cover: m.cover.isNotEmpty ? m.cover : imagePath));
      }
      _localComics.clear();
      _localComics.addAll(list.sortedFileNameBy((e) => e.path));
      _fileSize = '';
    } else {
      // 加载子目录
      _localComics.clear();
      final parentDir = Directory(parentPath);
      sFileRelativeFromPath = Path.canonicalize(parentDir.path);

      final files = (await parentDir.list().toList())
          .whereType<Directory>()
          .sortedByName();
      for (final file in files) {
        final path = file.absolute.path;
        final comic = LocalComicModel(
          path: path,
          title: Path.basename(path),
          cover: await _getCoverImage(path),
        );
        _localComics.add(comic);
      }
      if (isReversed) {
        // 如果是倒序，翻转列表
        final newList = List.of(_localComics.reversed);
        _localComics.clear();
        _localComics.addAll(newList);
      }
    }
    setState(() {});
  }

  // 计算并显示当前目录所有文件大小
  Future<void> _loadAllFileSize(final String dir) async {
    int totalFileSize = await workerManager.execute<int>(
      _buildComputeTask(dir),
    );
    if (widget.parentPath == dir) {
      setState(() {
        _fileSize = bytesLengthToReadableSize(totalFileSize);
      });
    }
  }

  static Future<int> Function() _buildComputeTask(String dir) {
    return () => _computeAllFileSize(dir);
  }

  // 在后台isolate中计算文件大小
  static Future<int> _computeAllFileSize(final String dir) async {
    int totalFileSize = 0;
    final files = Directory(dir).listSync(recursive: true);
    for (final file in files) {
      if (file is File) {
        totalFileSize += file.lengthSync();
      }
    }
    return totalFileSize;
  }

  // 获取封面图片路径
  Future<String> _getCoverImage(String directory) async {
    final dir = Directory(directory);
    try {
      final file = await dir.list(recursive: true).firstWhere(predictImageFile);
      return file.path;
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentPath = widget.parentPath;
    String titleText =
        '本地漫画${parentPath != null ? '(${Path.basename(parentPath)})' : ''}';
    if (_fileSize.isNotEmpty) {
      titleText += ' | $_fileSize';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          if (parentPath != null)
            IconButton(
              onPressed: () => _loadAllFileSize(parentPath),
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const PickOutNyakoDialog(),
            ),
            icon: const Icon(Icons.auto_fix_high),
            tooltip: "漫画整理工具".tl,
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _fileSort = isReversed ? ComicFileSort.asc : ComicFileSort.desc;
                PrefsHelper.setString(
                  'local_comic_folder_sort',
                  _fileSort.name,
                );
                _localComics.setAll(0, _localComics.reversed.toList());
              });
            },
            icon: Icon(isReversed ? Icons.arrow_downward : Icons.arrow_upward),
          ),
          IconButton(
            onPressed: () => App.to(context, () => const LocalHistoryPage()),
            icon: const Icon(Icons.history),
            tooltip: "历史记录".tl,
          ),
          IconButton(
            onPressed: () => App.to(context, () => const LocalFavoritesPage()),
            icon: const Icon(Icons.collections_bookmark),
            tooltip: "本地收藏".tl,
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: DropRegion(
        formats: Formats.standardFormats,
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: (event) => DropOperation.copy,
        onPerformDrop: (event) async {
          final item = event.session.items.first;
          item.dataReader?.getValue(Formats.fileUri, (value) {
            if (value != null) _dropFile(value.toFilePath());
          });
        },
        child: _buildBody(),
      ),
    );
  }

  // 处理拖拽文件/文件夹
  Future _dropFile(String path) async {
    if (FileSystemEntity.isDirectorySync(path)) {
      await downloadManager.addLocalItem(
        path: path,
        title: Path.basename(path),
        subtitle: '',
        json: {},
        size: 0,
        cover: '',
      );
      _loadLocalComics();
    }
  }

  // 构建页面主体
  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 计算每行显示的列数，根据窗口宽度动态调整
        int crossAxisCount = (width / 180).floor();
        if (crossAxisCount < 2) crossAxisCount = 2;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _localComics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemBuilder: (context, index) {
            final model = _localComics[index];
            return LocalComicTile(
              model: model,
              onReload: _loadLocalComics,
              allDirPaths: _localComics.map((e) => e.path).toList(),
              onTap: (history) async {
                if (history != null) {
                  // 读取漫画
                  final initIndex = history.optInt('pageIndex', 1);
                  final isReversed = history.optInt('isReversed') == 1;
                  await App.globalTo(
                    () => ComicReadingPage.localComic(
                      model.path,
                      model.title,
                      allDirPaths: _localComics.map((e) => e.path).toList(),
                      initialPage: initIndex,
                      isReversed: isReversed,
                    ),
                  );
                } else {
                  final dir = Directory(model.path);
                  final subDirs = (await dir.list().toList())
                      .whereType<Directory>();
                  if (subDirs.isNotEmpty) {
                    // 如果含有子目录，进入下一级
                    App.to(
                      context,
                      () => LocalComicPage(parentPath: model.path),
                    );
                  } else {
                    // 读取漫画
                    final initIndex = history?.optInt('pageIndex', 1) ?? 1;
                    final isReversed = history?.optInt('isReversed') == 1;
                    await App.globalTo(
                      () => ComicReadingPage.localComic(
                        model.path,
                        model.title,
                        allDirPaths: _localComics.map((e) => e.path).toList(),
                        initialPage: initIndex,
                        isReversed: isReversed,
                      ),
                    );
                  }
                }
              },
              onSecondaryTap: (details) =>
                  _showComicMenu(context, model, details),
              onLongPress: () => _showComicMenu(context, model, null),
            );
          },
        );
      },
    );
  }

  void _showComicMenu(
    BuildContext context,
    LocalComicModel model,
    TapDownDetails? details,
  ) {
    if (details == null) return;
    final parentPath = widget.parentPath;
    showContextMenu(
      context: App.globalContext!,
      globalPosition: details.globalPosition,
      items: [
        popupMenuItem(
          text: "查看详情".tl,
          icon: Icons.info_outline,
          onTap: () {
            App.globalTo(
              () => LocalThumbsPage(
                dirPath: model.path,
                allDirPaths: _localComics.map((e) => e.path).toList(),
              ),
            );
          },
        ),
        popupMenuItem(
          text: "清除历史记录".tl,
          icon: Icons.history_toggle_off,
          onTap: () async {
            await LocalHistoryManager().remove(model.path);
            _loadLocalComics();
          },
        ),
        popupMenuItem(
          text: "删除".tl,
          icon: Icons.delete_outline,
          onTap: () {
            showDialog(
              context: App.globalContext!,
              builder: (context) => AlertDialog(
                title: Text("确认删除".tl),
                content: Text(
                  "确定要删除此本地漫画吗？".tl +
                      (parentPath == null ? "\n(仅移除记录，不删除文件)" : "\n(将物理删除文件夹)"),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("取消".tl),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (parentPath == null) {
                        await downloadManager.deleteLocal(model.path);
                      } else {
                        try {
                          Directory(model.path).deleteSync(recursive: true);
                        } catch (e) {
                          showToast(message: "删除失败: $e");
                        }
                      }
                      _loadLocalComics();
                    },
                    child: Text("确定".tl),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class LocalComicModel {
  // 漫画路径
  final String path;
  // 标题
  final String title;
  // 副标题
  final String subtitle;
  // 额外数据
  final Map<String, dynamic> json;
  // 大小
  final double size;
  // 封面路径
  final String cover;

  const LocalComicModel({
    this.path = '',
    this.title = '',
    this.subtitle = '',
    this.json = const {},
    this.size = 0,
    this.cover = '',
  });

  factory LocalComicModel.fromMap(Map<String, dynamic> map) {
    return LocalComicModel(
      path: TypeUtil.parseString(map['path']),
      title: TypeUtil.parseString(map['title']),
      subtitle: TypeUtil.parseString(map['subtitle']),
      json: TypeUtil.parseMap(map['json']),
      size: TypeUtil.parseDouble(map['size']),
      cover: TypeUtil.parseString(map['cover']),
    );
  }

  Map<String, dynamic> toMap() => {
    'path': path,
    'title': title,
    'subtitle': subtitle,
    'json': json,
    'size': size,
    'cover': cover,
  };

  LocalComicModel copyWith({
    String? path,
    String? title,
    String? subtitle,
    Map<String, dynamic>? json,
    double? size,
    String? cover,
  }) => LocalComicModel(
    path: path ?? this.path,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    json: json ?? this.json,
    size: size ?? this.size,
    cover: cover ?? this.cover,
  );
}

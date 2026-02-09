import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pica_comic/network/download/download_manager.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:pica_comic/tools/shared_compute.dart';
import 'package:pica_comic/tools/translations.dart';
import 'dart:io';

import '../../components/components.dart';
import '../../foundation/file_utils.dart';
import '../../foundation/app.dart';

import '../../tools/image_utils.dart';
import '../../tools/input_dialog.dart';
import '../../tools/type_util.dart';
import '../reader/comic_reading_page.dart';
import './local_thumbs_page.dart';
import 'pick_out_nyako_dialog.dart';


class LocalComicPage extends StatefulWidget {
  const LocalComicPage({Key? key}) : super(key: key);

  @override
  State<LocalComicPage> createState() => _LocalComicPageState();
}

class _LocalComicPageState extends State<LocalComicPage> {
  // 本地漫画列表
  final List<LocalComicModel> _localComics = [];

  // 历史路径栈，用于导航返回
  final List<String> _historyPaths = [];
  // 当前父级路径，如果为null则表示在根目录
  String? _parentPath;
  // 当前目录文件总大小
  String _fileSize = '';

  // 文件排序方式
  late ComicFileSort _fileSort = ComicFileSort.values
          .asNameMap()[PrefsHelper.getString('local_comic_folder_sort')] ??
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
    final parentPath = _parentPath;
    if (parentPath == null) {
      // 加载根目录（已添加的本地漫画）
      final localComics = await downloadManager.getAllLocal();
      final list = <LocalComicModel>[];
      for (final map in localComics) {
        final m = LocalComicModel.fromMap(map);
        final imagePath = await _getCoverImage(m.path);
        list.add(m.copyWith(
          cover: m.cover.isNotEmpty ? m.cover : imagePath,
        ));
      }
      _localComics.clear();
      _localComics.addAll(list.sortedFileNameBy((e) => e.path));

      _fileSize = '';
    } else {
      // 加载子目录
      _localComics.clear();
      final parentDir = Directory(parentPath);
      // 设置相对路径基准，用于排序等
      sFileRelativeFromPath = Path.canonicalize(parentDir.path);

      // 获取子目录列表
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
      if (_fileSort == ComicFileSort.desc) {
        // 如果是倒序，翻转列表
        final newList = List.of(_localComics.reversed);
        _localComics.clear();
        _localComics.addAll(newList);
      }

      //_loadAllFileSize(parentPath);
      debugPrint(
          "localComics: ${_localComics.map((e) => Path.basename(e.cover)).toList()}");
    }

    setState(() {});
  }

  // 计算并显示当前目录所有文件大小
  Future<void> _loadAllFileSize(final String dir) async {
    int totalFileSize = await sharedCompute(_computeAllFileSize, dir);
    if (_parentPath == dir) {
      setState(() {
        _fileSize = bytesLengthToReadableSize(totalFileSize);
      });
    }
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
      debugPrint(e.toString());
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentPath = _parentPath;
    String titleText =
        '本地漫画${parentPath != null ? '(${Path.basename(parentPath)})' : ''}';
    if (_fileSize.isNotEmpty) {
      titleText += ' | $_fileSize';
    }
    return PopScope(
      canPop: parentPath == null,
      onPopInvokedWithResult: (didPop, result) {
        if (_parentPath != null) {
          _parentPath =
              _historyPaths.isNotEmpty ? _historyPaths.removeLast() : null;
          _loadLocalComics();
        }
        setState(() {});
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(titleText),
          leading: const BackButton(),
          actions: [
            if (parentPath != null)
              IconButton(
                onPressed: () {
                  _loadAllFileSize(parentPath);
                },
                icon: const Icon(Icons.refresh),
              ),
            IconButton(
              onPressed: () {
                showDialog(context: context, builder: (context) => const PickOutNyakoDialog());
              },
              icon: const Icon(Icons.auto_fix_high),
              tooltip: "漫画整理工具".tl,
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _fileSort = _fileSort == ComicFileSort.asc
                      ? ComicFileSort.desc
                      : ComicFileSort.asc;
                  PrefsHelper.setString(
                      'local_comic_folder_sort', _fileSort.name);
                  final newImages = List.of(_localComics.reversed);
                  _localComics.clear();
                  _localComics.addAll(newImages);
                });
              },
              icon: _fileSort == ComicFileSort.asc
                  ? const Icon(Icons.arrow_upward)
                  : const Icon(Icons.arrow_downward),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: DropRegion(
          formats: Formats.standardFormats,
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: (event) {
            if (event.session.items.isEmpty) {
              return DropOperation.none;
            }
            final item = event.session.items.first;
            if (item.canProvide(Formats.fileUri)) {
              return DropOperation.copy;
            }
            return DropOperation.none;
          },
          onPerformDrop: (event) async {
            final item = event.session.items.first;
            final reader = item.dataReader!;
            reader.getValue(Formats.fileUri, (value) {
              if (value != null) {
                _dropFile(value.toFilePath());
              }
            });
          },
          child: _buildPage(),
        ),
      ),
    );
  }

  // 处理拖拽文件/文件夹
  Future _dropFile(String path) async {
    if (FileSystemEntity.isDirectorySync(path)) {
      final name = Path.basename(path);
      await downloadManager.addLocalItem(
        path: path,
        title: name,
        subtitle: '',
        json: {},
        size: 0,
        cover: '',
      );
      _loadLocalComics();
    }
  }

  // 构建页面主体
  Widget _buildPage() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      // 计算每行显示的列数，根据窗口宽度动态调整
      // 假设最小宽度为 160，最大宽度为 240
      int crossAxisCount = (width / 180).floor();
      if (crossAxisCount < 2) crossAxisCount = 2; // 至少两列

      return GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _localComics.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.7, // 调整宽高比
        ),
        itemBuilder: _buildItem,
      );
    });
  }

  // 构建单个漫画项
  Widget _buildItem(BuildContext context, int index) {
    final model = _localComics[index];
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final dir = Directory(model.path);
          final subDirs = (await dir.list().toList()).whereType<Directory>();
          if (subDirs.isNotEmpty) {
            if (_parentPath != null) {
              _historyPaths.add(_parentPath!);
            }
            _parentPath = model.path;
            debugPrint('parent path: ${model.path}');
            _loadLocalComics();
            setState(() {});
          } else {
            App.globalTo(
              () => LocalThumbsPage(
                dirPath: model.path,
                isEnableDelete: true,
                allDirPaths: _localComics.map((e) => e.path).toList(),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        onSecondaryTapDown: (TapDownDetails details) {
          showDesktopMenu(
            App.globalContext!,
            Offset(details.globalPosition.dx, details.globalPosition.dy),
            _menuList(model),
          );
        },
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
                    if (model.cover.isNotEmpty)
                      Image.file(
                        File(model.cover),
                        fit: BoxFit.cover, 
                        // 使用 cover 填充，如果有裁剪问题可以改 contain 或增加背景色
                        cacheWidth: 300,
                      )
                    else 
                      ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.folder, size: 48, color: colorScheme.onSurfaceVariant),
                      ),
                    
                    // 渐变遮罩，增强文字可读性
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 右下角按钮组
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 阅读按钮
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _readComic(model),
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
                          const SizedBox(width: 8),
                          // 打开文件夹按钮
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                FileUtils.openFileOrDirectory(model.path);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.folder_open,
                                  size: 18,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Text(
                  model.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 右键菜单列表
  List<DesktopMenuEntry> _menuList(LocalComicModel model) {
    return [
      DesktopMenuEntry(
        text: "阅读".tl,
        onClick: () => _readComic(model),
      ),
      DesktopMenuEntry(
        text: "查看详情".tl,
        onClick: () {
          App.globalTo(() => LocalThumbsPage(
                dirPath: model.path,
                isEnableDelete: true,
                allDirPaths: _localComics.map((e) => e.path).toList(),
              ));
        },
      ),
      DesktopMenuEntry(
        text: "删除".tl,
        onClick: () async {
          if (_parentPath == null) {
            downloadManager.deleteLocal(model.path);
            _loadLocalComics();
          } else {
            showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('提示'),
                    content: const Text('确定要将文件从磁盘删除吗？删除后无法恢复'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final dir = Directory(model.path);
                          await dir.delete(recursive: true);
                          _loadLocalComics();
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  );
                });
          }
        },
      ),
      if (_parentPath != null)
        DesktopMenuEntry(
            text: '重命名',
            onClick: () {
              _renameFolder(model);
            }),
      DesktopMenuEntry(
        text: "复制路径".tl,
        onClick: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            var path = model.path;
            Clipboard.setData(ClipboardData(text: path));
          });
        },
      ),
      DesktopMenuEntry(
        text: "打开目录".tl,
        onClick: () {
          Future.delayed(const Duration(milliseconds: 100), () {
            var path = model.path;
            FileUtils.openFileOrDirectory(path);
          });
        },
      ),
    ];
  }

  // 阅读漫画
  Future<void> _readComic(LocalComicModel model) async {
    final history = await downloadManager.getLocalHistory(model.path);
    final initIndex = history.optInt('pageIndex', 1);
    final isReversed = history.optInt('isReversed') == 1;
    App.globalTo(() => ComicReadingPage.localComic(
          model.path,
          model.title,
          allDirPaths: _localComics.map((e) => e.path).toList(),
          initialPage: initIndex,
          isReversed: isReversed,
          isAutoFullscreenAndScroll: false,
        ));
  }

  // 重命名文件夹
  Future<void> _renameFolder(LocalComicModel model) async {
    final path = model.path;
    final fileName = Path.basename(path);
    String? newName = await InputDialog.show(
      context: App.globalContext!,
      title: '重命名',
      hint: '请输入新名称',
      content: fileName,
      predicate: (text) {
        return text.isNotEmpty;
      },
    );
    newName = newName?.replaceAll('/', ' ');
    if (newName != null && newName != fileName) {
      final newPath = Path.join(Path.dirname(path), newName);
      try {
        await Directory(path).rename(newPath);
        _loadLocalComics();
      } catch (e) {
        showToast(message: '重命名失败');
      }
    }
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

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'title': title,
      'subtitle': subtitle,
      'json': json,
      'size': size,
      'cover': cover,
    };
  }

  LocalComicModel copyWith({
    String? path,
    String? title,
    String? subtitle,
    Map<String, dynamic>? json,
    double? size,
    String? cover,
  }) {
    return LocalComicModel(
      path: path ?? this.path,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      json: json ?? this.json,
      size: size ?? this.size,
      cover: cover ?? this.cover,
    );
  }
}

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:pica_comic/network/download.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/prefs_helper.dart';
import 'package:pica_comic/tools/shared_compute.dart';
import 'package:pica_comic/tools/translations.dart';
import 'dart:io';

import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../tools/image_utils.dart';
import '../../tools/input_dialog.dart';
import '../../tools/type_util.dart';
import '../reader/comic_reading_page.dart';
import 'local_thumbs_page.dart';

class LocalComicPage extends StatefulWidget {
  const LocalComicPage({Key? key}) : super(key: key);

  @override
  State<LocalComicPage> createState() => _LocalComicPageState();
}

class _LocalComicPageState extends State<LocalComicPage> {
  final List<LocalComicModel> _localComics = [];

  final List<String> _historyPaths = [];
  String? _parentPath;
  String _fileSize = '';

  late ComicFileSort _fileSort = ComicFileSort.values
          .asNameMap()[PrefsHelper.getString('local_comic_folder_sort')] ??
      ComicFileSort.asc;

  bool get isReversed => _fileSort == ComicFileSort.desc;

  @override
  void initState() {
    super.initState();
    _loadLocalComics();
  }

  Future<void> _loadLocalComics() async {
    final parentPath = _parentPath;
    if (parentPath == null) {
      final downloadManager = DownloadManager();
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
      if (_fileSort == ComicFileSort.desc) {
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

  Future<void> _loadAllFileSize(final String dir) async {
    int totalFileSize = await sharedCompute(_computeAllFileSize, dir);
    if (_parentPath == dir) {
      setState(() {
        _fileSize = bytesLengthToReadableSize(totalFileSize);
      });
    }
  }

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
        body: DropTarget(
          enable: true,
          onDragDone: _dropFile,
          child: _buildPage(),
        ),
      ),
    );
  }

  Future _dropFile(DropDoneDetails details) async {
    List<XFile> files = details.files;
    final dirPaths = files
        .map((e) => e.path)
        .where((element) => FileSystemEntity.isDirectorySync(element))
        .toList();
    if (dirPaths.isNotEmpty) {
      for (var dirPath in dirPaths) {
        final name = Path.basename(dirPath);
        await DownloadManager().addLocalItem(
          path: dirPath,
          title: name,
          subtitle: '',
          json: {},
          size: 0,
          cover: '',
        );
      }
      _loadLocalComics();
    }
  }

  Widget _buildPage() {
    return GridView.builder(
      itemCount: _localComics.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 250,
      ),
      itemBuilder: _buildItem,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final model = _localComics[index];
    return InkWell(
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
            // App.globalTo(
            //   () => ComicReadingPage.localComic(
            //     model.path,
            //     model.title,
            //   ),
            // );
          }
        },
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        onSecondaryTapDown: (TapDownDetails details) {
          showDesktopMenu(
            App.globalContext!,
            Offset(details.globalPosition.dx, details.globalPosition.dy),
            _menuList(model),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (model.cover.isNotEmpty)
                Positioned.fill(
                  child: Image.file(
                    File(model.cover),
                    fit: BoxFit.contain,
                    cacheWidth: 200,
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.black.withOpacity(0.5),
                  child: Text(
                    model.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  List<DesktopMenuEntry> _menuList(LocalComicModel model) {
    return [
      DesktopMenuEntry(
        text: "阅读".tl,
        onClick: () async {
          final history = await DownloadManager().getLocalHistory(model.path);
          final initIndex = history.optInt('pageIndex', 1);
          final isReversed = history.optInt('isReversed') == 1;
          App.globalTo(() => ComicReadingPage.localComic(
                model.path,
                model.title,
                allDirPaths: _localComics.map((e) => e.path).toList(),
                initialPage: initIndex,
                isReversed: isReversed,
              ));
        },
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
      if (_parentPath == null)
        DesktopMenuEntry(
          text: "删除".tl,
          onClick: () {
            DownloadManager().deleteLocal(model.path);
            _loadLocalComics();
          },
        ),
      if (_parentPath != null) DesktopMenuEntry(text: '重命名', onClick: () {
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
            OpenFile.open(path);
          });
        },
      ),
    ];
  }

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
  final String path;
  final String title;
  final String subtitle;
  final Map<String, dynamic> json;
  final double size;
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

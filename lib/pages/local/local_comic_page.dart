import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/str_ext.dart';
import 'package:pica_comic/tools/translations.dart';
import 'dart:io';

import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../tools/type_util.dart';
import '../reader/comic_reading_page.dart';

class LocalComicPage extends StatefulWidget {
  const LocalComicPage({Key? key}) : super(key: key);

  @override
  State<LocalComicPage> createState() => _LocalComicPageState();
}

class _LocalComicPageState extends State<LocalComicPage> {
  final List<LocalComicModel> _localComics = [];

  String? _parentPath;

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
      _localComics.clear();
      for (final map in localComics) {
        final m = LocalComicModel.fromMap(map);
        final imagePath = await _getCoverImage(m.path);
        _localComics.add(m.copyWith(
          cover: m.cover.isNotEmpty ? m.cover : imagePath,
        ));
      }
    } else {
      _localComics.clear();
      final parentDir = Directory(parentPath);
      final files = parentDir.listSync().where((e) => e is Directory);
      for (final file in files) {
        final path = file.absolute.path;
        final comic = LocalComicModel(
          path: path,
          title: Path.basename(path),
          cover: await _getCoverImage(path),
        );
        _localComics.add(comic);
      }
      debugPrint(
          "localComics: ${_localComics.map((e) => Path.basename(e.cover)).toList()}");
    }

    setState(() {});
  }

  Future<String> _getCoverImage(String directory) async {
    final dir = Directory(directory);
    final exts = {'.webp', '.jpg', '.png', '.jpeg'};
    final file = await dir.list(recursive: true).firstWhere((e) {
      final ext = Path.extension(e.path).toLowerCase();
      return exts.contains(ext);
    }, orElse: () => File(''));
    // final file = (await dir.list(recursive: true).toList()).whereType<File>().sorted((a, b) {
    //   final aName = Path.basenameWithoutExtension(a.path);
    //   final bName = Path.basenameWithoutExtension(b.path);
    //   return aName.compareIndex(bName);
    // }).firstWhereOrNull((e) {
    //   final ext = Path.extension(e.path).toLowerCase();
    //   return {'.webp', '.jpg', '.png', '.jpeg'}.contains(ext);
    // });
    return file.path ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _parentPath == null,
      onPopInvokedWithResult: (didPop, result) {
        if (_parentPath != null) {
          _parentPath = null;
          _loadLocalComics();
        }
        setState(() {});
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              '本地漫画${_parentPath != null ? '(${Path.basename(_parentPath!)})' : ''}'),
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
        final dir = Directory(dirPath);
        final size = 0; //await dir.getMBSizeSync();
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
      setState(() {});
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
            _parentPath = model.path;
            debugPrint('parent path: ${model.path}');
            _loadLocalComics();
            setState(() {});
          } else {
            App.globalTo(
              () => ComicReadingPage.localComic(
                model.path,
                model.title,
              ),
            );
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
                  padding: EdgeInsets.all(10),
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
        text: "删除".tl,
        onClick: () {
          DownloadManager().deleteLocal(model.path);
          setState(() {});
        },
      ),
      DesktopMenuEntry(
        text: "复制路径".tl,
        onClick: () {
          Future.delayed(const Duration(milliseconds: 300), () {
            var path = model.path;
            Clipboard.setData(ClipboardData(text: path));
          });
        },
      ),
    ];
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

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../network/download.dart';
import '../../tools/image_size_getter.dart';
import '../../tools/io_tools.dart';
import '../../tools/prefs_helper.dart';
import '../reader/comic_reading_page.dart';

class LocalThumbsPage extends StatefulWidget {
  const LocalThumbsPage({
    super.key,
    required this.dirPath,
    this.onItemTap,
    this.isEnableDelete = false,
    this.allDirPaths = const [],
  });

  final String dirPath;
  final List<String> allDirPaths;
  final void Function(int, String)? onItemTap;
  final bool isEnableDelete;

  @override
  State<LocalThumbsPage> createState() => _LocalThumbsPageState();
}

class _LocalThumbsPageState extends State<LocalThumbsPage> {
  final _imageFiles = <ImageFile>[];

  String _title = '';
  bool _loading = true;

  final _selectedImages = <ImageFile>[];

  bool _isSelectedMode = false;

  String _fileSize = '';

  late ComicFileSort _fileSort = ComicFileSort.values
          .asNameMap()[PrefsHelper.getString('local_comic_sort')] ??
      ComicFileSort.asc;

  bool get isReversed => _fileSort == ComicFileSort.desc;

  StreamSubscription? _imageSizeSubscription;

  @override
  void initState() {
    super.initState();
    _title = Path.basename(widget.dirPath);
    _loadImages();
  }

  @override
  void dispose() {
    super.dispose();
    _imageSizeSubscription?.cancel();
  }

  static Future<List<ImageFile>> loadImagesFilePaths(String dirPath) async {
    final dir = Directory(dirPath);
    //final images = (await dir.list(recursive: true).toList())
    sFileRelativeFromPath = Path.canonicalize(dirPath);
    final images = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(predictImageFile)
        //.sorted(fileNameCompare)
        .sortedByName()
        .map(
          (e) => ImageFile(
            path: e.absolute.path,
          ),
        )
        .toList();
    return images;
  }

  Future<void> _loadImages() async {
    final t1 = DateTime.now();
    //final images = await compute(loadImagesFilePaths, widget.dirPath);
    final images = await loadImagesFilePaths(widget.dirPath);
    final diff = DateTime.now().difference(t1);
    if (diff.inMilliseconds < 300) {
      final delay = 300 - diff.inMilliseconds;
      debugPrint("LocalThumbsPage: delay $delay ms");
      await Future.delayed(Duration(milliseconds: delay));
    }
    debugPrint(
        "LocalThumbsPage: load ${images.length} images, diff: ${diff.inMilliseconds}ms");
    setState(() {
      _loading = false;
      _imageFiles.clear();
      if (_fileSort == ComicFileSort.desc) {
        _imageFiles.addAll(images.reversed);
      } else {
        _imageFiles.addAll(images);
      }
    });
    _loadAllFileSize();
    _loadAllImageSize();
  }

  Future<void> _loadAllImageSize() async {
    final allImagePathList = _imageFiles.map((e) => e.path).toList();
    final imageFileMap = _imageFiles.groupFoldBy((e) => e.path, (p, e) => e);
    _imageSizeSubscription = computeImageSizes(allImagePathList).listen((e) {
      for(var imagePath in e.keys) {
        final sizeInfo = e[imagePath]!;
        final imageFile = imageFileMap[imagePath];
        if (imageFile != null) {
          imageFile.size = sizeInfo.size;
        }
      }
      if (mounted) {
        setState(() {});
      }
    });
    // int index = 0;
    // while (index < _imageFiles.length) {
    //   final end =
    //       index + 30 > _imageFiles.length ? _imageFiles.length : index + 30;
    //   final subImages = _imageFiles.sublist(index, end);
    //   final imageSizes = await compute(
    //     _loadImageSizes,
    //     subImages,
    //   );
    //   //final imageSizes = await _loadImageSizes(subImages.map((e) => e.path).toList());
    //   for (var i = 0; i < subImages.length; i++) {
    //     final imageFile = subImages[i];
    //     final size = imageSizes[imageFile.path];
    //     if (size != null) {
    //       imageFile.size = size;
    //     }
    //   }
    //   if (mounted) {
    //     setState(() {});
    //   } else {
    //     debugPrint("LocalThumbsPage umouted");
    //     return;
    //   }
    //   index += 30;
    // }
  }

  Future<void> _loadAllFileSize() async {
    int totalSize = 0;
    for (var i = 0; i < _imageFiles.length; i++) {
      final imageFile = _imageFiles[i];
      final file = File(imageFile.path);
      if (!file.existsSync()) {
        continue;
      }
      imageFile.fileSize = (File(imageFile.path)).lengthSync();
      totalSize += imageFile.fileSize;
    }
    setState(() {
      _fileSize = bytesLengthToReadableSize(totalSize);
    });
  }

  // static Future<Map<String, Size>> _loadImageSizes(
  //     List<ImageFile> imageFiles) async {
  //   final imageSizes = <String, Size>{};
  //   for (var i = 0; i < imageFiles.length; i++) {
  //     final imageFilePath = imageFiles[i].path;
  //     final file = File(imageFilePath);
  //     try {
  //       final sizeResult = ImageSizeGetter.getSizeResult(FileInput(file));
  //       imageSizes[imageFilePath] = sizeResult.size;
  //     } catch (e) {
  //       debugPrint("LocalThumbsPage: error: $e");
  //     }
  //   }
  //   return imageSizes;
  // }

  Future<void> _pixivSortTap() async {
    final controller = showLoadingDialog(context, message: "正在整理图片...");
    await compute(
      _organizePixivImages,
      ImageFileList(
        list: _imageFiles,
        dirPath: widget.dirPath,
      ),
    );
    controller.close();
    _loadImages();
  }

  /// 整理图片
  static Future<void> _organizePixivImages(ImageFileList imageFileList) async {
    final imageFiles = imageFileList.list;
    final dir = Directory(imageFileList.dirPath);
    if (!dir.existsSync()) {
      return;
    }
    final dirPath = Path.join(dir.parent.absolute.path, '[01]PIXIV画师合集');

    // 按照id分组
    final imagesCollection = <String, List<_PixivImageInfo>>{};
    for (var i = 0; i < imageFiles.length; i++) {
      final imageFile = imageFiles[i];
      final file = File(Path.canonicalize(imageFile.path));
      final name = Path.basenameWithoutExtension(file.path);
      final ext = Path.extension(file.path);
      final nameParts = name.split("_"); // 类似: [にっか]_125934717_結束いのり - 初練_p8
      if (nameParts.length < 3 || !file.existsSync()) {
        debugPrint("LocalThumbsPage: invalid image file: ${file.path}");
        continue;
      }
      final userName = nameParts[0];
      final illustId = nameParts[1];
      final title = nameParts.sublist(2, nameParts.length - 1).join('_');
      final part = nameParts.last;
      final imageInfo = _PixivImageInfo(
        userName: userName,
        illustId: illustId,
        title: title,
        part: part,
        file: file,
        ext: ext,
      );
      final list = imagesCollection.putIfAbsent(
        illustId,
        () => <_PixivImageInfo>[],
      );
      list.add(imageInfo);
    }

    for (final illustId in imagesCollection.keys) {
      final list = imagesCollection[illustId] ?? [];
      if (list.isEmpty) {
        continue;
      }
      final first = list.firstOrNull;
      if (first == null) {
        continue;
      }
      final userName = first.userName;

      String imageFolderPath;
      if (list.length >= 8) {
        // 8张以上，单独创建一个文件夹
        final imageFolder = '[${first.illustId}]${first.title}';
        imageFolderPath = Path.join(dirPath, userName, imageFolder);
      } else {
        imageFolderPath = Path.join(dirPath, userName, '[0]散图');
      }
      if (!Directory(imageFolderPath).existsSync()) {
        await Directory(imageFolderPath).create(recursive: true);
      }
      for (final item in list) {
        final fileName = '${item.illustId}_${item.part}${item.ext}';
        final newFilePath = Path.join(imageFolderPath, fileName);
        if (!File(newFilePath).existsSync()) {
          try {
            await item.file.rename(newFilePath);
            debugPrint(
                'move file:\n    ==: ${item.file.path}\n    =>: $newFilePath');
          } catch (e) {
            await item.file.copy(newFilePath);
            debugPrint('move file error: ${item.file.path}, $e');
          }
        } else {
          debugPrint('file exists!!!: $newFilePath');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title +
            (_imageFiles.isEmpty ? "" : " (${_imageFiles.length})") +
            (_fileSize != "" ? " | $_fileSize" : "")),
        actions: [
          if (_isSelectedMode)
            TextButton(
              onPressed: () {
                setState(() {
                  _isSelectedMode = false;
                  _selectedImages.clear();
                });
              },
              child: Text("取消".tl),
            ),
          if (_isSelectedMode)
            TextButton(
              onPressed: () {
                _deleteImageFileList(_selectedImages);
              },
              child: Text("删除".tl),
            ),
          IconButton(
            onPressed: () {
              setState(() {
                _fileSort = _fileSort == ComicFileSort.asc
                    ? ComicFileSort.desc
                    : ComicFileSort.asc;
                PrefsHelper.setString('local_comic_sort', _fileSort.name);
                final newImages = List.of(_imageFiles.reversed);
                _imageFiles.clear();
                _imageFiles.addAll(newImages);
              });
            },
            icon: _fileSort == ComicFileSort.asc
                ? const Icon(Icons.arrow_upward)
                : const Icon(Icons.arrow_downward),
          ),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_horiz,
            ),
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(
                  value: "pixiv_sort1",
                  onTap: () {
                    _pixivSortTap();
                  },
                  child: Text("整理Pixv图片".tl),
                ),
              ];
            },
          ),
          const SizedBox(
            width: 10,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (widget.onItemTap != null) {
            widget.onItemTap?.call(-1, '');
          } else {
            final history = await DownloadManager().getLocalHistory(widget.dirPath);
            final initIndex = history.optInt('pageIndex', 1);
            final isReversed = history.optInt('isReversed') == 1;
            App.globalTo(
              () => ComicReadingPage.localComic(
                widget.dirPath,
                _title,
                initialPage: initIndex,
                allDirPaths: widget.allDirPaths,
                isReversed: isReversed,
              ),
            );
          }
        },
        child: const Icon(Icons.play_circle),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final cacheWidth = MediaQuery.devicePixelRatioOf(context) * 150;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: _imageFiles.length,
      itemBuilder: (BuildContext context, int index) {
        final imageFile = _imageFiles[index];
        final selected = _selectedImages.contains(imageFile);
        return Stack(
          fit: StackFit.expand,
          children: [
            InkWell(
              onTap: () {
                if (_isSelectedMode) {
                  if (_selectedImages.contains(imageFile)) {
                    _selectedImages.remove(imageFile);
                  } else {
                    _selectedImages.add(imageFile);
                  }
                  setState(() {});
                } else if (widget.onItemTap != null) {
                  widget.onItemTap?.call(index + 1, imageFile.path);
                } else {
                  App.globalTo(
                    () => ComicReadingPage.localComic(
                      widget.dirPath,
                      _title,
                      initialPage: index + 1,
                      allDirPaths: widget.allDirPaths,
                      isReversed: isReversed,
                    ),
                  );
                }
              },
              onSecondaryTapDown: (TapDownDetails details) {
                showDesktopMenu(
                  App.globalContext!,
                  Offset(details.globalPosition.dx, details.globalPosition.dy),
                  _menuList(imageFile),
                );
              },
              onLongPress: () {
                if (widget.isEnableDelete && !_isSelectedMode) {
                  setState(() {
                    _isSelectedMode = true;
                    _selectedImages.add(imageFile);
                  });
                }
              },
              child: Image.file(
                File(imageFile.path),
                fit: BoxFit.contain,
                cacheWidth: cacheWidth.toInt(),
              ),
            ),
            if (imageFile.size != null)
              Positioned(
                bottom: 0,
                right: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "${imageFile.size!.width.toInt()}x${imageFile.size!.height.toInt()}",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Text(
                        bytesLengthToReadableSize(imageFile.fileSize),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                    border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                )),
              ),
            )
          ],
        );
      },
    );
  }

  List<DesktopMenuEntry> _menuList(ImageFile imageFile) {
    return [
      if (widget.isEnableDelete)
        DesktopMenuEntry(
            text: "删除".tl,
            onClick: () {
              _deleteImageFileList([imageFile]);
            }),
      DesktopMenuEntry(
        text: "选择".tl,
        onClick: () {
          setState(() {
            _isSelectedMode = true;
          });
        },
      ),
      DesktopMenuEntry(
        text: "复制路径",
        onClick: () {
          Future.delayed(const Duration(milliseconds: 200), () {
            var path = imageFile.path;
            Clipboard.setData(ClipboardData(text: path));
          });
        },
      ),
      DesktopMenuEntry(
        text: "打开文件",
        onClick: () {
          OpenFile.open(imageFile.path);
          // Future.delayed(const Duration(milliseconds: 100), () {
          //   var path = imagePath;
          //   Clipboard.setData(ClipboardData(text: path));
          // });
        },
      ),
    ];
  }

  Future<void> _deleteImageFileList(List<ImageFile> imageFileList) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("提示".tl),
          content: Text("确定要删除此图片吗？".tl),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("取消".tl),
            ),
            TextButton(
              onPressed: () {
                for (var imageFile in imageFileList) {
                  File(imageFile.path).deleteSync();
                  _imageFiles.remove(imageFile);
                }
                setState(() {});
                Navigator.of(context).pop();
                if (_isSelectedMode) {
                  setState(() {
                    _isSelectedMode = false;
                    _selectedImages.clear();
                  });
                }
              },
              child: Text("确定".tl),
            ),
          ],
        );
      },
    );
  }
}

class ImageFileList {
  final List<ImageFile> list;
  final String dirPath;

  const ImageFileList({
    required this.list,
    required this.dirPath,
  });
}

class ImageFile {
  final String path;
  Size? size;
  int fileSize;

  ImageFile({
    required this.path,
    this.size,
    this.fileSize = 0,
  });
}

enum ComicFileSort {
  asc,
  desc,
}

class _PixivImageInfo {
  final File file;
  final String userName;
  final String illustId;
  final String title;
  final String part;
  final String ext;

  _PixivImageInfo({
    required this.file,
    required this.userName,
    required this.illustId,
    required this.title,
    required this.part,
    required this.ext,
  });
}

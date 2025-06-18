import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/translations.dart';

import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../tools/io_tools.dart';
import '../reader/comic_reading_page.dart';

class LocalThumbsPage extends StatefulWidget {
  const LocalThumbsPage({
    super.key,
    required this.dirPath,
    this.onItemTap,
    this.isEnableDelete = false,
  });

  final String dirPath;
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

  @override
  void initState() {
    super.initState();
    _title = Path.basename(widget.dirPath);
    _loadImages();
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
      _imageFiles.addAll(images);
    });
    _loadAllFileSize();
    _loadAllImageSize();
  }

  Future<void> _loadAllImageSize() async {
    int index = 0;
    while (index < _imageFiles.length) {
      final end =
          index + 30 > _imageFiles.length ? _imageFiles.length : index + 30;
      final subImages = _imageFiles.sublist(index, end);
      final imageSizes = await compute(
        _loadImageSizes,
        subImages,
      );
      //final imageSizes = await _loadImageSizes(subImages.map((e) => e.path).toList());
      for (var i = 0; i < subImages.length; i++) {
        final imageFile = subImages[i];
        final size = imageSizes[imageFile.path];
        if (size != null) {
          imageFile.size = size;
        }
      }
      if (mounted) {
        setState(() {});
      } else {
        debugPrint("LocalThumbsPage umouted");
        return;
      }
      index += 30;
    }
  }

  Future<void> _loadAllFileSize() async {
    int totalSize = 0;
    for (var i = 0; i < _imageFiles.length; i++) {
      final imageFile = _imageFiles[i];
      imageFile.fileSize = (File(imageFile.path)).lengthSync();
      totalSize += imageFile.fileSize;
    }
    setState(() {
      _fileSize = bytesLengthToReadableSize(totalSize);
    });
  }

  static Future<Map<String, Size>> _loadImageSizes(List<ImageFile> imageFiles) async {
    final imageSizes = <String, Size>{};
    for (var i = 0; i < imageFiles.length; i++) {
      final imageFilePath = imageFiles[i].path;
      final file = File(imageFilePath);
      final sizeResult = ImageSizeGetter.getSizeResult(FileInput(file));
      imageSizes[imageFilePath] = sizeResult.size;
    }
    return imageSizes;
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (widget.onItemTap != null) {
            widget.onItemTap?.call(-1, '');
          } else {
            App.globalTo(
              () => ComicReadingPage.localComic(
                widget.dirPath,
                _title,
                initialPage: 1,
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
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Text(
                        bytesLengthToReadableSize(imageFile.fileSize),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
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
  final List<String> list;

  ImageFileList({
    required this.list,
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

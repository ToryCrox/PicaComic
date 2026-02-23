import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../foundation/local_history.dart';
import '../../network/download/download_manager.dart';
import '../../tools/image_size_getter.dart';
import '../../tools/io_tools.dart';
import '../../tools/prefs_helper.dart';
import 'package:worker_manager/worker_manager.dart';
import '../reader/comic_reading_page.dart';

class LocalThumbsPage extends StatefulWidget {
  const LocalThumbsPage({
    super.key,
    required this.dirPath,
    this.onItemTap,
    this.isEnableDelete = false,
    this.allDirPaths = const [],
  });

  // 目录路径
  final String dirPath;
  // 同级目录的所有路径，用于跳转上一篇/下一篇
  final List<String> allDirPaths;
  // 点击回调，如果不为空则使用此回调而不是默认跳转
  final void Function(int, String)? onItemTap;
  // 是否允许删除
  final bool isEnableDelete;

  @override
  State<LocalThumbsPage> createState() => _LocalThumbsPageState();
}

class _LocalThumbsPageState extends State<LocalThumbsPage> {
  final _imageFiles = <ImageFile>[];
  Map<String, ImageFile> _imageFileMap = {};

  String _title = '';
  bool _loading = true;

  final _selectedImages = <ImageFile>[];

  // 是否处于多选模式
  bool _isSelectedMode = false;

  final String _fileSize = '';

  // 排序方式
  late ComicFileSort _fileSort = ComicFileSort.values
          .asNameMap()[PrefsHelper.getString('local_comic_sort')] ??
      ComicFileSort.asc;

  bool get isReversed => _fileSort == ComicFileSort.desc;

  StreamSubscription? _imageSizeSubscription;

  final _scrollController = ScrollController();
  late final _observerController = GridObserverController(controller: _scrollController);

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

  // 加载目录下所有图片文件
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

  static Future<List<ImageFile>> Function() _buildLoadImagesTask(String dirPath) {
    return () => loadImagesFilePaths(dirPath);
  }

  // 加载图片并更新状态
  Future<void> _loadImages() async {
    final t1 = DateTime.now();
    final images = await workerManager.execute<List<ImageFile>>(_buildLoadImagesTask(widget.dirPath));
    //final images = await loadImagesFilePaths(widget.dirPath);
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
      _imageFileMap = _imageFiles.groupFoldBy((e) => e.path, (p, e) => e);

    });
    await Future.delayed(const Duration(milliseconds: 50));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _observerController.dispatchOnceObserve();
      }
    });
    //_loadAllImageSize();
  }

  // 加载所有图片的大小信息
  Future<void> _loadAllImageSize() async {
    final allImagePathList = _imageFiles.map((e) => e.path).toList();
    final imageFileMap = _imageFiles.groupFoldBy((e) => e.path, (p, e) => e);
    _imageSizeSubscription = computeImageSizes(allImagePathList).listen((e) {
      for(var imagePath in e.keys) {
        final sizeInfo = e[imagePath]!;
        final imageFile = imageFileMap[imagePath];
        if (imageFile != null) {
          imageFile.size = sizeInfo.size;
          imageFile.fileSize = sizeInfo.fileSize;
        }
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  final _hasViewImageSizes = <String>{};

  // 加载已显示图片的大小信息
  void _loadHasViewImageSizes(List<int> indexList)  {
    final imageFiles = indexList.map((i) => _imageFiles[i].path).toList();
    final needUpdate = imageFiles.where((i) => !_hasViewImageSizes.contains(i)).toList();
    if (needUpdate.isEmpty) {
      return;
    }
    _hasViewImageSizes.addAll(needUpdate);
    computeImageSizes(needUpdate).listen((e) {
      for(var imagePath in e.keys) {
        final sizeInfo = e[imagePath]!;
        final imageFile = _imageFileMap[imagePath];
        if (imageFile != null) {
          imageFile.size = sizeInfo.size;
          imageFile.fileSize = sizeInfo.fileSize;
        }
      }
      if (mounted) {
        setState(() {});
      }
    });
  }


  // 点击整理Pixiv图片
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

  /// 整理Pixiv图片逻辑
  /// 将散乱的已命名图片按画师ID和作品ID分类整理到文件夹中
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
      String userName = nameParts[0];
      String illustId = nameParts[1];
      String title = nameParts.sublist(2, nameParts.length - 1).join('_');
      if (userName.startsWith('[') && !userName.endsWith(']')) {
        userName = [nameParts[0], nameParts[1]].join('_');
        illustId = nameParts[2];
        title = nameParts.sublist(3, nameParts.length - 1).join('_');
      }

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
        // 8张以上，单独创建一个文件夹以作品标题命名
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
            onPressed: () async {
              setState(() {
                _fileSort = _fileSort == ComicFileSort.asc
                    ? ComicFileSort.desc
                    : ComicFileSort.asc;
                PrefsHelper.setString('local_comic_sort', _fileSort.name);
                final newImages = List.of(_imageFiles.reversed);
                _imageFiles.clear();
                _imageFiles.addAll(newImages);
              });
              await Future.delayed(const Duration(milliseconds: 50));
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _observerController.dispatchOnceObserve();
                }
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
            final history = await LocalHistoryManager().find(widget.dirPath);
            final initIndex = history?.pageIndex ?? 1;
            final isReversed = history?.isReversed == 1;
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
    return GridViewObserver(
      controller: _observerController,
      onObserve: (model) {
        final list = model.displayingChildModelList.map((e) => e.index).toList();
        _loadHasViewImageSizes(list);
        // final patchFiles = list.map((i) => _imageFiles[i]).toList();
        // computeImageSizes(imagePaths)
        // debugPrint("observe: $list");
      },
      child: GridView.builder(
        controller: _scrollController,
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
      ),
    );
  }

  // 右键菜单
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

  // 删除选中的图片
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
  // 图片列表
  final List<ImageFile> list;
  // 所在目录
  final String dirPath;

  const ImageFileList({
    required this.list,
    required this.dirPath,
  });
}

class ImageFile {
  // 图片路径
  final String path;
  // 图片尺寸
  Size? size;
  // 文件大小
  int fileSize;

  ImageFile({
    required this.path,
    this.size,
    this.fileSize = 0,
  });
}

enum ComicFileSort {
  // 升序
  asc,
  // 降序
  desc,
}

class _PixivImageInfo {
  final File file;
  // 画师名
  final String userName;
  // 作品ID
  final String illustId;
  // 标题
  final String title;
  // 分P
  final String part;
  // 扩展名
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

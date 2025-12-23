import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/kemono_network/kemono_main_network.dart';
import 'package:pica_comic/network/kemono_network/models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';


class KemonoComicPage extends BaseComicPage<KemonoPost> {
  @override
  final String id;
  @override
  final String? cover;

  const KemonoComicPage(this.id, this.cover, {super.key});

  @override
  String get tag => "Kemono Comic Page $id";

  @override
  String get sourceKey => "kemono";

  @override
  String get source => "Kemono";

  @override
  Future<Res<KemonoPost>> loadData() async {
    final parts = id.split('/');
    if (parts.length != 3) {
      return const Res(null, errorMessage: 'Invalid ID format');
    }
    final [service, userId, postId] = parts;
    return KemonoNetwork().getPostDetail(service, userId, postId);
  }

  @override
  String? get title => data?.title;

  @override
  String? get subTitle => data?.userName;

  @override
  String? get introduction => data?.content;

  @override
  Map<String, List<String>>? get tags => {
    "Service": [data?.service ?? ""],
    "User": [data?.userName ?? ""],
  };

  @override
  void tapOnTag(String tag, String key) {
    context.to(() => SearchResultPage(sourceKey: sourceKey, keyword: tag));
  }

  @override
  ThumbnailsData? get thumbnailsCreator {
    if (data == null || data!.thumbnailUrls.isEmpty) return null;
    return ThumbnailsData(
      data!.thumbnailUrls,
      (page) async => Res(data!.thumbnailUrls),
      1,
    );
  }

  @override
  Widget thumbnailImageBuilder(int index, String url) {
    return Image(
      image: CachedImageProvider(
        url,
        headers: KemonoNetwork.getImageHeaders(),
      ),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.error),
      ),
    );
  }

  @override
  EpsData? get eps => null; 

  @override
  Map<String, String> get headers => Map.from(KemonoNetwork.getImageHeaders());

  @override
  Widget buildCover(BuildContext context, ComicPageLogic logic, double height, double width) {
    return FutureBuilder<String?>(
      future: _getLocalCoverPath(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: FileImage(File(snapshot.data!)),
                fit: BoxFit.cover,
              )
            ),
          );
        }
        return super.buildCover(context, logic, height, width);
      },
    );
  }

  Future<String?> _getLocalCoverPath() async {
    try {
      final downloadId = DownloadManager().generateId(sourceKey, id);
      if (await DownloadManager().isExists(downloadId)) {
        final comic = await DownloadManager().getComicOrNull(downloadId);
        if (comic != null) {
          final path = comic.coverPath;
          if (path != null && await File(path).exists()) {
            return path;
          }
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  @override
  void read(History? history) async {
    if (data == null) return;
    history = await History.createIfNull(history, data!);
    if (data!.imageUrls.isNotEmpty) {
      App.globalTo(
            () => ComicReadingPage(
          CustomReadingData(
            data!.target,
            data!.title,
            ComicSource.find(sourceKey)!,
            null,
          ),
          history!.page,
          history.ep,
        ),
      );
    } else {
      showToast(message: "没有图片".tl);
    }
  }

  @override
  void download() async {
    final downloadId = DownloadManager().generateId(sourceKey, id);
    if (DownloadManager().downloading.any((e) => e.id == downloadId)) {
      showToast(message: "下载中".tl);
      return;
    }
    
    if (await DownloadManager().isExists(downloadId)) {
       showToast(message: "已下载".tl);
       return;
    }

    final comicData = ComicInfoData(
      data!.title,
      data!.userName,
      data!.cover,
      data!.content,
      tags ?? {},
      null,
      data!.imageUrls,
      null,
      0,
      null,
      sourceKey,
      id,
    );

    DownloadManager().addCustomDownload(comicData, [0]);
    showToast(message: "已加入下载队列".tl);
  }

  @override
  FavoriteItem toLocalFavoriteItem() {
    return FavoriteItem(
      target: id,
      name: data?.title ?? "Unknown",
      coverPath: data?.cover ?? "",
      author: data?.userName ?? "",
      type: FavoriteType('kemono'.hashCode),
      tags: [data?.service ?? ""],
    );
  }

  @override
  Future<bool> loadFavorite(KemonoPost data) async {
    return (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem())).isNotEmpty;
  }
  
  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: false, 
      needLoadFolderData: false,
      folders: const {}, 
      initialFolder: null, 
      favoriteOnPlatform: false, 
      localFavoriteItem: toLocalFavoriteItem(), 
      setFavorite: (b) {
         if (favorite != b) {
           favorite = b;
           update();
         }
      }, 
      selectFolderCallback: (folder, type) async {
        LocalFavoritesManager().addComic(folder, toLocalFavoriteItem());
        return const Res(true);
      })
    );
  }
  
  @override
  Widget? recommendationBuilder(KemonoPost data) => null;

  @override
  int? get pages => data?.imageUrls.length;

  @override
  Card? get uploaderInfo => null;

  @override
  String get downloadedId => DownloadManager().generateId(sourceKey, id);

  @override
  List<Widget>? get extraActionButtons {
    if (data == null) return null;
    final nonImageAttachments = data!.attachments.where((element) => !element.isImage).toList();
    if (nonImageAttachments.isEmpty) return null;

    return [
      buildActionItem(
        context, 
        "附件".tl, 
        Icons.attach_file, 
        () => _showDownloadAttachmentsDialog(context, nonImageAttachments)
      )
    ];
  }

  void _showDownloadAttachmentsDialog(BuildContext context, List<KemonoFile> files) {
    showDialog(
      context: context,
      builder: (context) => _DownloadAttachmentsDialog(
        files: files, 
        authorName: data?.userName ?? "Unknown",
        publishedDate: data?.published,
      ),
    );
  }
}

class _DownloadAttachmentsDialog extends StatefulWidget {
  final List<KemonoFile> files;
  final String authorName;
  final DateTime? publishedDate;

  const _DownloadAttachmentsDialog({
    required this.files,
    required this.authorName,
    this.publishedDate,
  });

  @override
  State<_DownloadAttachmentsDialog> createState() => _DownloadAttachmentsDialogState();
}

String? _lastAttachmentDownloadPath;

class _DownloadAttachmentsDialogState extends State<_DownloadAttachmentsDialog> {
  late List<bool> selected;
  bool downloading = false;
  double? progress;
  String? currentFile;
  late String? downloadPath;

  @override
  void initState() {
    super.initState();
    selected = List.generate(widget.files.length, (index) => true);
    downloadPath = _lastAttachmentDownloadPath;
  }

  Future<void> _changeDirectory() async {
    String? path = await getDirectoryPath();
    if (path != null) {
      setState(() {
        downloadPath = path;
      });
      _lastAttachmentDownloadPath = path;
    }
  }

  Future<void> _startDownload() async {
    final selectedFiles = <KemonoFile>[];
    for (int i = 0; i < widget.files.length; i++) {
      if (selected[i]) {
        selectedFiles.add(widget.files[i]);
      }
    }

    if (selectedFiles.isEmpty) {
      showToast(message: "未选择任何文件");
      return;
    }

    if (downloadPath == null) {
      await _changeDirectory();
    }

    if (downloadPath == null) return;

    setState(() {
      downloading = true;
    });

    final dio = Dio();
    
    // 目录结构: path/[AuthorName]/
    final targetDir = Directory("$downloadPath${Platform.pathSeparator}${_sanitizeFileName(widget.authorName)}");
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    
    // 日期前缀: [2025-12-25]
    String datePrefix = "";
    if (widget.publishedDate != null) {
      datePrefix = "[${widget.publishedDate!.year}-${widget.publishedDate!.month.toString().padLeft(2, '0')}-${widget.publishedDate!.day.toString().padLeft(2, '0')}]";
    } else {
      final now = DateTime.now();
      datePrefix = "[${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}]";
    }

    int successCount = 0;
    
    for (var file in selectedFiles) {
      if (!mounted) break;
      
      setState(() {
        currentFile = file.name;
        progress = 0;
      });

      final fileName = "$datePrefix${file.name}";
      final savePath = "${targetDir.path}${Platform.pathSeparator}$fileName";

      try {
        await dio.download(
          file.fullUrl, 
          savePath,
          onReceiveProgress: (count, total) {
            if (mounted && total > 0) {
              setState(() {
                progress = count / total;
              });
            }
          },
        );
        successCount++;
      } catch (e) {
        showToast(message: "下载失败: ${file.name}\n$e");
      }
    }

    if (mounted) {
      setState(() {
        downloading = false;
        currentFile = null;
        progress = null;
      });
      Navigator.of(context).pop();
      showToast(message: "下载完成: 成功 $successCount/${selectedFiles.length}");
    }
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("下载附件"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (downloading) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(currentFile != null ? "正在下载: $currentFile" : "准备中..."),
            ] else ...[
              SizedBox(
                height: 300,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.files.length,
                  itemBuilder: (context, index) {
                    final file = widget.files[index];
                    return CheckboxListTile(
                      value: selected[index],
                      onChanged: (v) {
                        setState(() {
                          selected[index] = v!;
                        });
                      },
                      title: Text(file.name),
                      subtitle: Text(file.path.split('.').last.toUpperCase()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      downloadPath == null ? "未选择下载目录" : "存储位置: $downloadPath",
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _changeDirectory, 
                    child: const Text("更改")
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!downloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text("下载"),
          ),
        ],
      ],
    );
  }
}

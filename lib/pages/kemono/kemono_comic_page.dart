import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/kemono_network/kemono_main_network.dart';
import 'package:pica_comic/network/kemono_network/models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/tools/prefs_helper.dart';


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
      ),
      buildActionItem(
        context, 
        "原网页".tl, 
        Icons.open_in_browser, 
        () => launchUrlString("https://kemono.cr/${data!.service}/user/${data!.userId}/post/${data!.id}", mode: LaunchMode.externalApplication)
      ),
    ];
  }

  void _showDownloadAttachmentsDialog(BuildContext context, List<KemonoFile> files) {
    showDialog(
      context: context,
      builder: (context) => _DownloadAttachmentsDialog(
        files: files, 
        authorName: data?.userName ?? "Unknown",
        publishedDate: data?.published,
        coverUrl: data?.cover ?? "", // 传递封面 URL
      ),
    );
  }
}

class _DownloadAttachmentsDialog extends StatefulWidget {
  final List<KemonoFile> files;
  final String authorName;
  final DateTime? publishedDate;
  final String coverUrl;

  const _DownloadAttachmentsDialog({
    required this.files,
    required this.authorName,
    this.publishedDate,
    required this.coverUrl,
  });

  @override
  State<_DownloadAttachmentsDialog> createState() => _DownloadAttachmentsDialogState();
}


class _DownloadAttachmentsDialogState extends State<_DownloadAttachmentsDialog> {
  late List<bool> selected;
  late String? downloadPath;

  @override
  void initState() {
    super.initState();
    selected = List.generate(widget.files.length, (index) => true);
    var path = PrefsHelper.getString("kemono_download_path");
    if (path.isNotEmpty) {
      downloadPath = path;
    } else {
      downloadPath = null;
    }
  }

  Future<void> _changeDirectory() async {
    String? path = await getDirectoryPath();
    if (path != null) {
      setState(() {
        downloadPath = path;
      });
      PrefsHelper.setString("kemono_download_path", path);
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

    // 使用 DownloadManager 进行下载
    DownloadManager().addKemonoAttachmentDownload(
      files: selectedFiles,
      downloadPath: downloadPath!,
      authorName: widget.authorName,
      postId: widget.files.first.path.split('/')[2], // 从路径中提取 postId
      publishedDate: widget.publishedDate,
      coverUrl: widget.coverUrl,
    );

    if (mounted) {
      Navigator.of(context).pop();
      showToast(message: "已加入下载队列 (${selectedFiles.length} 个文件)");
    }
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("取消"),
        ),
        FilledButton(
          onPressed: _startDownload,
          child: const Text("下载"),
        ),
      ],
    );
  }
}

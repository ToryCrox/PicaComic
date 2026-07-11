import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' show FileInfo;
import 'package:pica_comic/foundation/pica_image_manager.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/file_type.dart';
import 'package:pica_comic/tools/translations.dart';
import 'models/download_color_tag.dart';

import '../../base.dart';
import 'image_download_queue.dart';
import 'download_error_handler.dart';
import '../../foundation/local_repository_manager.dart';

abstract class DownloadedItem {
  ///漫画源
  DownloadType get type;

  ///漫画名
  String get name;

  ///章节
  List<String> get eps;

  ///已下载的章节
  List<int> get downloadedEps;

  ///标识符, 对于哔咔和eh, 直接使用其提供的漫画id, 禁漫开头加jm, hitomi开头加hitomi
  String get id;

  ///副标题, 通常为作者
  String get subTitle;

  ///大小
  double? get comicSize;

  ///下载的时间
  DateTime? time;

  /// tags
  List<String> get tags;

  ///Color tag
  DownloadColorTag? color;

  Map<String, dynamic> toJson();

  set comicSize(double? value);

  String directory = "";

  String get directoryPath {
    final downloadPath = downloadManager.path;
    if (downloadPath == null) return '';
    return Path.join(downloadPath, directory);
  }

  /// 获取封面路径
  String? get coverPath {
    final downloadPath = downloadManager.path;
    if (downloadPath == null) return null;
    return Path.join(downloadPath, directory, 'cover.webp');
  }
}

enum DownloadType {
  picacg,
  ehentai,
  jm,
  hitomi,
  htmanga,
  nhentai,
  other,
  favorite,
  local;

  ComicType toComicType() => switch (this) {
    picacg => ComicType.picacg,
    ehentai => ComicType.ehentai,
    jm => ComicType.jm,
    hitomi => ComicType.hitomi,
    htmanga => ComicType.htmanga,
    nhentai => ComicType.nhentai,
    other => ComicType.other,
    favorite => ComicType.other,
    local => ComicType.other,
  };
}

typedef DownloadProgressCallback = void Function();

typedef DownloadProgressCallbackAsync = Future<void> Function();

abstract class DownloadingTask with _TransferSpeedMixin {
  ///完成时调用
  final DownloadProgressCallback? onFinish;

  ///出现错误时调用
  final DownloadProgressCallback? onError;

  ///更新下载信息
  final DownloadProgressCallbackAsync? updateInfo;

  ///标识符, 对于哔咔和eh, 直接使用其提供的漫画id, 禁漫开头加jm, hitomi开头加hitomi
  final String id;

  ///类型
  DownloadType type;

  /// run function start will cause this increasing by 1
  ///
  /// this is used for preventing running multiple downloading function at the same time
  int _runtimeKey = 0;

  int _retryTimes = 0;

  String directory = '';

  String get path {
    var downloadPath = downloadManager.path!;
    return "$downloadPath/$directory";
  }

  /// headers for downloading cover
  Map<String, String> get headers => {};

  /// 图片下载队列（新的队列系统）
  ImageDownloadQueue? _imageQueue;

  /// 错误处理器
  final DownloadErrorHandler _errorHandler = DownloadErrorHandler();

  /// 已下载的图片数量
  int get downloadedPages => _imageQueue?.completedCount ?? 0;

  /// 失败的图片数量
  int get failedPages => _imageQueue?.failedCount ?? 0;

  // 为了向后兼容，保留这些旧的字段
  @Deprecated('Use _imageQueue instead')
  int _downloadedNum = 0;

  @Deprecated('Use _imageQueue instead')
  int _downloadingEp = 0;

  /// index of downloading episode
  ///
  /// Attention, this is used for array indexing, so it starts with 0
  @Deprecated('Use _imageQueue instead')
  int get downloadingEp => _downloadingEp;

  @Deprecated('Use _imageQueue instead')
  int index = 0;

  /// all image urls
  Map<int, List<String>>? links;

  int get allowedLoadingNumber => int.tryParse(appdata.settings[79]) ?? 6;

  bool duplicate = false;

  /// 用户手动暂停
  bool userPaused = false;

  /// 是否应该保存到数据库
  ///
  /// 默认为 true，表示下载完成后保存到"已下载"列表
  /// 设置为 false 的下载任务（如临时文件下载）不会被持久化
  bool shouldSaveToDatabase = true;

  DownloadingTask(
    this.onFinish,
    this.onError,
    this.updateInfo,
    this.id, {
    required this.type,
  });

  Future<void> downloadCover() async {
    final file = File(Path.join(path, 'cover.webp'));
    if (file.existsSync()) {
      return;
    }
    try {
      final headers = Map<String, String>.from(this.headers);
      headers['sourceKey'] = type.toComicType().name;
      final stream = picaImageManager.getImageFile(cover, headers: headers);
      await for (var fileResponse in stream) {
        if (fileResponse is FileInfo) {
          if (file.existsSync()) {
            file.deleteSync();
          }
          await file.create(recursive: true);
          await fileResponse.file.copy(file.path);
          return;
        }
      }
    } catch (e) {
      Log.e("Download Cover Failed: $e");
      rethrow;
    }
  }

  /// retry when error
  Future<void> retry() async {
    _retryTimes++;
    if (_retryTimes > 100) {
      onError?.call();
      _retryTimes = 0;
    } else {
      await Future.delayed(Duration(seconds: min(2 * _retryTimes, 8)));
      start();
    }
  }

  @mustCallSuper
  FutureOr<void> onStart() async {
    // directory 在 _addDownloadTask 中已经确保初始化
  }

  /// 章节下载完成时调用，保存增量数据到数据库
  ///
  /// [episodeIndex] 是 links Map 的 key，即章节编号（通常从1开始）
  Future<void> _onEpisodeDownloaded(int episodeIndex) async {
    if (!shouldSaveToDatabase) return;
    if (directory.trim().isEmpty) return;

    try {
      // 生成包含已完成章节的下载记录
      final downloadedItem = await toDownloadedItemPartial(
        _imageQueue?.getCompletedEpisodes().toList() ?? [episodeIndex],
      );

      if (downloadedItem != null) {
        await downloadManager.addToDb(downloadedItem, directory);
        Log.i(
          'DownloadingTask: Saved episode $episodeIndex for $id to database',
        );
      }
    } catch (e, s) {
      Log.e('DownloadingTask: Failed to save episode $episodeIndex: $e\n$s');
    }
  }

  /// 生成包含指定已完成章节的下载记录（用于增量保存）
  ///
  /// 子类必须实现此方法以支持逐章节保存
  /// [completedEpisodes] 是已完成章节的索引列表（links Map 的 key）
  ///
  /// 默认实现返回 null，表示不支持增量保存
  FutureOr<DownloadedItem?> toDownloadedItemPartial(
    List<int> completedEpisodes,
  ) {
    return null;
  }

  // 为了向后兼容保留旧的 _downloading Map，但不再使用
  @Deprecated('Use _imageQueue instead')
  final _downloading = <String, _ImageDownloadWrapper>{};

  /// 创建图片下载队列实例
  void _createImageQueue() {
    _imageQueue = ImageDownloadQueue(
      maxConcurrentDownloads: allowedLoadingNumber,
      downloadFunction: _downloadImageWrapper,
      onProgressUpdate: (downloaded, total) {
        // 更新下载进度
        updateInfo?.call();
        downloadManager.notifyListeners();

        // 更新通知
        notifications.sendProgressNotification(
          downloaded,
          total,
          "下载中".tl,
          "${downloadManager.downloading.length} Tasks",
        );
      },
      onAllCompleted: () {
        Log.i('DownloadingTask: All images downloaded for $id');
      },
      onFailed: (failedItems) {
        Log.e('DownloadingTask: ${failedItems.length} images failed for $id');
      },
      onEpisodeCompleted: (episodeIndex) {
        // 章节下载完成，保存到数据库
        _onEpisodeDownloaded(episodeIndex);
      },
    );
  }

  /// 流式获取图片链接并入队
  ///
  /// 子类可以覆写此方法以实现边解析边下载。
  /// 默认实现是调用 getLinks() 一次性获取所有链接并入队。
  Future<void> loadImages(ImageDownloadQueue queue) async {
    // 默认实现保持原有行为：一次性获取所有链接
    if (links == null || links!.isEmpty) {
      links = await getLinks();
    }

    // 将所有图片添加到队列
    for (var ep in links!.keys) {
      var urls = links![ep]!;
      for (var i = 0; i < urls.length; i++) {
        var downloadTo = haveEps ? "$path/$ep" : path;
        var basename = i.toString();

        var item = ImageDownloadQueueItem(
          url: urls[i],
          episodeIndex: ep,
          imageIndex: i,
          savePath: downloadTo,
          fileBaseName: basename,
        );

        queue.addImage(item);
      }
    }
  }

  /// 下载图片的包装器（用于 ImageDownloadQueue）
  Future<void> _downloadImageWrapper(ImageDownloadQueueItem item) async {
    // 创建下载包装器，使用 downloadImageWithContext 替代直接调用 downloadImage
    // 这样可以将图片的上下文信息（章节索引等）安全地传递给子类，避免并发时的竞态条件
    final wrapper = _ImageDownloadWrapper(
      () => downloadImageWithContext(item),
      item.savePath,
      item.fileBaseName,
      onData,
      null, // 不需要完成回调，由队列管理
    );

    // 等待下载完成
    await wrapper.wait();

    // 检查错误
    if (wrapper.error != null) {
      throw wrapper.error!;
    }

    if (!wrapper.isFinished) {
      throw Exception('Image download not finished');
    }
  }

  /// begin or continue downloading
  void start() async {
    _runtimeKey++;
    var currentKey = _runtimeKey;

    try {
      Log.i('DownloadingTask: Starting download for $id, path: $path');
      // 初始化
      await Directory(path).create(recursive: true);
      await onStart();
      if (_runtimeKey != currentKey) return;

      // 下载封面
      await downloadCover();

      // 初始化图片下载队列
      if (_imageQueue == null) {
        _createImageQueue();
      } else if (_imageQueue!.failedCount > 0) {
        // 如果有失败的任务，清空它们以便重试
        // 保留已完成的任务，避免重新下载
        Log.d(
          'DownloadingTask: Clearing ${_imageQueue!.failedCount} failed items, keeping ${_imageQueue!.completedCount} completed items',
        );
        _imageQueue!.clearFailed();
      }

      final queue = _imageQueue!;

      // 启动速度统计
      runRecorder();

      // 发送初始进度通知
      notifications.sendProgressNotification(
        downloadedPages,
        totalPages,
        "下载中".tl,
        "${downloadManager.downloading.length} Tasks",
      );

      // 设置流式模式：告诉队列我们稍后会添加图片，即使现在是空的也不要结束
      queue.setStreamMode(true);

      // 启动队列（注意：这里不立即 await，否则会死锁，因为 streamMode=true 且队列可能为空）
      final queueFuture = queue.start();

      try {
        // 加载图片链接（可以是流式的，也可以是一次性的）
        await loadImages(queue);
      } finally {
        // 完成加载，关闭流模式。
        // 此时如果队列为空（没加载到任何东西），或者任务都做完了，queueFuture 就会完成。
        queue.setStreamMode(false);
      }

      // 等待队列处理完成
      await queueFuture;

      // 检查是否被取消
      if (_runtimeKey != currentKey) return;

      // 检查下载结果
      if (queue.totalCount == 0) {
        throw StateError('No images were loaded for download');
      }

      if (queue.failedCount > 0) {
        // 有失败的图片，触发重试
        throw Exception('${queue.failedCount} images failed to download');
      }

      if (!queue.isAllCompleted) {
        throw StateError(
          'Image download queue finished with incomplete tasks: '
          '${queue.getStatusSummary()}',
        );
      }

      // 下载完成
      Log.i('DownloadingTask: Download completed for $id');
      stopRecorder();

      // 只有当这是队列中第一个任务时才调用 onFinish
      if (downloadManager.downloading.firstOrNull == this) {
        onFinish?.call();
      }
    } catch (e, s) {
      if (currentKey != _runtimeKey) return;

      Log.e("Download error for $id: $e\n$s");

      // 使用新的错误处理器
      final error = DownloadError.fromException(e, s);
      _errorHandler.handleError(
        error: error,
        retryCount: _retryTimes,
        retryAction: () async {
          _retryTimes++;
          if (_retryTimes > 100) {
            throw Exception('Max retries exceeded');
          }
          start();
        },
        onFinalFailure: (error) {
          Log.e(
            'DownloadingTask: Final failure for $id after $_retryTimes retries\n'
            'Error type: ${error.type}\n'
            'Error message: ${error.message}',
          );
          stopRecorder();
          onError?.call();
          _retryTimes = 0;
        },
      );
    }
  }

  void _stopAllTasks() {
    // 停止图片下载队列
    _imageQueue?.cancelAll();

    // 为了向后兼容，也清理旧的 _downloading Map
    var shouldRemove = <String>[];
    for (var entry in _downloading.entries) {
      if (!entry.value.isFinished) {
        entry.value.cancel();
        shouldRemove.add(entry.key);
      }
    }
    for (var key in shouldRemove) {
      _downloading.remove(key);
    }
  }

  /// pause downloading
  void pause() {
    _runtimeKey++;
    stopRecorder();
    notifications.endProgress();
    // 使用 pause 而不是 cancelAll (通过 _stopAllTasks)
    _imageQueue?.pause();

    // 对于旧的 _downloading map，如果有正在进行的任务，取消它们
    for (var entry in _downloading.entries) {
      if (!entry.value.isFinished) {
        entry.value.cancel();
      }
    }
  }

  /// stop downloading
  ///
  /// 取消下载时，只删除未完成的章节目录，保留已完成的章节
  Future<void> stop() async {
    _runtimeKey++;
    stopRecorder();
    _stopAllTasks();
    notifications.endProgress();
    if (directory.isEmpty) {
      showToast(message: '文件夹为空');
      Log.e("DownloadingTask: stop called with empty directory");
      return;
    }
    if (await downloadManager.isExists(id)) {
      if (links == null) return;
      var comicPath = "$path/";
      // 获取已完成的章节，这些章节不会被删除
      final completedEpisodes = _imageQueue?.getCompletedEpisodes() ?? <int>{};
      for (var ep in links!.keys.toList()) {
        // 只删除未完成的章节
        if (completedEpisodes.contains(ep)) continue;
        var directory = Directory(comicPath + ep.toString());
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    } else {
      var file = Directory(path);
      if (file.existsSync()) {
        file.delete(recursive: true);
      }
    }
  }

  Map<String, dynamic> toBaseMap() {
    Map<String, List<String>>? convertedData;
    if (links != null) {
      convertedData = {};
      links!.forEach((key, value) {
        convertedData![key.toString()] = value;
      });
    }

    return {
      "id": id,
      "type": type.index,
      "_downloadedNum": _downloadedNum,
      "_downloadingEp": _downloadingEp,
      "index": index,
      "links": convertedData,
      "directory": directory,
      "userPaused": userPaused,
      "finishedTasks": _downloading.entries
          .where((element) => element.value.isFinished)
          .map((e) => e.key)
          .toList(),
    };
  }

  Map<String, dynamic> toMap();

  DownloadingTask.fromMap(
    Map<String, dynamic> map,
    this.onFinish,
    this.onError,
    this.updateInfo,
  ) : id = map.optString("id"),
      type = DownloadType.values[map.optInt("type")],
      _downloadedNum = map.optInt("_downloadedNum"),
      _downloadingEp = map.optInt("_downloadingEp"),
      index = map.optInt("index"),
      links = null {
    var data = map.optMap("links");
    if (data.isNotEmpty) {
      links = {};
      data.forEach((key, value) {
        links![int.parse(key)] = List<String>.from(value);
      });
    }
    directory = map.optString("directory");
    var finishedTasksList = map.optStringList("finishedTasks");
    if (finishedTasksList.isNotEmpty) {
      for (var task in finishedTasksList) {
        _downloading[task] = _ImageDownloadWrapper.finished();
      }
    }
    userPaused = map["userPaused"] ?? false;
  }

  /// get all image links
  ///
  /// key - episode number(starts with 1), value - image links in this episode
  ///
  /// if platform don't have episode, this only have one key: 0.
  Future<Map<int, List<String>>> getLinks();

  /// whether this platform have episode
  bool get haveEps =>
      type != DownloadType.ehentai &&
      type != DownloadType.hitomi &&
      type != DownloadType.htmanga &&
      type != DownloadType.nhentai;

  /// 下载单张图片
  ///
  /// [link] 图片链接
  Stream<DownloadProgress> downloadImage(String link);

  /// 下载单张图片（带上下文信息）
  ///
  /// 子类可以覆写此方法以获取完整的下载上下文，包括章节索引等信息。
  /// 这对于需要根据章节信息进行特殊处理的平台（如禁漫的图片反混淆）非常重要。
  ///
  /// 默认实现直接调用 [downloadImage]，忽略上下文信息。
  Stream<DownloadProgress> downloadImageWithContext(
    ImageDownloadQueueItem item,
  ) {
    Log.d(
      "DownloadingTask: Downloading image with context: ${item.url} => ${item.savePath}",
    );
    return downloadImage(item.url);
  }

  ///获取封面链接
  String get cover;

  ///总共的图片数量
  int get totalPages => _imageQueue?.totalCount ?? (links?.totalLength ?? 0);

  // downloadedPages 已在前面定义

  ///标题
  String get title;

  @override
  bool operator ==(Object other) {
    if (other is DownloadingTask) {
      return id == other.id;
    } else {
      return false;
    }
  }

  @override
  int get hashCode => id.hashCode;

  FutureOr<DownloadedItem> toDownloadedItem();

  /// 获取每个章节的下载进度
  ///
  /// 返回 Map，key 是章节索引（links Map 的 key），value 是 `(downloaded, total)` 元组
  Map<int, ({int downloaded, int total})> get episodeProgress =>
      _imageQueue?.getEpisodeProgress() ?? {};

  /// 取消指定章节的下载
  ///
  /// [episodeIndex] 是 links Map 的 key，即章节编号
  void cancelEpisode(int episodeIndex) {
    _imageQueue?.cancelEpisode(episodeIndex);
    // 同步从 links 中移除，防止后续重试时再次加入队列
    links?.remove(episodeIndex);
  }

  /// 获取章节名称（子类可覆写）
  ///
  /// [episodeIndex] 是 links Map 的 key，即章节编号
  /// 默认返回 "第X章"
  String getEpisodeName(int episodeIndex) {
    return "第$episodeIndex章";
  }

  /// 检查任务是否处于暂停状态
  ///
  /// 当任务被用户手动暂停，或在队列首位但下载管理器未运行时，视为暂停状态
  bool isPaused() {
    if (userPaused) return true;
    if (downloadManager.downloading.isEmpty) return false;
    if (downloadManager.downloading.first != this) return false;
    return !downloadManager.isDownloading;
  }

  @override
  String toString() {
    return "$id: $downloadedPages/$totalPages";
  }
}

class _ImageDownloadWrapper {
  final Stream<DownloadProgress> Function()? streamCreator;

  final String path;

  final String fileBaseName;

  final void Function(int length)? onReceiveData;

  final void Function()? onFinished;

  Object? error;

  bool isFinished = false;

  bool _canceled = false;

  void cancel() {
    _canceled = true;
  }

  _ImageDownloadWrapper(
    this.streamCreator,
    this.path,
    this.fileBaseName,
    this.onReceiveData,
    this.onFinished,
  ) {
    listen();
  }

  _ImageDownloadWrapper.finished()
    : streamCreator = null,
      path = "",
      fileBaseName = "",
      onReceiveData = null,
      onFinished = null,
      isFinished = true;

  Future<void> listen() async {
    final dir = Directory(path);
    if (await dir.exists()) {
      final files = await dir.list().toList();
      final file = files.whereType<File>().toList().firstWhereOrNull(
        (e) => Path.basenameWithoutExtension(e.path) == fileBaseName,
      );
      isFinished = file != null;
      if (isFinished) {
        Log.i("DownloadManager Found cached image ${file?.path}");
      }
    }

    if (!isFinished) {
      var stream = streamCreator!();
      try {
        var last = 0;
        await for (var progress in stream) {
          if (_canceled) {
            for (var c in completers) {
              c.complete(this);
            }
            return;
          }
          onReceiveData?.call(progress.currentBytes - last);
          last = progress.currentBytes;
          if (progress.finished && !isFinished) {
            var data = progress.data ?? await progress.getFile().readAsBytes();
            if (data.isEmpty) {
              error = Exception("Download data is empty");
              return;
            }
            var type = detectFileType(data);
            var finalFile = File("$path/$fileBaseName${type.ext}");
            var tmpFile = File("${finalFile.path}.tmp");
            if (!await tmpFile.parent.exists()) {
              await tmpFile.parent.create(recursive: true);
            }
            await tmpFile.writeAsBytes(data);
            await tmpFile.rename(finalFile.path);
            isFinished = true;
            final cachingFile = progress.cachingFile;
            if (cachingFile != null) {
              CacheManager().delete(cachingFile.key);
            }
          }
        }
      } catch (e) {
        error = e;
      }
    }

    if (!isFinished && error == null) {
      error = Exception("Failed to download image");
    }
    onFinished?.call();
    for (var c in completers) {
      c.complete(this);
    }
  }

  var completers = <Completer<_ImageDownloadWrapper>>[];

  Future<_ImageDownloadWrapper> wait() {
    if (isFinished) {
      return Future.value(this);
    }
    var completer = Completer<_ImageDownloadWrapper>();
    completers.add(completer);
    return completer.future;
  }
}

abstract mixin class _TransferSpeedMixin {
  int _bytesSinceLastSecond = 0;

  int _currentSpeed = 0;

  int get currentSpeed => _currentSpeed;

  Timer? timer;

  void onData(int length) {
    if (timer == null) return;
    _bytesSinceLastSecond += length;
  }

  void onNextSecond(Timer t) {
    _currentSpeed = _bytesSinceLastSecond;
    _bytesSinceLastSecond = 0;
    downloadManager.notifyListeners();
  }

  void runRecorder() {
    if (timer != null) {
      timer!.cancel();
    }
    timer = Timer.periodic(const Duration(seconds: 1), onNextSecond);
  }

  void stopRecorder() {
    timer?.cancel();
    timer = null;
  }
}

/// 本地导入的漫画项
class LocalDownloadedItem extends DownloadedItem {
  @override
  double? comicSize;

  @override
  final List<int> downloadedEps;

  @override
  List<String> get eps => [];

  @override
  final String id;

  @override
  final String name;

  @override
  final String subTitle;

  @override
  final List<String> tags;

  @override
  DownloadType get type => DownloadType.local;

  /// 存储库名称（存储在JSON中）
  final String repositoryName;

  /// 封面图片的相对路径（存储在JSON中，相对于存储库根目录）
  final String? coverImagePath;

  LocalDownloadedItem({
    required this.comicSize,
    required this.downloadedEps,
    required this.id,
    required this.name,
    required this.subTitle,
    required this.tags,
    required this.repositoryName,
    this.coverImagePath,
    DownloadColorTag? color,
  }) {
    this.color = color;
  }

  @override
  Map<String, dynamic> toJson() => {
    "comicSize": comicSize,
    "downloadedEps": downloadedEps,
    "id": id,
    "name": name,
    "subTitle": subTitle,
    "tags": tags,
    "repositoryName": repositoryName,
    "coverImagePath": coverImagePath,
    "color": color?.name,
  };

  LocalDownloadedItem.fromJson(Map<String, dynamic> json)
    : comicSize = json["comicSize"],
      downloadedEps = List<int>.from(json["downloadedEps"] ?? []),
      id = json["id"],
      name = json["name"],
      subTitle = json["subTitle"] ?? "",
      tags = List<String>.from(json["tags"] ?? []),
      repositoryName = json["repositoryName"],
      coverImagePath = json["coverImagePath"] {
    color = DownloadColorTag.fromString(json["color"]);
  }

  @override
  String get directoryPath {
    // 对于本地漫画，directory存储的是相对路径（相对于存储库根目录）
    // 通过LocalRepositoryManager同步方法获取存储库路径，拼接完整路径
    if (directory.isEmpty) return '';
    final repoPath = LocalRepositoryManager().getRepositoryPathSync(
      repositoryName,
    );
    if (repoPath == null) return '';
    return Path.join(repoPath, directory);
  }

  @override
  String? get coverPath {
    // 对于本地漫画，coverImagePath存储的是相对路径（相对于漫画目录）
    // 完整路径 = directoryPath + coverImagePath
    if (coverImagePath == null) return null;
    final dirPath = directoryPath;
    if (dirPath.isEmpty) return null;
    return Path.join(dirPath, coverImagePath!);
  }
}

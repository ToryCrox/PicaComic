import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:signals/signals_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/foundation/database/download_database.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/pica_image_manager.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/download_queue_manager.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/eh_network/eh_errors.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/eh_network/get_gallery_id.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/download/favorite_download.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart' as hitomi;
import 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart';
import 'package:pica_comic/network/htmanga_network/models.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/kemono_network/kemono_attachment_download.dart';
import 'package:pica_comic/network/kemono_network/models.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/picacg_network/methods.dart'
    as picacg_network;
import 'package:pica_comic/network/picacg_network/models.dart' as picacg;
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/tools/debounce.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/foundation/local_repository_manager.dart';
import 'package:pica_comic/tools/image_utils.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:math';

typedef DownloadingCallback = void Function();

final downloadManager = DownloadManager._();

class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  ///使用单例模式
  static DownloadManager? cache;

  ///下载目录
  String? path;

  /// 漫画文件的存储目录。
  String get comicsPath => Path.join(path ?? '', 'comics');

  /// 漫画封面的集中存储目录。
  String get coversPath => Path.join(path ?? '', 'covers');

  /// 获取漫画封面的完整路径。
  ///
  /// 封面文件名只依赖来源和下载 ID，因此漫画目录重命名不会影响封面路径。
  String? getCoverPath(String id, DownloadType type) {
    if (path == null) return null;
    final fileName = buildDownloadCoverFileName(
      sourceKey: type.name,
      id: id,
    );
    return Path.join(coversPath, fileName);
  }

  /// 下载队列管理器（新的队列系统）
  late final DownloadQueueManager _queueManager = DownloadQueueManager(
    maxConcurrentTasks: 1,
  );

  ///下载队列（向后兼容，委托给 _queueManager）
  Queue<DownloadingTask> get downloading {
    return Queue.from(_queueManager.getAllTasks());
  }

  /// 获取正在运行的任务ID集合
  Set<String> get runningTaskIds => _queueManager.runningTaskIds;

  /// 获取等待队列的任务ID集合
  Set<String> get waitingTaskIds => _queueManager.waitingTaskIds;

  ///是否正在下载（委托给 _queueManager）
  bool get isDownloading => _queueManager.isRunning;

  set isDownloading(bool value) {
    // 为了向后兼容保留 setter，但不做任何操作
    // 实际状态由 _queueManager 管理
  }

  ///是否出现了错误
  bool _error = false;

  ///是否出现了错误
  bool get error => _error;

  ///是否初始化
  bool _runInit = false;

  final DownloadDatabase _db = DownloadDatabase();

  final List<VoidCallback> _listeners = [];

  /// 数据库操作锁，防止并发写入导致 SQLite 死锁
  static final Lock _dbLock = Lock();

  /// 用于通知已下载列表变化的 StreamController
  final StreamController<void> _comicsChangedController =
      StreamController<void>.broadcast();

  /// 当已下载列表变化时触发的 Stream (下载完成, 删除, 导入等)
  Stream<void> get onComicsChanged => _comicsChangedController.stream;

  /// 触发已下载列表变化通知
  void _notifyComicsChanged() {
    _comicsChangedController.add(null);
  }

  /// 用于通知标签变化的 StreamController (添加/移除标签时触发)
  final StreamController<void> _tagsChangedController =
      StreamController<void>.broadcast();

  /// 当标签变化时触发的 Stream (只更新标签相关数据，不重新加载漫画列表)
  Stream<void> get onTagsChanged => _tagsChangedController.stream;

  /// 触发标签变化通知
  void _notifyTagsChanged() {
    _tagsChangedController.add(null);
  }

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _queueManager.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _queueManager.removeListener(listener);
  }

  @override
  void notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  ///获取下载目录
  Future<void> _getPath() async {
    if (appdata.settings[22] == "") {
      final appPath = await getApplicationSupportDirectory();
      path = "${appPath.path}/download";
    } else {
      path = appdata.settings[22];
    }
    Log.d(() => 'DownloadManager: 下载路径设置为 $path');
    if (App.isIOS) {
      if (path!.startsWith('/var/mobile/Containers/Data/Application/')) {
        if (!Directory(path!).existsSync()) {
          final appPath = await getApplicationSupportDirectory();
          path = "${appPath.path}/download";
          Log.d(() => 'DownloadManager: iOS路径不存在，重置为 $path');
        }
      }
    }
    var dir = Directory(path!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      Log.d(() => 'DownloadManager: 创建下载目录 $path');
    }
    await Directory(comicsPath).create(recursive: true);
    await Directory(coversPath).create(recursive: true);
    if (App.isAndroid) {
      var file = File("$path/.nomedia");
      if (!file.existsSync()) {
        await file.create();
        Log.d(() => 'DownloadManager: 创建 .nomedia 文件');
      }
    }
  }

  ///更换下载目录
  Future<String> updatePath(String newPath, {bool transform = true}) async {
    Log.d(
      () => 'DownloadManager: 更换下载目录 newPath=$newPath, transform=$transform',
    );
    if (transform) {
      var source = Directory(path!);
      final appPath = await getApplicationSupportDirectory();
      var destination = Directory(
        newPath == "" ? "${appPath.path}${pathSep}download" : newPath,
      );
      try {
        Log.d(
          () =>
              'DownloadManager: 复制目录 from=${source.path} to=${destination.path}',
        );
        await copyDirectory(source, destination);
        for (var i in source.listSync()) {
          await i.delete(recursive: true);
        }
        Log.d(() => 'DownloadManager: 目录迁移成功');
      } catch (e) {
        Log.e('DownloadManager: 目录迁移失败 $e');
        return e.toString();
      }
    }

    _runInit = false;
    downloading.clear();
    await init();
    return "ok";
  }

  ///读取数据, 获取未完成的下载和已下载的漫画ID
  Future<void> _getInfo() async {
    //读取数据
    var file = File("$path${pathSep}newDownload.json");
    if (!file.existsSync()) {
      //await _saveInfo();
    } else {
      try {
        var json = const JsonDecoder().convert(await file.readAsString());
        for (var item in json["downloading"]) {
          final task = downloadingItemFromMap(
            item,
            _onFinish,
            _onError,
            _saveInfo,
          );
          // 直接调用 _addDownloadTask，统一处理 directory 初始化
          _addDownloadTask(task, skipSave: true, autoStart: false);
        }

        // 恢复完成后统一保存一次
        await _saveInfo();

        // 如果有任务被加载，记录一下，但不自动启动
        if (_queueManager.totalTasksCount > 0) {
          Log.i(
            'DownloadManager: Loaded ${_queueManager.totalTasksCount} pending download tasks from previous session',
          );
          notifyListeners();
        }
      } catch (e, s) {
        Log.e("IO Failed to read downloaded information\n$e\n$s");
        // file.deleteSync();
        // await _saveInfo();
      }
    }
  }

  Future<void> _initDb() async {
    Log.d(() => 'DB DownloadManager: 初始化数据库');
    await _db.init(dbPath: "$path/download.db");
    Log.d(() => 'DB DownloadManager: 数据库初始化完成');
  }

  @override
  void dispose() {
    _runInit = false;
    _queueManager.stopAll();
    super.dispose();
  }

  ///初始化下载管理器
  Future<void> init() async {
    if (_runInit) return;
    _runInit = true;

    // 初始化队列管理器
    _queueManager.removeListener(notifyListeners);
    _queueManager.addListener(notifyListeners);

    await _getPath();
    await _getInfo();
    await _initDb();
  }

  static final _saveInfoThrottle = Debounce(
    duration: const Duration(milliseconds: 200),
  );

  ///储存当前的下载队列信息, 每完成一张图片的下载调用一次
  Future<void> _saveInfo() async {
    _saveInfoThrottle.call(() async {
      notifyListeners();
      var data = <String, dynamic>{};
      data["downloading"] = <Map<String, dynamic>>[];
      // 从队列管理器获取所有任务
      for (var item in _queueManager.getAllTasks()) {
        data["downloading"].add(item.toMap());
      }
      final saveItem = SaveInfoItem(data, path ?? '');
      workerManager.execute(_buildSaveTask(saveItem));
      // var file = File("$path${pathSep}newDownload.json");
      // await file.writeAsString(const JsonEncoder().convert(data));
    });
  }

  static Future<void> Function() _buildSaveTask(SaveInfoItem item) {
    return () => saveToFile(item);
  }

  static Future<void> saveToFile(SaveInfoItem item) async {
    var file = File("${item.path}${pathSep}newDownload.json");
    await file.writeAsString(const JsonEncoder().convert(item.items));
  }

  /// move comic to first
  void moveToFirst(DownloadingTask item) {
    Log.d(() => 'DownloadManager: 移动任务到队首 id=${item.id}');
    _queueManager.moveToFirst(item.id);
    _saveInfo();
  }

  String generateId(String source, String id) {
    var comicSource = ComicSource.find(source)!;
    if (comicSource.matchBriefIdReg != null) {
      id = RegExp(comicSource.matchBriefIdReg!).firstMatch(id)!.group(1)!;
    }
    id = "$source-$id";
    return id;
  }

  /// 根据漫画源和漫画ID获取下载ID
  ///
  /// 下载ID的生成规则：
  /// - 对于哔咔和eh，直接使用其提供的漫画id
  /// - 禁漫开头加jm，hitomi开头加hitomi
  /// - 其他源使用 generateId 方法生成
  String getDownloadIdFromComicId(ComicType? comicType, String? comicID) {
    if (comicType == null || comicID == null || comicID.isEmpty) return '';

    switch (comicType) {
      case ComicType.picacg:
        return comicID;
      case ComicType.ehentai:
        // ehentai 的 comicID 是完整的链接，需要从中提取 gallery ID
        // 参考 eh_gallery_page.dart 中的 downloadedId 实现
        return getGalleryId(comicID);
      case ComicType.jm:
        return 'jm$comicID';
      case ComicType.hitomi:
        if (comicID.startsWith('hitomi')) return comicID;
        // 从完整链接或纯数字 ID 中提取画廊 ID
        final match = RegExp(r'(\d+)(?:\.html)?/?$').firstMatch(comicID);
        if (match != null) {
          return 'hitomi${match.group(1)}';
        }
        return comicID;
      case ComicType.htmanga:
        return 'Ht$comicID';
      case ComicType.nhentai:
        return comicID.startsWith('nhentai') ? comicID : 'nhentai$comicID';
      default:
        return generateId(comicType.name, comicID);
    }
  }

  /// 根据漫画源和下载ID还原原始漫画ID
  String getComicIdFromDownloadId(ComicType? comicType, String? downloadId) {
    if (comicType == null || downloadId == null || downloadId.isEmpty)
      return '';

    switch (comicType) {
      case ComicType.picacg:
      case ComicType.ehentai:
        return downloadId;
      case ComicType.nhentai:
        return downloadId.replaceFirst(RegExp(r'^nhentai'), '');
      case ComicType.jm:
        return downloadId.replaceFirst(RegExp(r'^jm'), '');
      case ComicType.hitomi:
        return downloadId.replaceFirst(RegExp(r'^hitomi'), '');
      case ComicType.htmanga:
        return downloadId.replaceFirst(RegExp(r'^Ht'), '');
      default:
        var prefix = "${comicType.name}-";
        if (downloadId.startsWith(prefix)) {
          return downloadId.substring(prefix.length);
        }
        return downloadId;
    }
  }

  ///当一个下载任务完成时, 调用此函数
  void _onFinish() async {
    // 通知队列管理器任务完成
    final tasks = _queueManager.getAllTasks();
    if (tasks.isNotEmpty) {
      final finishedTask = tasks.first;
      Log.d(
        () =>
            'DownloadManager: 任务完成 id=${finishedTask.id}, title=${finishedTask.title}',
      );
      _queueManager.onTaskFinished(finishedTask.id);

      // 只有标记为需要保存的下载任务才会保存到数据库
      if (finishedTask.shouldSaveToDatabase) {
        final downloadedItem = await finishedTask.toDownloadedItem();
        await addToDb(downloadedItem, finishedTask.directory);
      }
    }

    await _saveInfo();
    _notifyComicsChanged();

    // 队列管理器会自动调度下一个任务
    // 如果没有更多任务，会自动停止
    if (_queueManager.totalTasksCount == 0) {
      Log.d(() => 'DownloadManager: 所有下载任务已完成');
      notifications.endProgress();
    }
  }

  ///暂停下载
  void pause() {
    Log.d(() => 'DownloadManager: 暂停下载');
    _queueManager.pause();
    notifications.endProgress();
  }

  ///出现错误时调用此函数
  void _onError() {
    final currentTask = _queueManager.runningTask;
    final errorTask = currentTask ?? _queueManager.getAllTasks().firstOrNull;
    final taskId = errorTask?.id ?? 'unknown';
    Log.d(() => 'DownloadManager: 下载出错 taskId=$taskId');

    if (currentTask is EhDownloadingTask &&
        currentTask.downloadType == 0 &&
        EhOriginalGpRequiredException.matchesError(currentTask.lastError)) {
      currentTask.pauseReason = DownloadPauseReason.ehOriginalGpInsufficient;
      unawaited(_pauseEhTaskForGp(currentTask));
      return;
    }

    pause();
    _error = true;
    if (errorTask != null) {
      _queueManager.onTaskError(errorTask.id);
    }
    notifications.sendNotification("下载出错".tl, "点击查看详情".tl);
    notifyListeners();
  }

  /// 暂停 EH GP 不足的任务，同时保留已经下载的内容。
  Future<void> _pauseEhTaskForGp(EhDownloadingTask task) async {
    await _queueManager.pauseTask(task.id, preserveProgress: true);
    _queueManager.onTaskError(task.id);
    _saveInfo();
    if (!_queueManager.isRunning) {
      notifications.endProgress();
    }
    notifyListeners();
  }

  ///开始或继续下载
  void start() {
    Log.d(
      () => 'DownloadManager: 开始/继续下载，当前队列任务数=${_queueManager.totalTasksCount}',
    );
    _error = false;
    _queueManager.start();
  }

  ///取消指定的下载
  Future<void> cancel(String id) async {
    Log.d(() => 'DownloadManager: 取消下载任务 id=$id');
    await _queueManager.removeTask(id);
    _saveInfo();
    notifyListeners();

    if (_queueManager.totalTasksCount == 0) {
      notifications.endProgress();
    }
  }

  /// 暂停指定下载任务
  Future<void> pauseTask(String id) async {
    Log.d(() => 'DownloadManager: 暂停任务 id=$id');
    await _queueManager.pauseTask(id);
    _saveInfo();
  }

  /// 恢复指定下载任务
  void resumeTask(String id) {
    Log.d(() => 'DownloadManager: 恢复任务 id=$id');
    final task = _queueManager.findTask(id);
    task?.pauseReason = null;
    _queueManager.resumeTask(id);
    _saveInfo();
  }

  /// 取消指定下载任务的指定章节
  ///
  /// [id] 下载任务ID
  /// [episodeIndex] 章节索引（links Map 的 key）
  void cancelEpisode(String id, int episodeIndex) {
    Log.d(() => 'DownloadManager: 取消章节下载 id=$id, episode=$episodeIndex');
    _queueManager.cancelEpisode(id, episodeIndex);
    _saveInfo();
    notifyListeners();
  }

  // ==================== Local Favorite Management ====================

  /// 本地收藏状态的 Signal 缓存
  final Map<String, Signal<LocalFavoriteItem?>> localFavoriteCache = {};
  final Set<String> _pendingFavoriteTargets = {};
  bool _isBatchFavoriteQueryPending = false;

  void _enqueueFavoriteQuery(String path) {
    _pendingFavoriteTargets.add(path);
    if (!_isBatchFavoriteQueryPending) {
      _isBatchFavoriteQueryPending = true;
      Future.microtask(_processBatchFavoriteQuery);
    }
  }

  Future<void> _processBatchFavoriteQuery() async {
    await Future.delayed(const Duration(milliseconds: 10)); // 防止微任务合并过多
    if (_pendingFavoriteTargets.isEmpty) {
      _isBatchFavoriteQueryPending = false;
      return;
    }

    final targetsToQuery = _pendingFavoriteTargets.toList();
    _pendingFavoriteTargets.clear();
    _isBatchFavoriteQueryPending = false;

    try {
      // 通过单一查询批量处理(由于无原生批量借口，或者可以多次查询，SQLite性能良好)
      for (var path in targetsToQuery) {
        final result = await _db.getLocalFavorite(path);
        if (result != null) {
          localFavoriteCache[path]?.value = LocalFavoriteItem.fromMap(result);
        } else {
          localFavoriteCache[path]?.value = null; // 查询为空时，确认为 null
        }
      }
    } catch (e, s) {
      Log.e("Batch favorite query failed", stackTrace: s);
    }
  }

  /// 获取本地收藏状态的响应式 Signal。
  /// 用于 UI，特别是 Watch.builder 中调用。
  LocalFavoriteItem? findLocalFavoriteInCache(String path) {
    if (!localFavoriteCache.containsKey(path)) {
      // 占位并触发异步查询
      localFavoriteCache[path] = signal(null);
      _enqueueFavoriteQuery(path);
    }
    return localFavoriteCache[path]!.value;
  }

  Future<void> addLocalFavorite(String path, {int sortOrder = 0}) async {
    await _db.addOrUpdateLocalFavorite(path, sortOrder: sortOrder);

    // 同步更新或新增 Signal
    final newItem = LocalFavoriteItem(
      path,
      sortOrder,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (localFavoriteCache.containsKey(path)) {
      localFavoriteCache[path]!.value = newItem;
    } else {
      localFavoriteCache[path] = signal(newItem);
    }
  }

  Future<void> updateLocalFavoriteSortOrder(String path, int sortOrder) async {
    await _db.updateLocalFavoriteSortOrder(path, sortOrder);

    // 同步更新 Signal
    if (localFavoriteCache.containsKey(path)) {
      final oldItem = localFavoriteCache[path]!.value;
      if (oldItem != null) {
        localFavoriteCache[path]!.value = LocalFavoriteItem(
          path,
          sortOrder,
          oldItem.time,
        );
      } else {
        _enqueueFavoriteQuery(path);
      }
    }
  }

  Future<void> deleteLocalFavorite(String path) async {
    await _db.deleteLocalFavorite(path);

    // 同步清除 Signal
    if (localFavoriteCache.containsKey(path)) {
      localFavoriteCache[path]!.value = null;
    }
  }

  Future<List<Map<String, Object?>>> getAllLocalFavorites() async {
    return _db.getAllLocalFavorites();
  }

  Future<Map<String, Object?>?> getLocalFavorite(String path) async {
    return _db.getLocalFavorite(path);
  }

  // ====================================================================

  Future<DownloadedItem?> getComicOrNull(String id) async {
    return _getComicWithDb(id);
  }

  ///删除已下载的漫画
  Future<void> delete(List<String> ids) async {
    for (var id in ids) {
      Log.i("IO delete comic: $id");
      final item = await getComicOrNull(id);
      final dirPath = await getFullDirectory(id);
      await _deleteFromDb(id);
      if (dirPath.isNotEmpty) {
        var comic = Directory(dirPath);
        try {
          Log.d('delete comic path: $dirPath');
          await comic.delete(recursive: true);
        } catch (e, s) {
          showToast(message: 'delete error $dirPath');
          Log.e('delete comic error $e', stackTrace: s);
          if (e is PathNotFoundException) {
            //忽略
          } else {
            rethrow;
          }
        }
      } else {
        Log.w("IO delete comic error: comic not found $id");
      }

      if (item != null && item.type != DownloadType.local) {
        final coverPath = item.coverPath;
        if (coverPath != null) {
          try {
            final coverFile = File(coverPath);
            if (await coverFile.exists()) {
              await coverFile.delete();
            }
          } catch (e, s) {
            Log.e('delete comic cover error $coverPath: $e', stackTrace: s);
          }
        }
      }
    }
    _notifyComicsChanged();
  }

  Future<void> deleteWithoutFile(List<String> ids) async {
    Log.d(() => 'DB DownloadManager: 删除数据库记录(不删除文件) ids=$ids');
    for (var id in ids) {
      await _deleteFromDb(id);
    }
    _notifyComicsChanged();
  }

  /// 删除漫画的指定章节
  ///
  /// 删除章节目录并重新计算漫画文件大小
  ///
  /// 参数：
  /// - comic: 漫画对象
  /// - ep: 章节索引（从0开始）
  ///
  /// 返回：
  /// - 成功返回 null，失败返回错误信息
  Future<String?> deleteEpisode(DownloadedItem comic, int ep) async {
    try {
      Log.d(() => 'DownloadManager: 删除章节 comicId=${comic.id}, episode=$ep');
      // 检查是否只剩一个章节，不允许删除最后一个章节
      if (comic.downloadedEps.length == 1) {
        Log.d(() => 'DownloadManager: 无法删除最后一个章节 comicId=${comic.id}');
        return "Delete Error: only one downloaded episode";
      }

      // 获取漫画目录的完整路径
      final fullPath = Path.join(comicsPath, comic.directory);

      // 删除指定章节的目录（章节编号从1开始，所以需要 +1）
      if (Directory("$fullPath/${ep + 1}").existsSync()) {
        Directory("$fullPath/${ep + 1}").deleteSync(recursive: true);
        Log.d(() => 'DownloadManager: 删除章节目录 $fullPath/${ep + 1}');
      }

      // 重新计算漫画文件大小（异步操作，不阻塞主线程）
      var size = await getComicStorageSize(comic);

      // 从已下载章节列表中移除该章节
      comic.downloadedEps.remove(ep);

      // 更新漫画大小
      comic.comicSize = size;

      // 更新数据库
      Log.d(
        () => 'DB DownloadManager: 更新漫画信息 comicId=${comic.id}, newSize=$size',
      );
      await addToDb(comic, comic.directory);
      await clearAiTranslationCompleted(comic.id);
      return null;
    } catch (e, s) {
      Log.e("IO $e/n$s");
      return e.toString();
    }
  }

  /// 更新漫画文件大小
  ///
  /// 计算漫画目录的实际文件大小，并在大小发生变化时更新到数据库
  ///
  /// 参数：
  /// - comic: 待更新的漫画对象
  ///
  /// 返回：
  /// - 更新后的文件大小（MB），如果出错则返回 0
  Future<double> updateComicSize(DownloadedItem comic) async {
    try {
      // 获取漫画目录的完整路径
      // 使用 comic.directoryPath 以支持本地漫画（其路径基于存储库，而非下载目录）
      // 异步计算目录大小（不阻塞主线程）
      final size = await getComicStorageSize(comic);

      // 获取旧的文件大小
      final oldSize = comic.comicSize ?? 0;

      // 更新漫画对象的大小属性
      comic.comicSize = size;

      // 只有当文件大小发生变化时才更新数据库
      // 使用 0.01 MB 作为阈值，避免浮点数精度问题
      if ((size - oldSize).abs() > 0.01) {
        Log.d(
          () =>
              'DownloadManager: 漫画大小变化 comicId=${comic.id}, oldSize=$oldSize MB, newSize=$size MB',
        );
        await updateSize(comic.id, size);
      }

      return size;
    } catch (e) {
      Log.e("IO ${e.toString()}");
      return 0;
    }
  }

  /// 获取漫画目录和集中封面的总大小，单位为 MB。
  Future<double> getComicStorageSize(DownloadedItem comic) async {
    final dirPath = comic.directoryPath;
    var size = await Directory(dirPath).getMBSize();
    if (comic.type == DownloadType.local) return size;

    final coverPath = comic.coverPath;
    if (coverPath != null) {
      final coverFile = File(coverPath);
      if (await coverFile.exists()) {
        size += await coverFile.length() / 1024 / 1024;
      }
    }
    return size;
  }

  /// 获取漫画章节的长度, 适用于有章节的漫画
  Future<int> getEpLength(String id, int ep) async {
    final fullDirPath = await getFullDirectory(id);
    var directory = Directory("$fullDirPath/$ep");
    var files = directory.list();
    return files.length;
  }

  /// 获取漫画的长度, 适用于无章节的漫画
  Future<int> getComicLength(String id) async {
    final fullDirPath = await getFullDirectory(id);
    var directory = Directory(fullDirPath);
    var files = directory.list();
    return await files.length - 1;
  }

  ///获取图片, 对于无章节的漫画, ep参数为0
  Future<File> getImage(String id, int ep, int index) async {
    final fullDirPath = await getFullDirectory(id); // 这里需要修改为同步方法或者重构调用处
    String downloadPath;
    if (ep == 0) {
      downloadPath = fullDirPath;
    } else {
      downloadPath = Path.join(fullDirPath, ep.toString());
    }
    for (var file in Directory(downloadPath).listSync()) {
      if (file.uri.pathSegments.last.replaceFirst(RegExp(r"\..+"), "") ==
          index.toString()) {
        return file as File;
      }
    }
    throw Exception("File not found");
  }

  Future<File?> getDownloadImageOrNull(String title, int ep, int index) async {
    final directory = findValidDirectoryName(path!, title);
    String downloadPath;
    if (ep == 0) {
      downloadPath = Path.join(comicsPath, directory);
    } else {
      downloadPath = Path.join(comicsPath, directory, ep.toString());
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) return null;
    return dir.listSync().whereType<File>().toList().firstWhereOrNull(
      (e) => Path.basenameWithoutExtension(e.path) == index.toString(),
    );
  }

  Future<String> getImageDirectory(String id, int ep) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = Path.join(comicsPath, dirName);
    } else {
      downloadPath = Path.join(comicsPath, dirName, ep.toString());
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    return dir.absolute.path;
  }

  Future<List<String>> getAllImageFileList(String id, int ep) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = Path.join(comicsPath, dirName);
    } else {
      downloadPath = Path.join(comicsPath, dirName, ep.toString());
    }
    final dir = Directory(downloadPath);
    if (!(await dir.exists())) {
      return [];
    }
    final files = await dir.list(recursive: true).toList();
    sFileRelativeFromPath = downloadPath;
    return files
        .where(
          (e) =>
              predictImageFile(e) && !Path.basename(e.path).startsWith("cover"),
        )
        .sortedByName()
        .map((e) => e.absolute.path)
        .toList();
  }

  Future<List<String>> getAllImagesByDir(String dirPath) async {
    final dir = Directory(dirPath);
    if (!(await dir.exists())) {
      return [];
    }
    final files = await dir.list(recursive: true).toList();
    sFileRelativeFromPath = Path.normalize(dirPath);
    return files
        .whereType<File>()
        .where(predictImageFile)
        .sortedByName()
        .map((e) => e.absolute.path)
        .toList();
  }

  Future<File> getImageAsync(String id, int ep, int index) async {
    String downloadPath;
    final dirName = await getDirectoryName(id);
    if (ep == 0) {
      downloadPath = Path.join(comicsPath, dirName);
    } else {
      downloadPath = Path.join(comicsPath, dirName, ep.toString());
    }
    var fileName = _downloadedFileName["$id$ep$index"];
    if (fileName != null) {
      final file = File(Path.join(downloadPath, fileName));
      if (await file.exists()) {
        return file;
      }
    }
    await for (var file in Directory(downloadPath).list()) {
      var i = file.uri.pathSegments.last.replaceFirst(RegExp(r"\..+"), "");
      if (i.isNum) {
        if (_downloadedFileName.length > 2000) {
          _downloadedFileName.remove(_downloadedFileName.keys.first);
        }
        _downloadedFileName["$id$ep$i"] = file.name;
      }
    }
    if (_downloadedFileName["$id$ep$index"] == null) {
      throw Exception("File not found");
    }
    return File(
      Path.join(downloadPath, _downloadedFileName["$id$ep$index"]!),
    );
  }

  static final _downloadedFileName = <String, String>{};

  ///获取封面, 所有漫画源通用
  Future<File> getCoverAsync(String id) async {
    return getCover(id);
  }

  Future<File> getCover(String id) async {
    final item = await getComicOrNull(id);
    final coverPath = item?.coverPath ??
        getCoverPath(id, item?.type ?? _inferDownloadType(id));
    return File(coverPath ?? '');
  }

  /// 根据下载 ID 推断内置漫画源类型，用于兼容没有数据库记录的调用方。
  DownloadType _inferDownloadType(String id) {
    if (id.startsWith('jm')) return DownloadType.jm;
    if (id.startsWith('hitomi')) return DownloadType.hitomi;
    if (id.startsWith('nhentai')) return DownloadType.nhentai;
    if (id.startsWith('Ht')) return DownloadType.htmanga;
    if (id.contains('-')) return DownloadType.other;
    if (id.isNum) return DownloadType.ehentai;
    return DownloadType.picacg;
  }
}

DownloadingTask downloadingItemFromMap(
  Map<String, dynamic> map,
  void Function() whenFinish,
  void Function() whenError,
  Future<void> Function() updateInfo,
) {
  switch (map["type"]) {
    case 0:
      return PicDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 1:
      return EhDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 2:
      return JmDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 3:
      return HitomiDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 4:
      return HtDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 5:
      return NhentaiDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 6:
      throw "Custom downloading task is no longer supported";
    case 7:
      return FavoriteDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    case 8:
      return KemonoAttachmentDownloadingTask.fromMap(
        map,
        whenFinish,
        whenError,
        updateInfo,
        map["id"],
      );
    default:
      throw UnimplementedError();
  }
}

extension AddDownloadExt on DownloadManager {
  /// 添加下载任务的通用方法（消除重复代码）
  ///
  /// [skipSave] 跳过保存，用于批量添加任务时提高性能
  /// [autoStart] 是否自动开始下载
  void _addDownloadTask(
    DownloadingTask task, {
    bool skipSave = false,
    bool autoStart = true,
  }) async {
    Log.d(() => 'DownloadManager: 添加下载任务 id=${task.id}, title=${task.title}');

    // 确保 directory 不为空
    if (task.directory.trim().isEmpty) {
      // 尝试从数据库恢复
      if (await isExists(task.id)) {
        task.directory = await getDirectoryName(task.id);
      }
      // 如果还是空，生成新的
      if (task.directory.trim().isEmpty) {
        task.directory = _generateDirectoryName(task);
        // Directory(task.path).createSync(recursive: true);
      }
    }

    _queueManager.enqueue(task);
    if (!skipSave) {
      _saveInfo();
    }
    notifyListeners();
    if (!isDownloading && autoStart) {
      start();
    }
  }

  /// 生成任务的目录名称，格式: [type][id]title
  ///
  /// 使用 title 生成目录名，如果失败则使用 id 作为后备，确保永远不为空
  String _generateDirectoryName(DownloadingTask task) {
    try {
      return _buildDirectoryName(task.type.name, task.id, task.title);
    } catch (e) {
      Log.w('DownloadManager: sanitizeFileName 失败，使用 id: $e');
      return _buildDirectoryName(task.type.name, task.id, task.id);
    }
  }

  /// 构建目录名称的通用方法，格式: [type][id]title
  String _buildDirectoryName(String type, String id, String title) {
    var maxLength = maxDownloadDirectoryNameBytes;
    if (App.isWindows && path != null) {
      // 为章节目录、图片文件名和分隔符预留 60 个字符。
      const reservedPathLength = 60;
      final pathLimitedLength =
          260 - comicsPath.length - reservedPathLength - 1;
      maxLength = min(maxLength, pathLimitedLength);
    }
    return buildDownloadDirectoryName(
      type: type,
      id: id,
      title: title,
      maxLength: maxLength,
    );
  }

  ///添加哔咔漫画下载
  void addPicDownload(picacg.ComicItem comic, List<int> downloadEps) {
    final task = PicDownloadingTask(
      comic,
      downloadEps,
      _onFinish,
      _onError,
      _saveInfo,
      comic.id,
    );
    _addDownloadTask(task);
  }

  ///添加E-Hentai下载
  /// 重复的英语: duplicateEnglishName
  /// - downloadEps: 下载的章节
  void addEhDownload(Gallery gallery, [int type = 0]) {
    final id = getGalleryId(gallery.link);
    final task = EhDownloadingTask(
      gallery,
      _onFinish,
      _onError,
      _saveInfo,
      id,
      type,
    );
    _addDownloadTask(task);
  }

  ///添加禁漫下载
  void addJmDownload(JmComicInfo comic, List<int> downloadEps) {
    final task = JmDownloadingTask(
      comic,
      downloadEps,
      _onFinish,
      _onError,
      _saveInfo,
      "jm${comic.id}",
    );
    _addDownloadTask(task);
  }

  ///添加Hitomi下载
  void addHitomiDownload(hitomi.HitomiComic comic, String cover, String link) {
    final id = "hitomi${comic.id}";
    final task = HitomiDownloadingTask(
      comic,
      cover,
      link,
      _onFinish,
      _onError,
      _saveInfo,
      id,
    );
    _addDownloadTask(task);
  }

  ///添加绅士漫画下载
  void addHtDownload(HtComicInfo comic) {
    final id = "Ht${comic.id}";
    final task = HtDownloadingTask(comic, _onFinish, _onError, _saveInfo, id);
    _addDownloadTask(task);
  }

  void addNhentaiDownload(NhentaiComic comic) {
    final id = "nhentai${comic.id}";
    final task = NhentaiDownloadingTask(
      comic,
      _onFinish,
      _onError,
      _saveInfo,
      id,
    );
    _addDownloadTask(task);
  }

  @Deprecated("Custom download is no longer supported.")
  void addCustomDownload(ComicInfoData comic, List<int> downloadEps) {
    throw "Custom download is no longer supported";
  }

  void addFavoriteDownload(FavoriteItem comic) {
    var id = switch (comic.type.key) {
      0 => comic.target,
      1 => getGalleryId(comic.target),
      2 => "jm${comic.target}",
      3 => "hitomi${RegExp(r"\d+(?=\.html)").firstMatch(comic.target)![0]!}",
      4 => "Ht${comic.target}",
      6 => "nhentai${comic.target}",
      _ =>
        comic.type.comicSource == null
            ? throw "Comic Source Not Found"
            : generateId(comic.type.comicSource!.key.name, comic.target),
    };
    final task = FavoriteDownloadingTask(
      comic,
      _onFinish,
      _onError,
      _saveInfo,
      id,
    );
    _addDownloadTask(task);
  }

  /// 添加 Kemono 附件下载
  void addKemonoAttachmentDownload({
    required List<KemonoFile> files,
    required String downloadPath,
    required String authorName,
    required String postId,
    DateTime? publishedDate,
    String? coverUrl,
  }) {
    final id =
        "kemono-attachment-$postId-${DateTime.now().millisecondsSinceEpoch}";
    final task = KemonoAttachmentDownloadingTask(
      files: files,
      customDownloadPath: downloadPath,
      authorName: authorName,
      postId: postId,
      publishedDate: publishedDate,
      coverUrl: coverUrl,
      onFinish: _onFinish,
      onError: _onError,
      updateInfo: _saveInfo,
      id: id,
    );
    _addDownloadTask(task);
  }

  bool _isNetworkDownloadedComic(DownloadedItem comic) {
    return switch (comic.type) {
      DownloadType.picacg ||
      DownloadType.ehentai ||
      DownloadType.jm ||
      DownloadType.hitomi ||
      DownloadType.htmanga ||
      DownloadType.nhentai => true,
      DownloadType.other ||
      DownloadType.favorite ||
      DownloadType.local => false,
    };
  }

  /// 是否支持重新下载。
  bool canRedownload(DownloadedItem comic) => _isNetworkDownloadedComic(comic);

  /// 是否支持更新封面。
  bool canRefreshCover(DownloadedItem comic) =>
      _isNetworkDownloadedComic(comic);

  /// 批量重新下载漫画，可选择覆盖已有文件或只补齐缺失图片。
  Future<DownloadBatchResult> redownloadComics(
    List<DownloadedItem> comics, {
    bool overwriteExisting = false,
  }) async {
    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    final errors = <String>[];

    for (final comic in comics) {
      if (!canRedownload(comic)) {
        skippedCount++;
        continue;
      }
      if (_queueManager.getAllTasks().any((task) => task.id == comic.id)) {
        skippedCount++;
        continue;
      }

      try {
        final context = await _buildLatestDownloadContext(comic);
        context.task.directory = await _resolveDownloadDirectory(comic);
        context.task.overwriteExistingFiles = overwriteExisting;
        _queueManager.enqueue(context.task);
        // 重新下载可能补充未翻译的新图片，旧的完成标记立即失效。
        await clearAiTranslationCompleted(comic.id);
        successCount++;
      } catch (e, s) {
        failedCount++;
        errors.add("${comic.name}: $e");
        Log.e(
          "DownloadManager: 重新下载失败 id=${comic.id}, error=$e",
          stackTrace: s,
        );
      }
    }

    if (successCount > 0) {
      await _saveInfo();
      notifyListeners();
      if (!isDownloading) {
        start();
      }
    }

    return DownloadBatchResult(
      successCount: successCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      errors: errors,
    );
  }

  /// 批量更新漫画封面。
  Future<DownloadBatchResult> refreshComicCovers(
    List<DownloadedItem> comics,
  ) async {
    var successCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    final errors = <String>[];

    for (final comic in comics) {
      if (!canRefreshCover(comic)) {
        skippedCount++;
        continue;
      }

      try {
        final directory = await _resolveDownloadDirectory(comic);
        if (directory.isEmpty) {
          skippedCount++;
          continue;
        }

        final context = await _buildLatestDownloadContext(comic);
        context.task.directory = directory;
        context.item.directory = directory;
        context.item.time = comic.time;
        context.item.color = comic.color;

        await _refreshCoverFile(comic, context.task);
        await addToDb(context.item, directory, comic.time);
        successCount++;
      } catch (e, s) {
        failedCount++;
        errors.add("${comic.name}: $e");
        Log.e(
          "DownloadManager: 更新封面失败 id=${comic.id}, error=$e",
          stackTrace: s,
        );
      }
    }

    if (successCount > 0) {
      _notifyComicsChanged();
    }

    return DownloadBatchResult(
      successCount: successCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      errors: errors,
    );
  }

  Future<String> _resolveDownloadDirectory(DownloadedItem comic) async {
    if (comic.directory.trim().isNotEmpty) {
      return comic.directory;
    }
    return getDirectoryName(comic.id);
  }

  Future<void> _refreshCoverFile(
    DownloadedItem oldComic,
    DownloadingTask task,
  ) async {
    await Directory(task.path).create(recursive: true);

    final coverPath = getCoverPath(task.id, task.type);
    if (coverPath == null) {
      throw StateError('Download path is not initialized');
    }
    final coverFile = File(coverPath);
    if (await coverFile.exists()) {
      await coverFile.delete();
    }

    final coverUrls = {
      _getStoredCoverUrl(oldComic),
      task.cover,
    }.where((url) => url.isNotEmpty);
    for (final url in coverUrls) {
      await _deleteCoverCache(url);
    }

    await task.downloadCover();
  }

  Future<void> _deleteCoverCache(String url) async {
    try {
      await CacheManager().delete(url);
    } catch (e) {
      Log.w("DownloadManager: 删除图片缓存失败 $url, $e");
    }
    try {
      await picaImageManager.removeFile(url);
    } catch (e) {
      Log.w("DownloadManager: 删除封面缓存失败 $url, $e");
    }
  }

  String _getStoredCoverUrl(DownloadedItem comic) {
    return switch (comic.type) {
      DownloadType.picacg => picacg_network.getImageUrl(
        (comic as DownloadedComic).comicItem.thumbUrl,
      ),
      DownloadType.ehentai =>
        (comic as DownloadedGallery).gallery.coverPath.replaceFirst(
          's.exhentai.org',
          'ehgt.org',
        ),
      DownloadType.jm => (comic as DownloadedJmComic).comic.cover,
      DownloadType.hitomi => (comic as DownloadedHitomiComic).cover,
      DownloadType.htmanga => (comic as DownloadedHtComic).comic.cover,
      DownloadType.nhentai => (comic as NhentaiDownloadedComic).cover,
      DownloadType.other || DownloadType.favorite || DownloadType.local => '',
    };
  }

  Future<({DownloadedItem item, DownloadingTask task})>
  _buildLatestDownloadContext(DownloadedItem comic) async {
    return switch (comic.type) {
      DownloadType.picacg => await _buildPicacgDownloadContext(
        comic as DownloadedComic,
      ),
      DownloadType.ehentai => await _buildEhentaiDownloadContext(
        comic as DownloadedGallery,
      ),
      DownloadType.jm => await _buildJmDownloadContext(
        comic as DownloadedJmComic,
      ),
      DownloadType.hitomi => await _buildHitomiDownloadContext(
        comic as DownloadedHitomiComic,
      ),
      DownloadType.htmanga => await _buildHtDownloadContext(
        comic as DownloadedHtComic,
      ),
      DownloadType.nhentai => await _buildNhentaiDownloadContext(
        comic as NhentaiDownloadedComic,
      ),
      DownloadType.other ||
      DownloadType.favorite ||
      DownloadType.local => throw UnsupportedError("不支持该漫画类型"),
    };
  }

  Future<({DownloadedItem item, DownloadingTask task})>
  _buildPicacgDownloadContext(DownloadedComic comic) async {
    final res = await picacg_network.PicacgNetwork().getComicInfo(comic.id);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final epsCount = latest.eps.isNotEmpty
        ? latest.eps.length
        : latest.epsCount;
    final downloadEps = List<int>.generate(epsCount, (index) => index);
    final item = DownloadedComic(
      latest,
      latest.eps,
      comic.comicSize,
      List<int>.from(comic.downloadedEps),
      color: comic.color,
    );
    final task = PicDownloadingTask(
      latest,
      downloadEps,
      _onFinish,
      _onError,
      _saveInfo,
      latest.id,
    );
    return (item: item, task: task);
  }

  Future<({DownloadedItem item, DownloadingTask task})>
  _buildEhentaiDownloadContext(DownloadedGallery comic) async {
    final res = await EhNetwork().getGalleryInfo(comic.gallery.link);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final id = getGalleryId(latest.link);
    final item = DownloadedGallery(latest, comic.comicSize, color: comic.color);
    final task = EhDownloadingTask(
      latest,
      _onFinish,
      _onError,
      _saveInfo,
      id,
      0,
    );
    return (item: item, task: task);
  }

  Future<({DownloadedItem item, DownloadingTask task})> _buildJmDownloadContext(
    DownloadedJmComic comic,
  ) async {
    final rawId = comic.id.replaceFirst(RegExp(r'^jm'), '');
    final res = await JmNetwork().getComicInfo(rawId);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final epsCount = latest.series.isEmpty ? 1 : latest.series.length;
    final downloadEps = List<int>.generate(epsCount, (index) => index);
    final item = DownloadedJmComic(
      latest,
      comic.comicSize,
      List<int>.from(comic.downloadedEps),
      color: comic.color,
    );
    final task = JmDownloadingTask(
      latest,
      downloadEps,
      _onFinish,
      _onError,
      _saveInfo,
      "jm${latest.id}",
    );
    return (item: item, task: task);
  }

  Future<({DownloadedItem item, DownloadingTask task})>
  _buildHitomiDownloadContext(DownloadedHitomiComic comic) async {
    final res = await HiNetwork().getComicInfo(comic.link);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final cover = latest.cover.isNotEmpty ? latest.cover : comic.cover;
    final item = DownloadedHitomiComic(
      latest,
      comic.comicSize,
      comic.link,
      cover,
      color: comic.color,
    );
    final task = HitomiDownloadingTask(
      latest,
      cover,
      comic.link,
      _onFinish,
      _onError,
      _saveInfo,
      "hitomi${latest.id}",
    );
    return (item: item, task: task);
  }

  Future<({DownloadedItem item, DownloadingTask task})> _buildHtDownloadContext(
    DownloadedHtComic comic,
  ) async {
    final rawId = comic.id.replaceFirst(RegExp(r'^Ht'), '');
    final res = await HtmangaNetwork().getComicInfo(rawId);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final item = DownloadedHtComic(latest, comic.comicSize, color: comic.color);
    final task = HtDownloadingTask(
      latest,
      _onFinish,
      _onError,
      _saveInfo,
      "Ht${latest.id}",
    );
    return (item: item, task: task);
  }

  Future<({DownloadedItem item, DownloadingTask task})>
  _buildNhentaiDownloadContext(NhentaiDownloadedComic comic) async {
    final rawId = comic.id.replaceFirst(RegExp(r'^nhentai'), '');
    final res = await NhentaiNetwork().getComicInfo(rawId);
    if (res.error) {
      throw Exception(res.errorMessageWithoutNull);
    }
    final latest = res.data;
    final item = NhentaiDownloadedComic(
      latest,
      comic.comicSize,
      color: comic.color,
    );
    final task = NhentaiDownloadingTask(
      latest,
      _onFinish,
      _onError,
      _saveInfo,
      "nhentai${latest.id}",
    );
    return (item: item, task: task);
  }

  DownloadedItem? _getComicFromJson({
    required String id,
    required String json,
    required DateTime time,
    double? size,
    String? directory,
    String? color,
    int? aiTranslationCompletedAt,
  }) {
    DownloadedItem comic;
    try {
      if (id.startsWith("LC")) {
        // 本地导入的漫画
        final jsonMap = jsonDecode(json) as Map<String, dynamic>;
        comic = LocalDownloadedItem.fromJson(jsonMap);
      } else if (id.startsWith("kemono-attachment-")) {
        // Kemono 附件下载 - 不应该被保存到数据库，但如果被保存了就忽略
        // 返回 null 会被 whereType<DownloadedItem>() 过滤掉
        return null;
      } else if (id.contains('-')) {
        comic = CustomDownloadedItem.fromJson(jsonDecode(json));
      } else if (id.startsWith("jm")) {
        comic = DownloadedJmComic.fromMap(jsonDecode(json));
      } else if (id.startsWith("hitomi")) {
        comic = DownloadedHitomiComic.fromMap(jsonDecode(json));
      } else if (id.startsWith("nhentai")) {
        comic = NhentaiDownloadedComic.fromJson(jsonDecode(json));
      } else if (id.startsWith("Ht")) {
        comic = DownloadedHtComic.fromJson(jsonDecode(json));
      } else if (id.isNum) {
        comic = DownloadedGallery.fromJson(jsonDecode(json));
      } else {
        comic = DownloadedComic.fromJson(jsonDecode(json));
      }
      comic.time = time;
      comic.directory = directory ?? "";
      if (size != null && size > 0) {
        comic.comicSize = size;
      }
      if (color != null) {
        comic.color = DownloadColorTag.fromString(color);
      }
      comic.aiTranslationCompletedAt = aiTranslationCompletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(aiTranslationCompletedAt);
      return comic;
    } catch (e, s) {
      Log.e("IO Failed to get a downloaded comic info:\n$e\n$s");
      return null;
    }
  }

  /// 添加或更新下载记录到数据库（公开方法，供 DownloadingTask 使用）
  Future<void> addToDb(
    DownloadedItem item,
    String directory, [
    DateTime? time,
  ]) async {
    // 使用锁保护数据库写入，防止并发导致的 SQLite 死锁
    await DownloadManager._dbLock.synchronized(() async {
      Log.d(
        () =>
            'DB DownloadManager: 添加/更新下载记录 id=${item.id}, name=${item.name}, directory=$directory',
      );
      await _db.addToDownload(
        item.id,
        item.name,
        item.subTitle,
        (time ?? DateTime.now()).millisecondsSinceEpoch,
        directory,
        item.comicSize ?? 0,
        jsonEncode(item.toJson()),
        color: item.color?.name,
      );
    });
  }

  /// 在保留下载元数据的前提下更新漫画详情。
  ///
  /// 返回 true 表示详情发生变化并已写入数据库。
  Future<bool> updateDownloadedDetails(
    DownloadedItem original,
    DownloadedItem updated,
  ) async {
    if (original.id != updated.id) {
      throw ArgumentError('下载详情更新前后的 ID 不一致');
    }
    final originalJson = original.toJson();
    final updatedJson = updated.toJson();
    if (original.name == updated.name &&
        original.subTitle == updated.subTitle &&
        TypeUtil.equal(originalJson, updatedJson)) {
      return false;
    }

    await DownloadManager._dbLock.synchronized(() async {
      await _db.updateDownloadDetails(
        id: original.id,
        title: updated.name,
        subtitle: updated.subTitle,
        json: jsonEncode(updatedJson),
      );
    });
    return true;
  }

  /// 更新漫画大小
  Future<void> updateSize(String id, double size) async {
    // 使用锁保护数据库写入
    await DownloadManager._dbLock.synchronized(() async {
      Log.d(() => 'DB DownloadManager: 更新漫画大小 id=$id, size=$size MB');
      await _db.updateDownloadSize(id, size);
    });
  }

  Future<bool> isExists(String id) async {
    final exists = await _db.isDownloadExists(id);
    Log.d(() => 'DB DownloadManager: 检查下载是否存在 id=$id, exists=$exists');
    return exists;
  }

  Future<void> _deleteFromDb(String id) async {
    // 使用锁保护数据库删除操作
    await DownloadManager._dbLock.synchronized(() async {
      Log.d(() => 'DB DownloadManager: 从数据库删除下载记录 id=$id');
      await _db.deleteDownload(id);
      _cache.remove(id);
    });
  }

  Future<DownloadedItem?> _getComicWithDb(String id) async {
    Log.d(() => 'DB DownloadManager: 从数据库获取漫画 id=$id');
    final result = await _db.getDownloadById(id);
    if (result == null) {
      Log.d(() => 'DB DownloadManager: 漫画不存在 id=$id');
      return null;
    }

    return _getComicFromJson(
      id: result[kDownloadId] as String,
      json: result[kDownloadJson] as String,
      time: DateTime.fromMillisecondsSinceEpoch(result[kDownloadTime] as int),
      size: result[kDownloadSize] is double
          ? result[kDownloadSize] as double
          : (result[kDownloadSize] as int).toDouble(),
      directory: result[kDownloadDirectory] as String? ?? "",
      color: result[kDownloadColor] as String?,
      aiTranslationCompletedAt:
          result[kDownloadAiTranslationCompletedAt] as int?,
    );
  }

  /// 根据ID获取已下载的漫画
  Future<DownloadedItem?> getDownloadedItemById(String id) async {
    return await _getComicWithDb(id);
  }

  /// 批量根据ID获取已下载的漫画
  Future<Map<String, DownloadedItem>> getDownloadedItemsByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};

    Log.d(() => 'DB DownloadManager: 批量获取漫画 ids=$ids');
    final results = await _db.getDownloadsByIds(ids);
    final map = <String, DownloadedItem>{};

    for (var result in results) {
      final comic = _getComicFromJson(
        id: result[kDownloadId] as String,
        json: result[kDownloadJson] as String,
        time: DateTime.fromMillisecondsSinceEpoch(result[kDownloadTime] as int),
        size: result[kDownloadSize] is double
            ? result[kDownloadSize] as double
            : (result[kDownloadSize] as int).toDouble(),
        directory: result[kDownloadDirectory] as String? ?? "",
        color: result[kDownloadColor] as String?,
        aiTranslationCompletedAt:
            result[kDownloadAiTranslationCompletedAt] as int?,
      );
      if (comic != null) {
        map[comic.id] = comic;
      }
    }

    Log.d(() => 'DB DownloadManager: 批量获取到 ${map.length} 个漫画');
    return map;
  }

  // int get total {
  //   // 注意：这个方法需要异步处理，但在原来代码中是同步的
  //   // 在实际使用中，需要重构调用此属性的地方改为异步
  //   throw UnimplementedError('Use getTotal() instead');
  // }

  Future<int> getTotal() async {
    final count = await _db.getDownloadTotalCount();
    Log.d(() => 'DB DownloadManager: 获取下载总数 count=$count');
    return count;
  }

  /// order: time, title, subtitle, size
  Future<List<DownloadedItem>> getAll([
    String order = 'time',
    String direction = 'desc',
  ]) async {
    Log.d(
      () => 'DB DownloadManager: 获取所有下载 order=$order, direction=$direction',
    );
    String orderBy;
    switch (order) {
      case 'time':
        orderBy = kDownloadTime;
        break;
      case 'title':
        orderBy = kDownloadTitle;
        break;
      case 'subtitle':
        orderBy = kDownloadSubtitle;
        break;
      case 'size':
        orderBy = kDownloadSize;
        break;
      default:
        orderBy = kDownloadTime;
    }

    final result = await _db.getAllDownloads(
      orderBy: orderBy,
      descending: direction == 'desc',
    );

    final comics = result
        .map(
          (e) => _getComicFromJson(
            id: e[kDownloadId] as String,
            json: e[kDownloadJson] as String,
            time: DateTime.fromMillisecondsSinceEpoch(e[kDownloadTime] as int),
            size: e[kDownloadSize] is double
                ? e[kDownloadSize] as double
                : (e[kDownloadSize] as int).toDouble(),
            directory: e[kDownloadDirectory] as String?,
            color: e[kDownloadColor] as String?,
            aiTranslationCompletedAt:
                e[kDownloadAiTranslationCompletedAt] as int?,
          ),
        )
        .whereType<DownloadedItem>() // 过滤掉 null 值
        .toList();
    Log.d(() => 'DB DownloadManager: 获取到 ${comics.length} 个下载记录');
    return comics;
  }

  static final _cache = <String, String>{};

  String getDirectory(String id) {
    var directory = _cache[id];
    if (directory == null) {
      // 注意：这个方法需要异步处理，但在原来代码中是同步的
      // 在实际使用中，需要重构调用此方法的地方改为异步
      throw UnimplementedError('Use getDirectoryAsync() instead');
    }
    return directory;
  }

  Future<String> getDirectoryName(String id) {
    var directory = _cache[id];
    if (directory != null && directory.isNotEmpty) {
      return SynchronousFuture(directory);
    }
    return Future.sync(() async {
      String? directory = await _db.getDownloadDirectory(id);
      if (directory == null) {
        debugPrint("Failed to get directory for $id");
        return '';
      }
      if (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }
      _cache[id] = directory;
      return directory;
    });
  }

  Future<String> getFullDirectory(String id) async {
    // 如果是本地漫画，需要从存储库获取路径
    if (id.startsWith('LC')) {
      final item = await getDownloadedItemById(id);
      if (item is LocalDownloadedItem) {
        final repoPath = await LocalRepositoryManager().getRepositoryPath(
          item.repositoryName,
        );
        if (repoPath != null && item.directory.isNotEmpty) {
          return Path.join(repoPath, item.directory);
        }
      }
      return '';
    }
    return getDirectoryName(id).then((e) {
      if (e.isEmpty) return '';
      return Path.join(comicsPath, e);
    });
  }

  /// 获取本地漫画的完整封面路径
  Future<String?> getLocalComicCoverPath(String id) async {
    if (!id.startsWith('LC')) return null;
    final item = await getDownloadedItemById(id);
    if (item is LocalDownloadedItem) {
      final repoPath = await LocalRepositoryManager().getRepositoryPath(
        item.repositoryName,
      );
      if (repoPath != null && item.coverImagePath != null) {
        return Path.join(repoPath, item.coverImagePath!);
      }
    }
    return null;
  }

  /// 添加一个本地的漫画
  Future<void> addLocalItem({
    required String path,
    required String title,
    required String subtitle,
    required Map<String, dynamic> json,
    required double size,
    required String cover,
  }) async {
    Log.d(
      () =>
          'DB DownloadManager: 添加本地漫画 title=$title, path=$path, size=$size MB',
    );
    await _db.addLocalComic(
      path: path,
      title: title,
      subtitle: subtitle,
      json: jsonEncode(json),
      size: size,
      cover: cover,
    );
  }

  Future<List<Map<String, dynamic>>> getAllLocal() async {
    Log.d(() => 'DB DownloadManager: 获取所有本地漫画');
    final result = (await _db.getAllLocalComics())
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    Log.d(() => 'DB DownloadManager: 获取到 ${result.length} 个本地漫画');
    return result;
  }

  Future<void> deleteLocal(String path) async {
    Log.d(() => 'DB DownloadManager: 删除本地漫画 path=$path');
    await _db.deleteLocalComic(path);
  }

  Future<void> addOrUpdateLocalHistory({
    required String path,
    required int isReversed,
    required int pageIndex,
    required int time,
    int totalPages = 0,
  }) async {
    await _db.addOrUpdateLocalHistory(
      path: path,
      isReversed: isReversed,
      pageIndex: pageIndex,
      time: time,
      json: const JsonEncoder().convert({
        "isReversed": isReversed,
        "pageIndex": pageIndex,
        "time": time,
        "total_pages": totalPages,
      }),
      totalPages: totalPages,
    );
  }

  Future<Map<String, dynamic>> getLocalHistory(String path) async {
    final result = await _db.getLocalHistory(path);
    if (result == null) return {};
    return TypeUtil.parseMap(result);
  }

  // ==================== Tag Management Methods ====================

  /// 创建标签
  Future<int> createTag(
    String name, {
    String? coverComicId,
    int category = 0,
  }) async {
    Log.d(() => 'DB DownloadManager: 创建标签 name=$name, category=$category');
    return await _db.createTag(
      name,
      coverComicId: coverComicId,
      category: category,
    );
  }

  /// 获取所有标签
  Future<List<DownloadTag>> getAllTags() async {
    Log.d(() => 'DB DownloadManager: 获取所有标签');
    final maps = await _db.getAllTags();
    final tags = maps.map((map) => DownloadTag.fromMap(map)).toList();
    Log.d(() => 'DB DownloadManager: 获取到 ${tags.length} 个标签');
    return tags;
  }

  /// 根据ID获取标签
  Future<DownloadTag?> getTagById(int tagId) async {
    Log.d(() => 'DB DownloadManager: 根据ID获取标签 tagId=$tagId');
    final map = await _db.getTagById(tagId);
    return map != null ? DownloadTag.fromMap(map) : null;
  }

  /// 重命名标签
  Future<void> renameTag(int tagId, String newName) async {
    Log.d(() => 'DB DownloadManager: 重命名标签 tagId=$tagId, newName=$newName');
    await _db.updateTagName(tagId, newName);
  }

  /// 更新标签封面（使用漫画ID）
  Future<void> updateTagCover(int tagId, String coverComicId) async {
    Log.d(
      () =>
          'DB DownloadManager: 更新标签封面 tagId=$tagId, coverComicId=$coverComicId',
    );
    await _db.updateTagCover(tagId, coverComicId);
  }

  /// 删除标签
  Future<void> deleteTag(int tagId) async {
    Log.d(() => 'DB DownloadManager: 删除标签 tagId=$tagId');
    await _db.deleteTag(tagId);
  }

  /// 为漫画添加标签
  Future<void> addTagToComic(String comicId, int tagId) async {
    Log.d(() => 'DB DownloadManager: 为漫画添加标签 comicId=$comicId, tagId=$tagId');
    await _db.addTagToComic(comicId, tagId);
    _notifyTagsChanged();
  }

  /// 为漫画添加多个标签
  Future<void> addTagsToComic(String comicId, List<int> tagIds) async {
    Log.d(
      () => 'DB DownloadManager: 为漫画添加多个标签 comicId=$comicId, tagIds=$tagIds',
    );
    for (var tagId in tagIds) {
      await _db.addTagToComic(comicId, tagId);
    }
    _notifyTagsChanged();
  }

  /// 从漫画移除标签
  Future<void> removeTagFromComic(String comicId, int tagId) async {
    Log.d(() => 'DB DownloadManager: 从漫画移除标签 comicId=$comicId, tagId=$tagId');
    await _db.removeTagFromComic(comicId, tagId);
    _notifyTagsChanged();
  }

  /// 批量更新标签
  Future<void> batchUpdateTags(
    List<String> comicIds,
    List<int> addTagIds,
    List<int> removeTagIds,
  ) async {
    Log.d(
      () =>
          'DB DownloadManager: 批量更新标签 comicIds count=${comicIds.length}, add=${addTagIds.length}, remove=${removeTagIds.length}',
    );
    await _db.batchUpdateComicTags(comicIds, addTagIds, removeTagIds);
    _notifyTagsChanged();
  }

  /// 获取漫画的所有标签
  Future<List<DownloadTag>> getComicTags(String comicId) async {
    Log.d(() => 'DB DownloadManager: 获取漫画的所有标签 comicId=$comicId');
    final maps = await _db.getComicTags(comicId);
    final tags = maps.map((map) => DownloadTag.fromMap(map)).toList();
    Log.d(() => 'DB DownloadManager: 漫画有 ${tags.length} 个标签');
    return tags;
  }

  Future<List<DownloadTag>> getCommonComicTags(List<String> comicIds) async {
    Log.d(() => 'DB DownloadManager: 获取多个漫画的共同标签 comicIds=$comicIds');
    final maps = await _db.getCommonComicTags(comicIds);
    final tags = maps.map((map) => DownloadTag.fromMap(map)).toList();
    Log.d(() => 'DB DownloadManager: 共同标签有 ${tags.length} 个');
    return tags;
  }

  /// 获取所有漫画的标签映射
  Future<Map<String, List<String>>> getAllComicTagsMap() async {
    Log.d(() => 'DB DownloadManager: 获取所有漫画的标签映射');
    final result = await _db.getAllComicTags();
    Log.d(() => 'DB DownloadManager: 获取到 ${result.length} 个漫画的标签映射');
    return result;
  }

  /// 获取标签下的所有漫画ID
  Future<List<String>> getComicIdsByTag(int tagId) async {
    Log.d(() => 'DB DownloadManager: 获取标签下的所有漫画ID tagId=$tagId');
    final ids = await _db.getComicIdsByTag(tagId);
    Log.d(() => 'DB DownloadManager: 标签下有 ${ids.length} 个漫画');
    return ids;
  }

  /// 获取标签下的漫画数量
  Future<int> getTagComicCount(int tagId) async {
    Log.d(() => 'DB DownloadManager: 获取标签下的漫画数量 tagId=$tagId');
    final count = await _db.getTagComicCount(tagId);
    Log.d(() => 'DB DownloadManager: 标签下有 $count 个漫画');
    return count;
  }

  /// 清除漫画的所有标签
  Future<void> clearComicTags(String comicId) async {
    Log.d(() => 'DB DownloadManager: 清除漫画所有标签 comicId=$comicId');
    await _db.clearComicTags(comicId);
  }

  /// 更新标签排序
  Future<void> updateTagSortOrder(int tagId, int sortOrder) async {
    Log.d(
      () => 'DB DownloadManager: 更新标签排序 tagId=$tagId, sortOrder=$sortOrder',
    );
    await _db.updateTagSortOrder(tagId, sortOrder);
  }

  /// 批量更新标签排序
  Future<void> updateTagsSortOrder(List<int> tagIds) async {
    Log.d(() => 'DB DownloadManager: 批量更新标签排序 tagIds=$tagIds');
    await _db.updateTagsSortOrder(tagIds);
  }

  /// 更新标签分类排序
  Future<void> updateTagCategorySortOrder(int tagId, int sortOrder) async {
    Log.d(
      () => 'DB DownloadManager: 更新标签分类排序 tagId=$tagId, sortOrder=$sortOrder',
    );
    await _db.updateTagCategorySortOrder(tagId, sortOrder);
  }

  /// 更新标签分类
  Future<void> updateTagCategory(int tagId, int category) async {
    Log.d(() => 'DB DownloadManager: 更新标签分类 tagId=$tagId, category=$category');
    await _db.updateTagCategory(tagId, category);
  }

  /// 按分类获取标签
  Future<List<DownloadTag>> getTagsByCategory(int category) async {
    Log.d(() => 'DB DownloadManager: 按分类获取标签 category=$category');
    final maps = await _db.getTagsByCategory(category);
    final tags = maps.map((map) => DownloadTag.fromMap(map)).toList();
    Log.d(() => 'DB DownloadManager: 该分类有 ${tags.length} 个标签');
    return tags;
  }

  // ==================== Directory Rename Methods ====================

  /// 根据漫画信息生成新的目录名
  String generateDirectoryName(DownloadedItem item) {
    return _buildDirectoryName(item.type.name, item.id, item.name);
  }

  /// 生成唯一的本地漫画ID（带冲突检测）
  Future<String> _generateUniqueLocalId(String repositoryName) async {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    String id;
    bool exists;
    int attempts = 0;
    const maxAttempts = 100;

    do {
      final suffix = List.generate(
        8,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      id = 'LC$repositoryName$suffix';
      exists = await _db.isDownloadExists(id);
      attempts++;
      if (attempts >= maxAttempts) {
        throw Exception(
          'Failed to generate unique ID after $maxAttempts attempts',
        );
      }
    } while (exists);

    return id;
  }

  /// 扫描漫画目录（只扫描直接子目录）
  Future<List<Map<String, dynamic>>> scanComicDirectories(
    String parentPath,
    String repositoryPath,
  ) async {
    final result = <Map<String, dynamic>>[];
    final parentDir = Directory(parentPath);

    if (!await parentDir.exists()) {
      return result;
    }

    // 只扫描直接子目录
    await for (var entity in parentDir.list()) {
      if (entity is Directory) {
        // 递归扫描该子目录下的所有文件，查找图片
        int imageCount = 0;
        String? firstImagePath;

        try {
          await for (var file in entity.list(recursive: true)) {
            if (file is File && predictImageFile(file)) {
              imageCount++;
              firstImagePath ??= file.path;
            }
          }
        } catch (e) {
          // 忽略无法访问的目录
          continue;
        }

        // 如果包含至少3张图片，则添加到结果列表
        if (imageCount >= 3) {
          final relativePath = Path.relative(entity.path, from: repositoryPath);
          // coverImagePath存储相对于漫画目录的路径
          final relativeImagePath = firstImagePath != null
              ? Path.relative(firstImagePath, from: entity.path)
              : null;

          result.add({
            'path': entity.path,
            'name': Path.basename(entity.path),
            'relativePath': relativePath,
            'imageCount': imageCount,
            'coverImagePath': relativeImagePath,
          });
        }
      }
    }

    return result;
  }

  /// 导入本地漫画
  Future<Map<String, dynamic>> importLocalComics({
    required String draggedFolderPath,
    required String repositoryName,
    String? titlePrefix,
    List<int>? tagIds,
    List<Map<String, dynamic>>? comicDirs,
  }) async {
    Log.d(
      () =>
          'DB DownloadManager: 开始导入本地漫画 repository=$repositoryName, path=$draggedFolderPath',
    );
    var successCount = 0;
    var failCount = 0;
    final errors = <String>[];

    try {
      // 获取存储库路径
      final repositoryPath = await LocalRepositoryManager().getRepositoryPath(
        repositoryName,
      );
      if (repositoryPath == null) {
        Log.d(() => 'DB DownloadManager: 存储库不存在 repository=$repositoryName');
        return {
          'success': false,
          'message': '存储库不存在: $repositoryName',
          'successCount': 0,
          'failCount': 0,
        };
      }

      // 如果提供了已扫描的漫画目录列表，直接使用；否则进行扫描
      final finalComicDirs =
          comicDirs ??
          await scanComicDirectories(draggedFolderPath, repositoryPath);
      Log.d(() => 'DB DownloadManager: 扫描到 ${finalComicDirs.length} 个漫画目录');

      // 导入每个漫画目录
      for (var comicDir in finalComicDirs) {
        try {
          final relativePath = comicDir['relativePath'] as String;

          // 通过相对路径查询数据库，检查是否已存在（只查询相同相对路径的记录）
          final existingRecords = await _db.getDownloadsByDirectory(
            relativePath,
          );

          // 检查是否有相同相对路径和存储库名称的记录
          bool isDuplicate = false;
          for (var record in existingRecords) {
            try {
              final jsonStr = record[kDownloadJson] as String;
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              // 只检查本地漫画（ID以LC开头）且存储库名称匹配的记录
              final recordId = record[kDownloadId] as String;
              if (recordId.startsWith('LC') &&
                  json['repositoryName'] == repositoryName) {
                isDuplicate = true;
                break;
              }
            } catch (e) {
              // 忽略解析失败的记录
              continue;
            }
          }

          if (isDuplicate) {
            failCount++;
            errors.add('${comicDir['name']}: 已存在');
            Log.d(
              () => 'DB DownloadManager: 漫画已存在，跳过 name=${comicDir['name']}',
            );
            continue;
          }

          // 生成唯一ID
          final id = await _generateUniqueLocalId(repositoryName);

          // 计算目录大小
          final dir = Directory(comicDir['path'] as String);
          final size = await dir.getMBSize();

          // 创建LocalDownloadedItem
          final name = titlePrefix != null && titlePrefix.isNotEmpty
              ? '$titlePrefix ${comicDir['name']}'
              : comicDir['name'] as String;

          final item = LocalDownloadedItem(
            comicSize: size,
            downloadedEps: [],
            id: id,
            name: name,
            subTitle: '',
            tags: [],
            repositoryName: repositoryName,
            coverImagePath: comicDir['coverImagePath'] as String?,
          );

          // 保存到数据库
          Log.d(
            () => 'DB DownloadManager: 导入漫画 id=$id, name=$name, size=$size MB',
          );
          await addToDb(item, relativePath);

          // 如果选择了标签，关联标签
          if (tagIds != null && tagIds.isNotEmpty) {
            for (final tagId in tagIds) {
              await addTagToComic(id, tagId);
            }
          }

          successCount++;
        } catch (e, s) {
          failCount++;
          errors.add('${comicDir['name']}: $e');
          Log.e('导入漫画失败: $e', stackTrace: s);
        }
      }

      Log.d(() => 'DB DownloadManager: 导入完成 成功=$successCount, 失败=$failCount');
      return {
        'success': true,
        'successCount': successCount,
        'failCount': failCount,
        'errors': errors,
      };
    } catch (e, s) {
      Log.e('导入本地漫画失败: $e', stackTrace: s);
      return {
        'success': false,
        'message': '导入失败: $e',
        'successCount': successCount,
        'failCount': failCount,
        'errors': errors,
      };
    }
  }

  /// 重命名漫画目录
  /// 返回 null 表示成功,返回错误信息表示失败
  Future<String?> renameComicDirectory(
    String id,
    String newDirectoryName,
  ) async {
    try {
      Log.d(() => 'DownloadManager: 重命名漫画目录 id=$id, newName=$newDirectoryName');
      // 获取当前目录名
      final oldDirectoryName = await getDirectoryName(id);
      if (oldDirectoryName.isEmpty) {
        Log.d(() => 'DownloadManager: 未找到漫画目录 id=$id');
        return '未找到漫画目录';
      }

      // 如果目录名相同,不需要重命名
      if (oldDirectoryName == newDirectoryName) {
        Log.d(() => 'DownloadManager: 目录名相同，无需重命名 id=$id');
        return null;
      }

      // 构建完整路径
      final oldPath = Path.join(comicsPath, oldDirectoryName);
      final newPath = Path.join(comicsPath, newDirectoryName);

      // 检查旧目录是否存在
      final oldDir = Directory(oldPath);
      if (!await oldDir.exists()) {
        Log.d(() => 'DownloadManager: 源目录不存在 path=$oldPath');
        return '源目录不存在: $oldPath';
      }

      // 检查新目录是否已存在
      final newDir = Directory(newPath);
      if (await newDir.exists()) {
        Log.d(() => 'DownloadManager: 目标目录已存在 path=$newPath');
        return '目标目录已存在: $newPath';
      }

      // 执行重命名
      try {
        await oldDir.rename(newPath);
        Log.d(() => 'DownloadManager: 目录重命名成功 from=$oldPath to=$newPath');
      } catch (e) {
        if (await newDir.exists()) {
          if ((await newDir.list().length) == 0) {
            await newDir.delete();
          } else {
            rethrow;
          }
        }
      }

      Log.d(
        () =>
            'DB DownloadManager: 更新数据库中的目录名 id=$id, newDirectory=$newDirectoryName',
      );
      final result = await _db.updateDownloadDirectory(id, newDirectoryName);
      if (!result) {
        Log.d(() => 'DB DownloadManager: 更新数据库失败 id=$id');
        return '更新数据库失败';
      }
      // 更新缓存
      _cache[id] = newDirectoryName;

      return null;
    } catch (e, s) {
      Log.e('重命名目录失败: $e', stackTrace: s);
      return '重命名失败: $e';
    }
  }

  /// 更新漫画颜色
  Future<void> updateColor(String id, DownloadColorTag? color) async {
    Log.d(() => 'DB DownloadManager: 更新漫画颜色 id=$id, color=${color?.name}');
    await _db.updateDownloadColor(id, color?.name);
    _notifyComicsChanged();
  }

  /// 手动或自动标记漫画已完成 AI 翻译。
  Future<void> markAiTranslationCompleted(
    String id, {
    DateTime? completedAt,
  }) async {
    final time = (completedAt ?? DateTime.now()).millisecondsSinceEpoch;
    await DownloadManager._dbLock.synchronized(() async {
      await _db.updateAiTranslationCompletedAt(id, time);
    });
    _notifyComicsChanged();
  }

  /// 清除漫画的 AI 翻译完成标记。
  Future<void> clearAiTranslationCompleted(String id) async {
    await DownloadManager._dbLock.synchronized(() async {
      await _db.updateAiTranslationCompletedAt(id, null);
    });
    _notifyComicsChanged();
  }

  /// 批量更新漫画颜色
  Future<void> batchUpdateColor(
    List<String> ids,
    DownloadColorTag? color,
  ) async {
    Log.d(() => 'DB DownloadManager: 批量更新漫画颜色 ids=$ids, color=${color?.name}');
    final colorName = color?.name;
    for (var id in ids) {
      await _db.updateDownloadColor(id, colorName);
    }
    _notifyComicsChanged();
  }
}

class SaveInfoItem {
  final Map<String, dynamic> items;
  final String path;

  SaveInfoItem(this.items, this.path);
}

/// 批量下载操作结果。
class DownloadBatchResult {
  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<String> errors;

  const DownloadBatchResult({
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    this.errors = const [],
  });

  int get totalCount => successCount + skippedCount + failedCount;
}

class LocalFavoriteItem {
  final String path;
  final int sortOrder;
  final int time;

  LocalFavoriteItem(this.path, this.sortOrder, this.time);

  factory LocalFavoriteItem.fromMap(Map<String, dynamic> map) {
    return LocalFavoriteItem(
      TypeUtil.parseString(map[kLocalFavoritePath]),
      TypeUtil.parseInt(map[kLocalFavoriteSortOrder]),
      TypeUtil.parseInt(map[kLocalFavoriteTime]),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      kLocalFavoritePath: path,
      kLocalFavoriteSortOrder: sortOrder,
      kLocalFavoriteTime: time,
    };
  }
}

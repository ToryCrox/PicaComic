import 'dart:collection';
import 'dart:async';
import 'package:pica_comic/foundation/log.dart';
import 'download_exceptions.dart';

/// 图片下载队列项的状态
enum ImageDownloadTaskState {
  /// 等待下载
  waiting,

  /// 下载中
  downloading,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已取消
  canceled,
}

/// 图片下载队列项
///
/// 表示一个待下载的图片任务
class ImageDownloadQueueItem {
  /// 图片URL
  final String url;

  /// 章节索引（从0开始，对于无章节的漫画为0）
  final int episodeIndex;

  /// 图片索引（在章节中的位置）
  final int imageIndex;

  /// 保存路径（目录）
  final String savePath;

  /// 文件基础名称（不含扩展名）
  final String fileBaseName;

  /// 任务状态
  ImageDownloadTaskState state;

  /// 错误信息
  Object? error;

  /// 重试次数
  int retryCount;

  /// 下载进度（字节）
  int downloadedBytes;

  /// 总大小（字节，如果未知则为0）
  int totalBytes;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  DateTime? completedAt;

  ImageDownloadQueueItem({
    required this.url,
    required this.episodeIndex,
    required this.imageIndex,
    required this.savePath,
    required this.fileBaseName,
    this.state = ImageDownloadTaskState.waiting,
    this.error,
    this.retryCount = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
  }) : createdAt = DateTime.now();

  /// 生成唯一键
  String get key => '$episodeIndex-$imageIndex';

  /// 是否已完成
  bool get isCompleted => state == ImageDownloadTaskState.completed;

  /// 是否失败
  bool get isFailed => state == ImageDownloadTaskState.failed;

  /// 是否可以重试
  bool get canRetry => state == ImageDownloadTaskState.failed;

  @override
  String toString() {
    return 'ImageDownloadQueueItem(ep: $episodeIndex, idx: $imageIndex, state: $state, retry: $retryCount)';
  }
}

/// 图片下载队列
///
/// 管理单个漫画的所有图片下载任务，控制并发数量，跟踪下载进度
class ImageDownloadQueue {
  /// 等待下载的图片队列
  final Queue<ImageDownloadQueueItem> _waitingQueue =
      Queue<ImageDownloadQueueItem>();

  /// 正在下载的图片映射表（key: ep-index）
  final Map<String, ImageDownloadQueueItem> _downloadingItems = {};

  /// 已完成的图片集合（key: ep-index）
  final Map<String, ImageDownloadQueueItem> _completedItems = {};

  /// 失败的图片集合（key: ep-index）
  final Map<String, ImageDownloadQueueItem> _failedItems = {};

  /// 正在等待退避重试的图片集合（key: ep-index）
  final Map<String, ImageDownloadQueueItem> _retryingItems = {};

  /// 最大并发下载数
  final int maxConcurrentDownloads;

  /// 是否正在运行
  bool _isRunning = false;

  /// 完成信号（用于 await start() 等待所有任务完成）
  Completer<void>? _completer;

  /// 需要立即停止重试的终止错误。
  Object? _terminalError;

  /// 下载函数
  final Future<void> Function(ImageDownloadQueueItem item) downloadFunction;

  /// 进度更新回调
  final void Function(int downloaded, int total)? onProgressUpdate;

  /// 任务完成回调
  final void Function()? onAllCompleted;

  /// 任务失败回调（所有重试都失败后）
  final void Function(List<ImageDownloadQueueItem> failedItems)? onFailed;

  /// 章节完成回调（当一个章节的所有图片下载完成时触发）
  final void Function(int episodeIndex)? onEpisodeCompleted;

  /// 每个章节的图片总数
  final Map<int, int> _episodeTotalCounts = {};

  /// 每个章节已完成的图片数
  final Map<int, int> _episodeCompletedCounts = {};

  /// 已触发完成回调的章节（避免重复触发）
  final Set<int> _completedEpisodes = {};

  ImageDownloadQueue({
    required this.downloadFunction,
    this.maxConcurrentDownloads = 6,
    this.onProgressUpdate,
    this.onAllCompleted,
    this.onFailed,
    this.onEpisodeCompleted,
  });

  /// 获取当前下载中的数量
  int get downloadingCount => _downloadingItems.length;

  /// 获取等待中的数量
  int get waitingCount => _waitingQueue.length;

  /// 获取已完成的数量
  int get completedCount => _completedItems.length;

  /// 获取失败的数量
  int get failedCount => _failedItems.length;

  /// 获取等待退避重试的数量
  int get retryingCount => _retryingItems.length;

  /// 获取总任务数量
  int get totalCount =>
      _waitingQueue.length +
      _downloadingItems.length +
      _retryingItems.length +
      _completedItems.length +
      _failedItems.length;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 获取需要交给下载任务处理的终止错误。
  Object? get terminalError => _terminalError;

  /// 是否全部完成
  bool get isAllCompleted => totalCount > 0 && completedCount == totalCount;

  /// 是否处于流式模式（动态添加任务）
  bool _streamMode = false;

  /// 设置是否为流式模式
  ///
  /// 如果为 true，队列为空时不会自动结束，而是等待新任务
  /// 如果设置为 false 且队列为空，会触发完成回调
  void setStreamMode(bool enable) {
    _streamMode = enable;
    if (!_streamMode && _isRunning) {
      _scheduleNext();
    }
  }

  /// 添加图片到队列
  void addImage(ImageDownloadQueueItem item) {
    final key = item.key;

    // 检查是否已存在
    if (_completedItems.containsKey(key) ||
        _downloadingItems.containsKey(key) ||
        _retryingItems.containsKey(key) ||
        _failedItems.containsKey(key) ||
        _waitingQueue.any((i) => i.key == key)) {
      //Log.d('ImageDownloadQueue: Item $key already exists');
      return;
    }

    _waitingQueue.addLast(item);

    // 统计章节图片总数
    _episodeTotalCounts[item.episodeIndex] =
        (_episodeTotalCounts[item.episodeIndex] ?? 0) + 1;

    // 如果正在运行，尝试调度
    if (_isRunning) {
      _scheduleNext();
    }
  }

  /// 批量添加图片
  void addImages(List<ImageDownloadQueueItem> items) {
    for (var item in items) {
      addImage(item);
    }
  }

  /// 开始下载
  ///
  /// 这个方法会阻塞直到所有任务完成（成功或失败）
  Future<void> start() async {
    if (_isRunning) {
      Log.w('ImageDownloadQueue: Already running');
      return;
    }

    _isRunning = true;
    _completer = Completer<void>();

    Log.i(
      'ImageDownloadQueue: Starting queue. Total: $totalCount, Waiting: ${_waitingQueue.length}',
    );

    // 触发任务调度
    _scheduleNext();

    // 等待所有任务完成
    await _completer!.future;
  }

  /// 暂停下载
  void pause() {
    if (!_isRunning) {
      Log.w('ImageDownloadQueue: Already paused');
      return;
    }

    _isRunning = false;
    Log.i(
      'ImageDownloadQueue: Paused. Downloaded: $completedCount, Failed: $failedCount, Downloading: $downloadingCount',
    );

    // 解除对 start() 的阻塞
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }

  /// 取消所有下载
  void cancelAll() {
    _isRunning = false;
    _terminalError = null;

    // 将所有正在下载的任务标记为取消
    for (var item in _downloadingItems.values) {
      item.state = ImageDownloadTaskState.canceled;
    }
    for (var item in _retryingItems.values) {
      item.state = ImageDownloadTaskState.canceled;
    }

    _downloadingItems.clear();
    _retryingItems.clear();
    _waitingQueue.clear();

    Log.i('ImageDownloadQueue: All tasks canceled');
  }

  /// 重试失败的任务
  Future<void> retryFailed() async {
    if (_failedItems.isEmpty) {
      Log.i('ImageDownloadQueue: No failed items to retry');
      return;
    }

    Log.i('ImageDownloadQueue: Retrying ${_failedItems.length} failed items');
    _terminalError = null;

    // 将失败的任务重新加入队列
    final failedList = _failedItems.values.toList();
    _failedItems.clear();

    for (var item in failedList) {
      item.state = ImageDownloadTaskState.waiting;
      item.error = null;
      // 保留重试次数，用于退避策略
      _waitingQueue.addLast(item);
    }

    // 如果队列没有运行，启动它
    if (!_isRunning) {
      await start();
    } else {
      _scheduleNext();
    }
  }

  /// 清除已完成的项目（释放内存）
  void clearCompleted() {
    _completedItems.clear();
  }

  /// 调度下一批任务
  void _scheduleNext() {
    if (!_isRunning) {
      return;
    }

    // 继续调度直到达到并发上限或没有等待的任务
    while (_downloadingItems.length < maxConcurrentDownloads &&
        _waitingQueue.isNotEmpty) {
      final item = _waitingQueue.removeFirst();
      _downloadItem(item);
    }

    // 检查是否全部完成
    if (_waitingQueue.isEmpty &&
        _downloadingItems.isEmpty &&
        _retryingItems.isEmpty) {
      // 如果处于流式模式，等待新任务，不结束
      if (_streamMode) {
        return;
      }

      if (_failedItems.isEmpty) {
        Log.i('ImageDownloadQueue: All tasks completed successfully');
        _isRunning = false;
        onAllCompleted?.call();
        _completer?.complete(); // 发送完成信号
      } else {
        Log.w(
          'ImageDownloadQueue: All tasks finished but ${_failedItems.length} failed',
        );
        _isRunning = false;
        onFailed?.call(_failedItems.values.toList());
        _completer?.complete(); // 即使有失败也发送完成信号
      }
    }
  }

  /// 单张图片的最大重试次数
  static const _maxItemRetries = 3;

  /// 单张图片重试的初始延迟（毫秒）
  static const _itemRetryInitialDelayMs = 500;

  /// 下载单个图片（带自动重试）
  Future<void> _downloadItem(ImageDownloadQueueItem item) async {
    final key = item.key;
    item.state = ImageDownloadTaskState.downloading;
    _downloadingItems[key] = item;

    try {
      // 调用下载函数
      await downloadFunction(item);

      // 下载成功
      item.state = ImageDownloadTaskState.completed;
      item.completedAt = DateTime.now();
      _downloadingItems.remove(key);
      _completedItems[key] = item;

      Log.d(
        'ImageDownloadQueue: Downloaded $key ($completedCount/$totalCount), title: ${item.savePath}',
      );

      // 通知进度更新
      onProgressUpdate?.call(completedCount, totalCount);

      // 检查章节是否完成
      _checkEpisodeCompleted(item.episodeIndex);
    } catch (e) {
      if (e is DownloadNonRetryableException) {
        Log.e('ImageDownloadQueue: Non-retryable failure for $key: $e');
        item.state = ImageDownloadTaskState.failed;
        item.error = e;
        _downloadingItems.remove(key);
        _failedItems[key] = item;
        _terminalError ??= e;
        // 保留等待队列和已完成项目，暂停后恢复时继续补齐剩余图片。
        _isRunning = false;
        onProgressUpdate?.call(completedCount, totalCount);
        _completeAfterTerminalErrorIfIdle();
        return;
      }

      // 下载失败，检查是否可以重试
      item.retryCount++;

      if (item.retryCount < _maxItemRetries) {
        // 可以重试：延迟后重新加入等待队列
        final delay =
            _itemRetryInitialDelayMs * (1 << (item.retryCount - 1)); // 指数退避
        Log.w(
          'ImageDownloadQueue: Failed to download $key (attempt ${item.retryCount}/$_maxItemRetries), retrying in ${delay}ms: $e',
        );

        _downloadingItems.remove(key);
        item.state = ImageDownloadTaskState.waiting;
        item.error = null;
        _retryingItems[key] = item;

        // 延迟后重新加入队列
        Future.delayed(Duration(milliseconds: delay), () {
          if (item.state == ImageDownloadTaskState.canceled) return;
          _retryingItems.remove(key);
          _waitingQueue.addLast(item);
          if (_isRunning) {
            _scheduleNext();
          }
          _completeAfterTerminalErrorIfIdle();
        });
      } else {
        // 达到最大重试次数，标记为最终失败
        Log.e(
          'ImageDownloadQueue: Failed to download $key after $_maxItemRetries attempts: $e',
        );

        item.state = ImageDownloadTaskState.failed;
        item.error = e;

        _downloadingItems.remove(key);
        _failedItems[key] = item;
      }

      // 通知进度更新
      onProgressUpdate?.call(completedCount, totalCount);
    }

    // 调度下一个任务
    _scheduleNext();
    _completeAfterTerminalErrorIfIdle();
  }

  /// 终止错误发生后，等待已经发出的请求结束，再解除任务等待。
  void _completeAfterTerminalErrorIfIdle() {
    if (_terminalError == null ||
        _downloadingItems.isNotEmpty ||
        _retryingItems.isNotEmpty) {
      return;
    }
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
  }

  /// 检查章节是否完成
  void _checkEpisodeCompleted(int episodeIndex) {
    // 如果已经触发过，跳过
    if (_completedEpisodes.contains(episodeIndex)) return;

    // 更新已完成数量
    _episodeCompletedCounts[episodeIndex] =
        (_episodeCompletedCounts[episodeIndex] ?? 0) + 1;

    final total = _episodeTotalCounts[episodeIndex] ?? 0;
    final completed = _episodeCompletedCounts[episodeIndex] ?? 0;

    if (completed >= total && total > 0) {
      _completedEpisodes.add(episodeIndex);
      Log.i(
        'ImageDownloadQueue: Episode $episodeIndex completed ($completed/$total)',
      );
      onEpisodeCompleted?.call(episodeIndex);
    }
  }

  /// 获取已完成的章节索引集合
  Set<int> getCompletedEpisodes() {
    return Set<int>.from(_completedEpisodes);
  }

  /// 获取队列状态摘要
  String getStatusSummary() {
    return 'Total: $totalCount, Completed: $completedCount, Downloading: $downloadingCount, Waiting: $waitingCount, Retrying: $retryingCount, Failed: $failedCount';
  }

  /// 获取每个章节的进度
  ///
  /// 返回 Map，key 是章节索引，value 是 `(downloaded, total)` 元组
  Map<int, ({int downloaded, int total})> getEpisodeProgress() {
    final result = <int, ({int downloaded, int total})>{};
    for (var entry in _episodeTotalCounts.entries) {
      final ep = entry.key;
      final total = entry.value;
      final completed = _episodeCompletedCounts[ep] ?? 0;
      result[ep] = (downloaded: completed, total: total);
    }
    return result;
  }

  /// 取消指定章节的所有下载任务
  ///
  /// 从等待队列中移除该章节的任务，并标记正在下载的任务为已取消
  void cancelEpisode(int episodeIndex) {
    Log.i('ImageDownloadQueue: Cancelling episode $episodeIndex');

    // 从等待队列中移除该章节的任务
    _waitingQueue.removeWhere((item) => item.episodeIndex == episodeIndex);

    // 标记正在下载的该章节任务为已取消
    final downloadingKeys = _downloadingItems.keys.toList();
    for (var key in downloadingKeys) {
      final item = _downloadingItems[key];
      if (item != null && item.episodeIndex == episodeIndex) {
        item.state = ImageDownloadTaskState.canceled;
        _downloadingItems.remove(key);
      }
    }

    // 从失败列表中移除该章节的任务
    _failedItems.removeWhere((key, item) => item.episodeIndex == episodeIndex);

    // 取消等待退避重试的该章节任务
    final retryingKeys = _retryingItems.keys.toList();
    for (var key in retryingKeys) {
      final item = _retryingItems[key];
      if (item != null && item.episodeIndex == episodeIndex) {
        item.state = ImageDownloadTaskState.canceled;
        _retryingItems.remove(key);
      }
    }

    // 更新统计数据
    _episodeTotalCounts.remove(episodeIndex);
    _episodeCompletedCounts.remove(episodeIndex);
    _completedEpisodes.remove(episodeIndex);

    Log.i(
      'ImageDownloadQueue: Episode $episodeIndex cancelled. Remaining: $totalCount',
    );
  }

  /// 清理资源
  void dispose() {
    cancelAll();
  }

  /// 清空失败的任务（用于重试时保留已完成的任务）
  void clearFailed() {
    Log.i('ImageDownloadQueue: Clearing ${_failedItems.length} failed items');
    _failedItems.clear();
    _terminalError = null;
    // 重置章节统计（只保留已完成的）
    final failedEps = <int>{};
    for (var entry in _episodeTotalCounts.entries) {
      final total = entry.value;
      final completed = _episodeCompletedCounts[entry.key] ?? 0;
      if (completed < total) {
        failedEps.add(entry.key);
      }
    }
    // 移除没有完成的章节统计
    for (var ep in failedEps) {
      _episodeTotalCounts.remove(ep);
      _episodeCompletedCounts.remove(ep);
      _completedEpisodes.remove(ep);
    }
  }
}

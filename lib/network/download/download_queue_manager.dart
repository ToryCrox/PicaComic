import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/log.dart';
import 'download_model.dart';

/// 下载队列管理器
/// 
/// 负责管理所有下载任务的队列，控制并发下载数量，调度任务执行
class DownloadQueueManager {
  /// 等待队列 - 等待执行的任务
  final Queue<DownloadingTask> _waitingQueue = Queue<DownloadingTask>();

  /// 正在执行的任务映射表
  final Map<String, DownloadingTask> _runningTasks = {};

  /// 最大并发任务数（同时下载的漫画数量）
  final int maxConcurrentTasks;

  /// 是否正在运行
  bool _isRunning = false;

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 获取等待队列的只读视图
  Queue<DownloadingTask> get waitingQueue => Queue.from(_waitingQueue);

  /// 获取正在运行的任务数量
  int get runningTasksCount => _runningTasks.length;

  /// 获取总任务数量
  int get totalTasksCount => _waitingQueue.length + _runningTasks.length;

  /// 状态变更监听器
  final List<VoidCallback> _listeners = [];

  DownloadQueueManager({this.maxConcurrentTasks = 1});

  /// 添加监听器
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// 通知状态变更
  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }

  /// 添加任务到队列末尾
  void enqueue(DownloadingTask task) {
    if (_runningTasks.containsKey(task.id)) {
      Log.w('DownloadQueueManager: Task ${task.id} is already running');
      return;
    }

    if (_waitingQueue.any((t) => t.id == task.id)) {
      Log.w('DownloadQueueManager: Task ${task.id} is already in waiting queue');
      return;
    }

    _waitingQueue.addLast(task);
    Log.i('DownloadQueueManager: Task ${task.id} added to queue. Total: $totalTasksCount');
    _notifyListeners();

    // 如果队列正在运行，尝试调度下一个任务
    if (_isRunning) {
      _scheduleNext();
    }
  }

  /// 添加任务到队列开头（高优先级）
  void enqueueFirst(DownloadingTask task) {
    if (_runningTasks.containsKey(task.id)) {
      Log.w('DownloadQueueManager: Task ${task.id} is already running');
      return;
    }

    if (_waitingQueue.any((t) => t.id == task.id)) {
      Log.w('DownloadQueueManager: Task ${task.id} is already in waiting queue');
      return;
    }

    _waitingQueue.addFirst(task);
    Log.i('DownloadQueueManager: Task ${task.id} added to front of queue. Total: $totalTasksCount');
    _notifyListeners();

    // 如果队列正在运行，尝试调度下一个任务
    if (_isRunning) {
      _scheduleNext();
    }
  }

  /// 移除指定任务
  /// 
  /// 如果任务正在运行，会先停止任务再移除
  Future<void> removeTask(String taskId) async {
    // 检查是否在运行中
    final runningTask = _runningTasks[taskId];
    if (runningTask != null) {
      Log.i('DownloadQueueManager: Stopping and removing running task $taskId');
      await runningTask.stop();
      _runningTasks.remove(taskId);
      _notifyListeners();
      
      // 任务停止后，尝试调度下一个
      if (_isRunning) {
        _scheduleNext();
      }
      return;
    }

    // 从等待队列中移除
    final originalLength = _waitingQueue.length;
    _waitingQueue.removeWhere((task) => task.id == taskId);
    if (_waitingQueue.length < originalLength) {
      Log.i('DownloadQueueManager: Removed task $taskId from waiting queue');
      _notifyListeners();
    } else {
      Log.w('DownloadQueueManager: Task $taskId not found');
    }
  }

  /// 将任务移到队列首位
  void moveToFirst(String taskId) {
    // 如果任务正在运行，先暂停所有任务
    if (_runningTasks.containsKey(taskId)) {
      Log.i('DownloadQueueManager: Task $taskId is already running, pausing to move to first');
      final task = _runningTasks[taskId]!;
      pause();
      _waitingQueue.addFirst(task);
      start();
      return;
    }

    // 从等待队列中找到任务并移到首位
    DownloadingTask? targetTask;
    _waitingQueue.removeWhere((task) {
      if (task.id == taskId) {
        targetTask = task;
        return true;
      }
      return false;
    });

    if (targetTask != null) {
      _waitingQueue.addFirst(targetTask!);
      Log.i('DownloadQueueManager: Moved task $taskId to first');
      _notifyListeners();

      // 如果队列正在运行，需要重新调度
      if (_isRunning && _runningTasks.isEmpty) {
        _scheduleNext();
      }
    } else {
      Log.w('DownloadQueueManager: Task $taskId not found in waiting queue');
    }
  }

  /// 启动队列处理
  void start() {
    if (_isRunning) {
      Log.w('DownloadQueueManager: Already running');
      return;
    }

    _isRunning = true;
    Log.i('DownloadQueueManager: Starting queue manager');
    _notifyListeners();

    // 开始调度任务
    _scheduleNext();
  }

  /// 暂停队列处理
  void pause() {
    if (!_isRunning) {
      Log.w('DownloadQueueManager: Already paused');
      return;
    }

    _isRunning = false;
    Log.i('DownloadQueueManager: Pausing queue manager');

    // 暂停所有正在运行的任务
    for (var task in _runningTasks.values) {
      task.pause();
    }

    _notifyListeners();
  }

  /// 停止队列处理并清空所有任务
  Future<void> stopAll() async {
    _isRunning = false;
    Log.i('DownloadQueueManager: Stopping all tasks');

    // 停止所有正在运行的任务
    final runningTasksList = _runningTasks.values.toList();
    for (var task in runningTasksList) {
      await task.stop();
    }

    _runningTasks.clear();
    _waitingQueue.clear();
    _notifyListeners();
  }

  /// 调度下一个任务
  void _scheduleNext() {
    if (!_isRunning) {
      return;
    }

    // 如果已达到最大并发数，不再调度
    if (_runningTasks.length >= maxConcurrentTasks) {
      Log.d('DownloadQueueManager: Max concurrent tasks reached (${_runningTasks.length}/$maxConcurrentTasks)');
      return;
    }

    // 如果没有等待的任务，停止运行
    if (_waitingQueue.isEmpty) {
      if (_runningTasks.isEmpty) {
        Log.i('DownloadQueueManager: No more tasks, stopping');
        _isRunning = false;
        _notifyListeners();
      }
      return;
    }

    // 从队列中取出下一个任务
    final task = _waitingQueue.removeFirst();
    _runningTasks[task.id] = task;
    
    Log.i('DownloadQueueManager: Starting task ${task.id}. Running: ${_runningTasks.length}, Waiting: ${_waitingQueue.length}');
    _notifyListeners();

    // 启动任务
    task.start();
  }

  /// 任务完成回调
  /// 
  /// 由外部在任务完成时调用
  void onTaskFinished(String taskId) {
    final task = _runningTasks.remove(taskId);
    if (task == null) {
      Log.w('DownloadQueueManager: Task $taskId not found in running tasks');
      return;
    }

    Log.i('DownloadQueueManager: Task $taskId finished. Running: ${_runningTasks.length}, Waiting: ${_waitingQueue.length}');
    _notifyListeners();

    // 调度下一个任务
    if (_isRunning) {
      _scheduleNext();
    }
  }

  /// 任务出错回调
  /// 
  /// 由外部在任务出错时调用
  void onTaskError(String taskId) {
    Log.e('DownloadQueueManager: Task $taskId encountered an error');
    // 错误处理由任务自己的重试机制处理
    // 这里只记录日志
    _notifyListeners();
  }

  /// 获取所有任务（等待 + 运行中）
  List<DownloadingTask> getAllTasks() {
    return [..._runningTasks.values, ..._waitingQueue];
  }

  /// 清理资源
  void dispose() {
    _listeners.clear();
  }
}

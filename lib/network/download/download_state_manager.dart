import 'package:flutter/foundation.dart';

/// 下载任务状态
enum DownloadTaskStatus {
  /// 等待开始
  waiting,
  
  /// 下载中
  downloading,
  
  /// 已暂停
  paused,
  
  /// 已完成
  completed,
  
  /// 失败
  failed,
  
  /// 已取消
  canceled,
}

/// 下载状态
/// 
/// 记录单个下载任务的完整状态信息
class DownloadState {
  /// 任务ID
  final String taskId;

  /// 任务标题
  final String title;

  /// 总图片数量
  final int totalImages;

  /// 已下载的图片数量
  final int downloadedImages;

  /// 失败的图片数量
  final int failedImages;

  /// 任务状态
  final DownloadTaskStatus status;

  /// 当前章节索引
  final int currentEpisode;

  /// 当前图片索引
  final int currentImageIndex;

  /// 下载速度（字节/秒）
  final int speedBytesPerSecond;

  /// 错误信息
  final String? errorMessage;

  /// 创建时间
  final DateTime createdAt;

  /// 最后更新时间
  final DateTime updatedAt;

  DownloadState({
    required this.taskId,
    required this.title,
    required this.totalImages,
    required this.downloadedImages,
    required this.failedImages,
    required this.status,
    required this.currentEpisode,
    required this.currentImageIndex,
    this.speedBytesPerSecond = 0,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 下载进度（0.0 - 1.0）
  double get progress => totalImages > 0 ? downloadedImages / totalImages : 0.0;

  /// 进度百分比文本
  String get progressText => '${downloadedImages}/${totalImages}';

  /// 进度百分比
  int get progressPercent => (progress * 100).toInt();

  /// 是否正在下载
  bool get isDownloading => status == DownloadTaskStatus.downloading;

  /// 是否已完成
  bool get isCompleted => status == DownloadTaskStatus.completed;

  /// 是否失败
  bool get isFailed => status == DownloadTaskStatus.failed;

  /// 是否可以恢复
  bool get canResume =>
      status == DownloadTaskStatus.paused || status == DownloadTaskStatus.failed;

  /// 复制并更新状态
  DownloadState copyWith({
    String? taskId,
    String? title,
    int? totalImages,
    int? downloadedImages,
    int? failedImages,
    DownloadTaskStatus? status,
    int? currentEpisode,
    int? currentImageIndex,
    int? speedBytesPerSecond,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return DownloadState(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      totalImages: totalImages ?? this.totalImages,
      downloadedImages: downloadedImages ?? this.downloadedImages,
      failedImages: failedImages ?? this.failedImages,
      status: status ?? this.status,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      currentImageIndex: currentImageIndex ?? this.currentImageIndex,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'DownloadState($taskId: $progressText, status: $status, speed: ${speedBytesPerSecond}B/s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadState &&
        other.taskId == taskId &&
        other.downloadedImages == downloadedImages &&
        other.status == status &&
        other.speedBytesPerSecond == speedBytesPerSecond;
  }

  @override
  int get hashCode =>
      taskId.hashCode ^
      downloadedImages.hashCode ^
      status.hashCode ^
      speedBytesPerSecond.hashCode;
}

/// 状态管理器
/// 
/// 管理所有下载任务的状态，提供状态查询和更新通知
class DownloadStateManager extends ChangeNotifier {
  /// 状态映射表
  final Map<String, DownloadState> _states = {};

  /// 获取所有状态
  Map<String, DownloadState> get states => Map.unmodifiable(_states);

  /// 获取状态数量
  int get count => _states.length;

  /// 获取指定任务的状态
  DownloadState? getState(String taskId) {
    return _states[taskId];
  }

  /// 更新状态
  /// 
  /// 如果状态有变化，会通知所有监听器
  void updateState(DownloadState state) {
    final oldState = _states[state.taskId];
    
    // 只在状态真正改变时才更新和通知
    if (oldState != state) {
      _states[state.taskId] = state;
      notifyListeners();
    }
  }

  /// 批量更新状态
  void updateStates(List<DownloadState> states) {
    bool changed = false;
    
    for (var state in states) {
      final oldState = _states[state.taskId];
      if (oldState != state) {
        _states[state.taskId] = state;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// 移除状态
  void removeState(String taskId) {
    if (_states.remove(taskId) != null) {
      notifyListeners();
    }
  }

  /// 批量移除状态
  void removeStates(List<String> taskIds) {
    bool changed = false;
    
    for (var taskId in taskIds) {
      if (_states.remove(taskId) != null) {
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// 清除所有状态
  void clear() {
    if (_states.isNotEmpty) {
      _states.clear();
      notifyListeners();
    }
  }

  /// 获取所有正在下载的任务
  List<DownloadState> getDownloadingTasks() {
    return _states.values
        .where((state) => state.status == DownloadTaskStatus.downloading)
        .toList();
  }

  /// 获取所有已完成的任务
  List<DownloadState> getCompletedTasks() {
    return _states.values
        .where((state) => state.status == DownloadTaskStatus.completed)
        .toList();
  }

  /// 获取所有失败的任务
  List<DownloadState> getFailedTasks() {
    return _states.values
        .where((state) => state.status == DownloadTaskStatus.failed)
        .toList();
  }

  /// 获取总下载进度
  double getTotalProgress() {
    if (_states.isEmpty) return 0.0;

    final totalImages = _states.values.fold<int>(
      0,
      (sum, state) => sum + state.totalImages,
    );

    if (totalImages == 0) return 0.0;

    final downloadedImages = _states.values.fold<int>(
      0,
      (sum, state) => sum + state.downloadedImages,
    );

    return downloadedImages / totalImages;
  }

  /// 获取总下载速度
  int getTotalSpeed() {
    return _states.values.fold<int>(
      0,
      (sum, state) =>
          sum +
          (state.status == DownloadTaskStatus.downloading
              ? state.speedBytesPerSecond
              : 0),
    );
  }

  @override
  void dispose() {
    _states.clear();
    super.dispose();
  }
}

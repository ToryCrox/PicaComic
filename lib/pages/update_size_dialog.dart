import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/tools/translations.dart';

/// 更新漫画文件大小对话框
///
/// 用于批量更新已下载漫画的文件大小信息
/// 显示更新进度、前后大小对比以及更新结果统计
class UpdateSizeDialog extends StatefulWidget {
  /// 待更新的漫画列表
  final List<DownloadedItem> comics;

  /// 更新完成后的回调函数
  final VoidCallback onComplete;

  const UpdateSizeDialog({
    Key? key,
    required this.comics,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<UpdateSizeDialog> createState() => _UpdateSizeDialogState();
}

/// 更新任务的状态枚举
enum UpdateStatus {
  waiting, // 等待更新
  updating, // 更新中
  success, // 更新成功
  failed, // 更新失败
}

/// 单个更新任务的数据模型
class UpdateTask {
  /// 待更新的漫画对象
  final DownloadedItem comic;

  /// 更新前的文件大小（MB）
  double oldSize;

  /// 更新后的文件大小（MB）
  double newSize;

  /// 当前任务状态
  UpdateStatus status;

  /// 错误信息（如果更新失败）
  String? errorMessage;

  UpdateTask({
    required this.comic,
    required this.oldSize,
    this.newSize = 0,
    this.status = UpdateStatus.waiting,
  });

  /// 判断文件大小是否发生变化
  /// 使用 0.01 MB 作为阈值，避免浮点数精度问题
  bool get hasChanged => (newSize - oldSize).abs() > 0.01;

  /// 获取变化量
  double get change => newSize - oldSize;
}

class _UpdateSizeDialogState extends State<UpdateSizeDialog> {
  /// 是否正在加载任务列表
  bool _isLoading = true;

  /// 是否正在执行更新操作
  bool _isUpdating = false;

  /// 所有更新任务的列表
  final List<UpdateTask> _tasks = [];

  /// 成功更新的任务数量
  int _successCount = 0;

  /// 失败的任务数量
  int _failCount = 0;

  /// 文件大小发生变化的任务数量
  int _changedCount = 0;

  /// 总的大小变化量 (MB)
  double _totalSizeChange = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  /// 加载待更新的任务列表
  /// 为每个漫画创建一个 UpdateTask 对象
  Future<void> _loadTasks() async {
    for (var comic in widget.comics) {
      _tasks.add(UpdateTask(
        comic: comic,
        oldSize: comic.comicSize ?? 0,
      ));
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 开始执行更新操作
  /// 逐个更新每个漫画的文件大小，并更新UI显示进度
  Future<void> _startUpdate() async {
    setState(() {
      _isUpdating = true;
      _successCount = 0;
      _failCount = 0;
      _changedCount = 0;
      _totalSizeChange = 0;
    });

    for (var task in _tasks) {
      // 更新任务状态为"更新中"
      setState(() {
        task.status = UpdateStatus.updating;
      });

      try {
        // 调用下载管理器更新漫画文件大小
        final newSize = await downloadManager.updateComicSize(task.comic);

        if (mounted) {
          setState(() {
            task.newSize = newSize;
            task.status = UpdateStatus.success;
            _successCount++;
            // 如果文件大小发生变化，增加变化计数和总变化量
            if (task.hasChanged) {
              _changedCount++;
              _totalSizeChange += task.change;
            }
          });
        }
      } catch (e) {
        // 捕获错误并标记任务为失败
        if (mounted) {
          setState(() {
            task.status = UpdateStatus.failed;
            task.errorMessage = e.toString();
            _failCount++;
          });
        }
      }

      // 添加微小延迟以避免UI卡顿
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('更新漫画文件大小'.tl),
      content: SizedBox(
        width: 600,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return ListTile(
                          title: Text(
                            task.comic.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '原大小: ${task.oldSize.toStringAsFixed(2)} MB',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (task.status == UpdateStatus.success)
                                Row(
                                  children: [
                                    Text(
                                      '新大小: ${task.newSize.toStringAsFixed(2)} MB',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: task.hasChanged
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                        fontWeight: task.hasChanged
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                    ),
                                    if (task.hasChanged) ...[
                                      const SizedBox(width: 8),
                                      _buildChangeTag(context, task),
                                    ],
                                  ],
                                ),
                              if (task.errorMessage != null)
                                SelectableText(
                                  task.errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                          trailing: _buildStatusIcon(task.status),
                          dense: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isUpdating || (_successCount + _failCount > 0))
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: _tasks.isEmpty
                              ? 0
                              : (_successCount + _failCount) / _tasks.length,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _buildSummaryText(),
                          style: TextStyle(
                            color: _failCount > 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                ],
              ),
      ),
      actions: [
        if (!_isUpdating && _successCount + _failCount == 0) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'.tl),
          ),
          FilledButton(
            onPressed: _startUpdate,
            child: Text('确认更新'.tl),
          ),
        ],
        if (!_isUpdating && (_successCount + _failCount > 0)) ...[
          FilledButton(
            onPressed: () {
              widget.onComplete();
              Navigator.of(context).pop();
            },
            child: Text('关闭'.tl),
          ),
        ],
      ],
    );
  }

  /// 构建变化标签
  Widget _buildChangeTag(BuildContext context, UpdateTask task) {
    final isIncreased = task.change > 0;
    final color = isIncreased ? Colors.red : Colors.green;
    final icon = isIncreased ? Icons.arrow_upward : Icons.arrow_downward;
    final text =
        '${isIncreased ? "+" : ""}${task.change.toStringAsFixed(2)} MB';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建总结文本
  String _buildSummaryText() {
    final sb = StringBuffer();
    sb.write('成功: $_successCount, 失败: $_failCount');

    if (_changedCount > 0) {
      sb.write(', $_changedCount 个发生变化');
      sb.write('\n总变动: ');
      if (_totalSizeChange > 0) {
        sb.write('+${_totalSizeChange.toStringAsFixed(2)} MB');
      } else if (_totalSizeChange < 0) {
        sb.write('${_totalSizeChange.toStringAsFixed(2)} MB');
      } else {
        sb.write('0 MB');
      }
    } else {
      sb.write(', 无文件大小变化');
    }

    return sb.toString();
  }

  /// 根据任务状态构建对应的图标
  ///
  /// - waiting: 灰色时钟图标
  /// - updating: 加载中的圆形进度条
  /// - success: 绿色对勾图标
  /// - failed: 红色错误图标
  Widget _buildStatusIcon(UpdateStatus status) {
    switch (status) {
      case UpdateStatus.waiting:
        return const Icon(Icons.access_time, size: 20, color: Colors.grey);
      case UpdateStatus.updating:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case UpdateStatus.success:
        return const Icon(Icons.check_circle, size: 20, color: Colors.green);
      case UpdateStatus.failed:
        return const Icon(Icons.error, size: 20, color: Colors.red);
    }
  }
}

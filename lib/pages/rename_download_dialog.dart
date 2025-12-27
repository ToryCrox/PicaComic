import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/tools/translations.dart';

class RenameDownloadDialog extends StatefulWidget {
  final List<DownloadedItem> comics;
  final VoidCallback onComplete;

  const RenameDownloadDialog({
    Key? key,
    required this.comics,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<RenameDownloadDialog> createState() => _RenameDownloadDialogState();
}

enum RenameStatus {
  waiting,
  renaming,
  success,
  failed,
}

class RenameTask {
  final DownloadedItem comic;
  String oldName;
  String newName;
  RenameStatus status;
  String? errorMessage;

  RenameTask({
    required this.comic,
    required this.oldName,
    required this.newName,
    this.status = RenameStatus.waiting,
  });
}

class _RenameDownloadDialogState extends State<RenameDownloadDialog> {
  bool _isLoading = true;
  bool _isRenaming = false;
  final List<RenameTask> _tasks = [];
  int _successCount = 0;
  int _failCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    for (var comic in widget.comics) {
      final oldName = await downloadManager.getDirectoryName(comic.id);
      final newName = downloadManager.generateDirectoryName(comic);
      _tasks.add(RenameTask(
        comic: comic,
        oldName: oldName,
        newName: newName,
      ));
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startRename() async {
    setState(() {
      _isRenaming = true;
      _successCount = 0;
      _failCount = 0;
    });

    for (var task in _tasks) {
      setState(() {
        task.status = RenameStatus.renaming;
      });

      // 如果新旧名称相同，直接标记为成功
      if (task.oldName == task.newName) {
        setState(() {
          task.status = RenameStatus.success;
          _successCount++;
        });
        continue;
      }

      final error = await downloadManager
          .renameComicDirectory(task.comic.id, task.newName);

      if (mounted) {
        setState(() {
          if (error == null) {
            task.status = RenameStatus.success;
            _successCount++;
          } else {
            task.status = RenameStatus.failed;
            task.errorMessage = error;
            _failCount++;
          }
        });
      }

      // 添加微小延迟以避免UI卡顿
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      setState(() {
        _isRenaming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('重命名下载目录'.tl),
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
                              SelectableText(
                                '原: ${task.oldName}',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                              ),
                              SelectableText(
                                '新: ${task.newName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
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
                  if (_isRenaming || (_successCount + _failCount > 0))
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: _tasks.isEmpty
                              ? 0
                              : (_successCount + _failCount) / _tasks.length,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '成功: $_successCount, 失败: $_failCount'.tl,
                          style: TextStyle(
                            color: _failCount > 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
      ),
      actions: [
        if (!_isRenaming && _successCount + _failCount == 0) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'.tl),
          ),
          FilledButton(
            onPressed: _startRename,
            child: Text('确认重命名'.tl),
          ),
        ],
        if (!_isRenaming && (_successCount + _failCount > 0)) ...[
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

  Widget _buildStatusIcon(RenameStatus status) {
    switch (status) {
      case RenameStatus.waiting:
        return const Icon(Icons.access_time, size: 20, color: Colors.grey);
      case RenameStatus.renaming:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case RenameStatus.success:
        return const Icon(Icons.check_circle, size: 20, color: Colors.green);
      case RenameStatus.failed:
        return const Icon(Icons.error, size: 20, color: Colors.red);
    }
  }
}

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/local_repository_manager.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:path/path.dart' as Path;

/// 导入本地漫画对话框
class ImportLocalComicDialog extends StatefulWidget {
  const ImportLocalComicDialog({Key? key}) : super(key: key);

  @override
  State<ImportLocalComicDialog> createState() => _ImportLocalComicDialogState();
}

class _ImportLocalComicDialogState extends State<ImportLocalComicDialog> {
  List<RepositoryInfo> repositories = [];
  String? selectedRepositoryName;
  String? draggedFolderPath;
  List<Map<String, dynamic>> scannedComics = [];
  bool scanning = false;
  bool importing = false;
  String? titlePrefix;
  int? selectedTagId;
  List<DownloadTag> allTags = [];
  String importResult = '';

  @override
  void initState() {
    super.initState();
    _loadRepositories();
    _loadTags();
  }

  Future<void> _loadRepositories() async {
    final repos = await LocalRepositoryManager().getAllRepositories();
    setState(() {
      repositories = repos;
      if (repos.isNotEmpty && selectedRepositoryName == null) {
        selectedRepositoryName = repos.first.name;
      }
    });
  }

  Future<void> _loadTags() async {
    final tags = await downloadManager.getAllTags();
    setState(() {
      allTags = tags;
    });
  }

  Future<void> _scanComics() async {
    if (draggedFolderPath == null || selectedRepositoryName == null) {
      return;
    }

    setState(() {
      scanning = true;
      scannedComics = [];
    });

    try {
      final repositoryPath =
          await LocalRepositoryManager().getRepositoryPath(selectedRepositoryName!);
      if (repositoryPath == null) {
        setState(() {
          scanning = false;
          importResult = '存储库不存在';
        });
        return;
      }

      final comics = await downloadManager.scanComicDirectories(
        draggedFolderPath!,
        repositoryPath,
      );

      setState(() {
        scannedComics = comics;
        scanning = false;
      });
    } catch (e) {
      setState(() {
        scanning = false;
        importResult = '扫描失败: $e';
      });
    }
  }

  Future<void> _importComics() async {
    if (draggedFolderPath == null || selectedRepositoryName == null) {
      return;
    }

    setState(() {
      importing = true;
      importResult = '';
    });

    try {
      final result = await downloadManager.importLocalComics(
        draggedFolderPath: draggedFolderPath!,
        repositoryName: selectedRepositoryName!,
        titlePrefix: titlePrefix,
        tagId: selectedTagId,
      );

      setState(() {
        importing = false;
        if (result['success'] == true) {
          final successCount = result['successCount'] as int;
          final failCount = result['failCount'] as int;
          importResult = '导入完成：成功 $successCount 个，失败 $failCount 个';
          if (result['errors'] != null) {
            final errors = result['errors'] as List<String>;
            if (errors.isNotEmpty) {
              importResult += '\n错误：${errors.join('\n')}';
            }
          }
        } else {
          importResult = result['message'] as String? ?? '导入失败';
        }
      });
    } catch (e) {
      setState(() {
        importing = false;
        importResult = '导入失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "导入本地漫画".tl,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            // 存储库选择
            Row(
              children: [
                Text("存储库：".tl),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: selectedRepositoryName,
                    isExpanded: true,
                    items: repositories.map((repo) {
                      return DropdownMenuItem<String>(
                        value: repo.name,
                        child: Text(repo.title),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedRepositoryName = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 标题前缀输入
            TextField(
              decoration: InputDecoration(
                labelText: "标题前缀（可选）".tl,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                titlePrefix = value.isEmpty ? null : value;
              },
            ),
            const SizedBox(height: 16),
            // 标签选择
            Row(
              children: [
                Text("标签（可选）：".tl),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int?>(
                    value: selectedTagId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('无'),
                      ),
                      ...allTags.map((tag) {
                        return DropdownMenuItem<int?>(
                          value: tag.id,
                          child: Text(tag.name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedTagId = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 拖拽区域
            Expanded(
              child: DropTarget(
                onDragDone: (details) {
                  final files = details.files;
                  if (files.isNotEmpty) {
                    final path = files.first.path;
                    final dir = Directory(path);
                    if (dir.existsSync()) {
                      setState(() {
                        draggedFolderPath = path;
                        scannedComics = [];
                        importResult = '';
                      });
                      _scanComics();
                    }
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: draggedFolderPath != null
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                      width: 2,
                      style: BorderStyle.solid,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open,
                          size: 48,
                          color: draggedFolderPath != null
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          draggedFolderPath != null
                              ? Path.basename(draggedFolderPath!)
                              : "拖拽文件夹到这里".tl,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (draggedFolderPath != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            draggedFolderPath!,
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 扫描结果列表
            if (scanning)
              const Center(child: CircularProgressIndicator())
            else if (scannedComics.isNotEmpty) ...[
              Text(
                "找到 ${scannedComics.length} 个漫画目录：".tl,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: scannedComics.length,
                  itemBuilder: (context, index) {
                    final comic = scannedComics[index];
                    return ListTile(
                      dense: true,
                      title: SelectableText(comic['name'] as String),
                      subtitle: SelectableText(comic['relativePath'] as String),
                      trailing: SelectableText('${comic['imageCount']} 张图片'),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 导入结果
            if (importResult.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: importResult.contains('成功')
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  importResult,
                  style: TextStyle(
                    color: importResult.contains('成功')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // 按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: importing ? null : () => Navigator.pop(context),
                  child: Text("取消".tl),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (importing || scannedComics.isEmpty)
                      ? null
                      : _importComics,
                  child: importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text("导入".tl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


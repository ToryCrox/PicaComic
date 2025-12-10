import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/local_repository_manager.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/image_utils.dart';
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
  List<int> selectedTagIds = [];
  List<DownloadTag> allTags = [];
  String importResult = '';
  final TextEditingController _titlePrefixController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRepositories();
    _loadTags();
  }

  @override
  void dispose() {
    _titlePrefixController.dispose();
    super.dispose();
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

      final draggedDir = Directory(draggedFolderPath!);
      if (!await draggedDir.exists()) {
        setState(() {
          scanning = false;
          importResult = '文件夹不存在';
        });
        return;
      }

      // 检查是否有子目录（只检查直接子目录）
      bool hasSubDirectories = false;
      await for (var entity in draggedDir.list()) {
        if (entity is Directory) {
          hasSubDirectories = true;
          break;
        }
      }

      List<Map<String, dynamic>> comics = [];

      // 如果没有子目录，检查该文件夹本身是否就是漫画目录
      if (!hasSubDirectories) {
        int imageCount = 0;
        String? firstImagePath;

        try {
          await for (var file in draggedDir.list(recursive: true)) {
            if (file is File && predictImageFile(file)) {
              imageCount++;
              if (firstImagePath == null) {
                firstImagePath = file.path;
              }
            }
          }
        } catch (e) {
          // 忽略无法访问的文件
        }

        // 如果包含至少3张图片，则将该文件夹作为漫画目录
        if (imageCount >= 3) {
          final relativePath = Path.relative(draggedDir.path, from: repositoryPath);
          final relativeImagePath = firstImagePath != null
              ? Path.relative(firstImagePath, from: draggedDir.path)
              : null;

          comics.add({
            'path': draggedDir.path,
            'name': Path.basename(draggedDir.path),
            'relativePath': relativePath,
            'imageCount': imageCount,
            'coverImagePath': relativeImagePath,
          });
        }
      }

      // 如果有子目录或者当前文件夹不是漫画目录，则扫描子目录
      if (hasSubDirectories || comics.isEmpty) {
        final scannedComics = await downloadManager.scanComicDirectories(
          draggedFolderPath!,
          repositoryPath,
        );
        comics = scannedComics;
      }

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
        tagIds: selectedTagIds.isEmpty ? null : selectedTagIds,
        comicDirs: scannedComics,
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

  /// 显示标签搜索对话框
  Future<void> _showTagSearchDialog(BuildContext context) async {
    String searchQuery = '';
    List<DownloadTag> filteredTags = List.from(allTags);
    // 使用临时列表来跟踪对话框内的选择状态
    List<int> tempSelectedTagIds = List.from(selectedTagIds);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: Container(
                width: 400,
                height: 500,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "选择标签".tl,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    // 搜索框
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: "搜索标签".tl,
                        hintText: "输入标签名称".tl,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setDialogState(() {
                                    searchQuery = '';
                                    filteredTags = List.from(allTags);
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          searchQuery = value;
                          if (value.isEmpty) {
                            filteredTags = List.from(allTags);
                          } else {
                            filteredTags = allTags
                                .where((tag) => tag.name
                                    .toLowerCase()
                                    .contains(value.toLowerCase()))
                                .toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // 标签列表
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredTags.length,
                        itemBuilder: (context, index) {
                          final tag = filteredTags[index];
                          final isSelected = tempSelectedTagIds.contains(tag.id);
                          return CheckboxListTile(
                            title: Text(tag.name),
                            value: isSelected,
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  if (!tempSelectedTagIds.contains(tag.id)) {
                                    tempSelectedTagIds.add(tag.id);
                                  }
                                } else {
                                  tempSelectedTagIds.remove(tag.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              tempSelectedTagIds.clear();
                            });
                          },
                          child: Text("清除".tl),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text("取消".tl),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              selectedTagIds = List.from(tempSelectedTagIds);
                            });
                            Navigator.pop(dialogContext);
                          },
                          child: Text("确定".tl),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
              controller: _titlePrefixController,
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
                  child: InkWell(
                    onTap: () => _showTagSearchDialog(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: selectedTagIds.isEmpty
                                ? Text(
                                    '无',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                    ),
                                  )
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: selectedTagIds.map((tagId) {
                                      final tag = allTags
                                          .where((tag) => tag.id == tagId)
                                          .firstOrNull;
                                      if (tag == null) return const SizedBox.shrink();
                                      return Chip(
                                        label: Text(tag.name),
                                        onDeleted: () {
                                          setState(() {
                                            selectedTagIds.remove(tagId);
                                          });
                                        },
                                        deleteIcon: const Icon(Icons.close, size: 18),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
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
                      final folderName = Path.basename(path);
                      setState(() {
                        draggedFolderPath = path;
                        titlePrefix = folderName;
                        scannedComics = [];
                        importResult = '';
                        selectedTagIds = [];
                      });
                      _titlePrefixController.text = folderName;
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
                          size: 30,
                          color: draggedFolderPath != null
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        const SizedBox(height: 3),
                        SelectableText(
                          draggedFolderPath != null
                              ? Path.basename(draggedFolderPath!)
                              : "拖拽文件夹到这里".tl,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (draggedFolderPath != null) ...[
                          const SizedBox(height: 0),
                          SelectableText(
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


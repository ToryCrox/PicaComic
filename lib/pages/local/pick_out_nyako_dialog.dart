import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as Path;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'dart:io';

import '../../tools/translations.dart';

class PickOutNyakoDialog extends StatefulWidget {
  const PickOutNyakoDialog({Key? key}) : super(key: key);

  @override
  State<PickOutNyakoDialog> createState() => _PickOutNyakoDialogState();
}

class _PickOutNyakoDialogState extends State<PickOutNyakoDialog> {
  String? _sourcePath;
  bool _isScanning = false;
  bool _isMoving = false;
  MoveTargets? _moveTargets;

  // 错误日志列表
  final List<String> _errorLogs = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: DefaultTabController(
        length: 2,
        child: Container(
          width: 800,
          height: 1200,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                "文件整理工具".tl,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildSourceSelector(),
              const SizedBox(height: 8),
              TabBar(
                tabs: [
                  Tab(text: "预览".tl),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("日志".tl),
                        if (_errorLogs.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${_errorLogs.length}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [_buildPreviewList(), _buildLogList()],
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceSelector() {
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        if (event.session.items.isEmpty) return DropOperation.none;
        final item = event.session.items.first;
        if (item.canProvide(Formats.fileUri)) return DropOperation.copy;
        return DropOperation.none;
      },
      onPerformDrop: (event) async {
        final item = event.session.items.first;
        final reader = item.dataReader!;
        reader.getValue(Formats.fileUri, (value) {
          if (value != null) {
            final path = value.toFilePath();
            if (FileSystemEntity.isDirectorySync(path)) {
              setState(() {
                _sourcePath = path;
                _scanDirectory(path);
              });
            }
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_sourcePath ?? "请选择或拖入文件夹".tl)),
            ElevatedButton(onPressed: _pickDirectory, child: Text("选择文件夹".tl)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewList() {
    if (_isScanning) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_moveTargets == null || _moveTargets!.targetMoveMap.isEmpty) {
      return Center(child: Text("没有文件需要移动".tl));
    }
    final targets = _moveTargets!.targetMoveMap.entries.toList();
    return ListView.builder(
      itemCount: targets.length,
      itemBuilder: (context, index) {
        final entry = targets[index];
        return ListTile(
          title: Text("源: ${entry.key.path}"),
          subtitle: Text("目标: ${entry.value}"),
          dense: true,
        );
      },
    );
  }

  Widget _buildLogList() {
    if (_errorLogs.isEmpty) {
      return Center(child: Text("无错误日志".tl));
    }
    return ListView.builder(
      itemCount: _errorLogs.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const Icon(Icons.error, color: Colors.red, size: 20),
          title: Text(
            _errorLogs[index],
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
          dense: true,
        );
      },
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text("取消".tl),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed:
              (_moveTargets == null ||
                  _moveTargets!.targetMoveMap.isEmpty ||
                  _isMoving)
              ? null
              : _executeMoves,
          child: _isMoving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text("执行整理".tl),
        ),
      ],
    );
  }

  Future<void> _pickDirectory() async {
    final path = await getDirectoryPath(confirmButtonText: "选择".tl);
    if (path != null) {
      setState(() {
        _sourcePath = path;
        _scanDirectory(path);
      });
    }
  }

  void _logError(String message) {
    setState(() {
      _errorLogs.add(message);
    });
  }

  Future<void> _scanDirectory(String path, {bool clearLogs = true}) async {
    setState(() {
      _isScanning = true;
      _moveTargets = null;
      if (clearLogs) {
        _errorLogs.clear();
      }
    });

    try {
      final dir = Directory(path);
      // Run in a separate future to avoid blocking UI
      final targets = collectMoveTargets(dir, dir);
      setState(() {
        _moveTargets = targets;
      });
    } catch (e, s) {
      debugPrint("Scan error: $e\n$s");
      _logError("Scan error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _executeMoves() async {
    if (_moveTargets == null) return;
    setState(() {
      _isMoving = true;
    });

    try {
      await executeMoves(_moveTargets!);
      if (mounted) {
        if (_sourcePath != null) {
          // 重新扫描但不清除日志
          _scanDirectory(_sourcePath!, clearLogs: false);
        }
      }
    } catch (e) {
      debugPrint("Move execution error: $e");
      _logError("Execution error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isMoving = false;
        });
      }
    }
  }

  // --- Logic from pick_out_nyako_pics.dart ---

  static const supportedExtensions = {'.7z', '.rar', '.zip', '.mp4'};

  String formatDirectoryName(String name) {
    final parts = name.split('.');
    if (parts.length == 2) {
      return '${parts[0].padLeft(2, '0')}.${parts[1].padLeft(2, '0')}';
    }
    return name;
  }

  bool isTargetFile(FileSystemEntity entity) {
    if (entity is Directory) return true;
    if (entity is File) {
      final extension = Path.extension(entity.path);
      return supportedExtensions.contains(extension);
    }
    return false;
  }

  MoveTargets collectMoveTargets(Directory srcDir, Directory destDir) {
    final targetMoveMap = <FileSystemEntity, String>{};
    final subDirectories = <Directory>{};

    try {
      if (!srcDir.existsSync()) {
        _logError("源目录不存在: ${srcDir.path}");
        return MoveTargets({}, {});
      }

      for (final subDir in srcDir.listSync()) {
        if (subDir is! Directory) continue;

        final subDirName = formatDirectoryName(Path.basename(subDir.path));
        bool hasTarget = false;

        try {
          for (final file in subDir.listSync()) {
            if (!isTargetFile(file)) continue;

            hasTarget = true;
            final fileName = Path.basename(file.path);
            final newFileName = '[$subDirName] $fileName';
            targetMoveMap[file] = Path.join(destDir.path, newFileName);
          }
        } catch (e) {
          _logError("扫描子目录失败 ${subDir.path}: $e");
        }

        if (hasTarget) {
          subDirectories.add(subDir);
        }
      }
    } catch (e) {
      _logError("扫描目录失败 ${srcDir.path}: $e");
    }

    return MoveTargets(targetMoveMap, subDirectories);
  }

  Future<void> cleanUpEmptyDirectories(Set<Directory> directories) async {
    for (final dir in directories) {
      try {
        if (!await dir.exists()) continue;
        final contents = await dir.list().toList();
        if (contents.isEmpty) {
          await dir.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete dir: $e');
        _logError("清理空目录失败 ${dir.path}: $e");
      }
    }
  }

  Future<void> executeMoves(MoveTargets moveTargets) async {
    final targetMoveMap = moveTargets.targetMoveMap;

    for (final entry in targetMoveMap.entries) {
      final src = entry.key;
      final dest = entry.value;

      try {
        await src.rename(dest);
      } catch (e) {
        debugPrint("Error moving ${src.path}: $e");
        _logError("移动文件失败: ${Path.basename(src.path)} -> $e");
      }
    }

    await cleanUpEmptyDirectories(moveTargets.subDirectories);
  }
}

class MoveTargets {
  final Map<FileSystemEntity, String> targetMoveMap;
  final Set<Directory> subDirectories;

  MoveTargets(this.targetMoveMap, this.subDirectories);
}

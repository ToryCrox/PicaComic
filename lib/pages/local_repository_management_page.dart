import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_repository_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:file_selector/file_selector.dart';

class LocalRepositoryManagementPage extends StatefulWidget {
  const LocalRepositoryManagementPage({Key? key}) : super(key: key);

  @override
  State<LocalRepositoryManagementPage> createState() =>
      _LocalRepositoryManagementPageState();
}

class _LocalRepositoryManagementPageState
    extends State<LocalRepositoryManagementPage> {
  List<RepositoryInfo> repositories = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadRepositories();
  }

  Future<void> _loadRepositories() async {
    setState(() => loading = true);
    final repos = await LocalRepositoryManager().getAllRepositories();
    setState(() {
      repositories = repos;
      loading = false;
    });
  }

  Future<void> _addRepository() async {
    final nameController = TextEditingController();
    final pathController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("添加存储库".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: "存储库名称".tl,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: InputDecoration(
                      labelText: "存储库路径".tl,
                      border: const OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    String? selectedPath;
                    if (App.isDesktop) {
                      selectedPath = await getDirectoryPath();
                    } else {
                      // 移动端暂不支持选择目录
                      return;
                    }
                    if (selectedPath != null) {
                      pathController.text = selectedPath;
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("取消".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("确认".tl),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.isNotEmpty &&
        pathController.text.isNotEmpty) {
      try {
        final success = await LocalRepositoryManager()
            .addRepository(nameController.text, pathController.text);
        if (success) {
          showToast(message: "存储库添加成功".tl);
          _loadRepositories();
        } else {
          showToast(message: "存储库添加失败：名称已存在或路径无效".tl);
        }
      } catch (e) {
        showToast(message: "存储库添加失败: $e".tl);
      }
    }
  }

  Future<void> _editRepository(RepositoryInfo repo) async {
    final nameController = TextEditingController(text: repo.name);
    final pathController = TextEditingController(text: repo.path);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("编辑存储库".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: "存储库名称".tl,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: InputDecoration(
                      labelText: "存储库路径".tl,
                      border: const OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    String? selectedPath;
                    if (App.isDesktop) {
                      selectedPath = await getDirectoryPath();
                    } else {
                      // 移动端暂不支持选择目录
                      return;
                    }
                    if (selectedPath != null) {
                      pathController.text = selectedPath;
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("取消".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("确认".tl),
          ),
        ],
      ),
    );

    if (result == true &&
        nameController.text.isNotEmpty &&
        pathController.text.isNotEmpty) {
      try {
        final success = await LocalRepositoryManager().updateRepository(
          repo.name,
          nameController.text,
          pathController.text,
        );
        if (success) {
          showToast(message: "存储库更新成功".tl);
          _loadRepositories();
        } else {
          showToast(message: "存储库更新失败：名称冲突或路径无效".tl);
        }
      } catch (e) {
        showToast(message: "存储库更新失败: $e".tl);
      }
    }
  }

  Future<void> _deleteRepository(RepositoryInfo repo) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("删除存储库".tl),
        content: Text("确定要删除存储库 \"${repo.name}\" 吗?".tl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("取消".tl),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("确认".tl),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await LocalRepositoryManager().removeRepository(repo.name);
        showToast(message: "存储库删除成功".tl);
        _loadRepositories();
      } catch (e) {
        showToast(message: "存储库删除失败: $e".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("存储库管理".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addRepository,
            tooltip: "添加存储库".tl,
          ),
        ],
      ),
      body: loading && repositories.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : repositories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        "暂无存储库".tl,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "点击右上角添加按钮创建存储库".tl,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: repositories.length,
                  itemBuilder: (context, index) {
                    final repo = repositories[index];
                    return ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(repo.name),
                      subtitle: Text(repo.path),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editRepository(repo),
                            tooltip: "编辑".tl,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteRepository(repo),
                            tooltip: "删除".tl,
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}


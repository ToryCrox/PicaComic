import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/tools/translations.dart';

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({Key? key}) : super(key: key);

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  List<TagInfo> tags = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() => loading = true);
    final tagData = await downloadManager.getAllTags();
    final tagList = <TagInfo>[];

    for (var tag in tagData) {
      final count = await downloadManager.getTagComicCount(tag.id);

      // 如果有封面漫画ID，获取其封面路径
      String? coverPath;
      if (tag.coverComicId != null) {
        final comic =
            await downloadManager.getDownloadedItemById(tag.coverComicId!);
        coverPath = comic?.coverPath;
      }

      tagList.add(TagInfo(
        id: tag.id,
        name: tag.name,
        coverPath: coverPath,
        comicCount: count,
      ));
    }

    setState(() {
      tags = tagList;
      loading = false;
    });
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("创建标签".tl),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "标签名称".tl,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
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

    if (result == true && controller.text.isNotEmpty) {
      try {
        await downloadManager.createTag(controller.text);
        showToast(message: "标签创建成功".tl);
        _loadTags();
      } catch (e) {
        showToast(message: "标签创建失败: $e".tl);
      }
    }
  }

  Future<void> _renameTag(TagInfo tag) async {
    final controller = TextEditingController(text: tag.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("重命名标签".tl),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: "标签名称".tl,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
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
        controller.text.isNotEmpty &&
        controller.text != tag.name) {
      try {
        await downloadManager.renameTag(tag.id, controller.text);
        showToast(message: "标签重命名成功".tl);
        _loadTags();
      } catch (e) {
        showToast(message: "标签重命名失败: $e".tl);
      }
    }
  }

  Future<void> _changeCover(TagInfo tag) async {
    // \u83b7\u53d6\u8be5\u6807\u7b7e\u4e0b\u7684\u6f2b\u753b
    final comicIds = await downloadManager.getComicIdsByTag(tag.id);
    if (comicIds.isEmpty) {
      showToast(message: "\u8be5\u6807\u7b7e\u4e0b\u6ca1\u6709\u6f2b\u753b".tl);
      return;
    }

    // \u663e\u793a\u5bf9\u8bdd\u6846\u9009\u62e9\u5c01\u9762
    final comics = await downloadManager.getAll('time', 'desc');
    final tagComics = comics.where((c) => comicIds.contains(c.id)).toList();
    for (var comic in tagComics){
      await comic.fillDownloadingItemCover();
    }

    if (!mounted) return;

    final selectedComic = await showDialog<DownloadedItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("\u9009\u62e9\u5c01\u9762".tl),
        content: SizedBox(
          width: 400,
          height: 500,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: tagComics.length,
            itemBuilder: (context, index) {
              final comic = tagComics[index];
              return InkWell(
                onTap: () => Navigator.pop(context, comic),
                child: Column(
                  children: [
                    Expanded(
                      child: comic.coverPath != null
                          ? Image.file(
                              File(comic.coverPath!),
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.image),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      comic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("\u53d6\u6d88".tl),
          ),
        ],
      ),
    );

    if (selectedComic != null) {
      try {
        // 使用漫画ID而不是路径
        await downloadManager.updateTagCover(tag.id, selectedComic.id);
        showToast(message: "封面更新成功".tl);
        _loadTags();
      } catch (e) {
        showToast(message: "封面更新失败: $e".tl);
      }
    }
  }

  Future<void> _deleteTag(TagInfo tag) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("删除标签".tl),
        content: Text("确定要删除标签 \"${tag.name}\" 吗？".tl),
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
        await downloadManager.deleteTag(tag.id);
        showToast(message: "标签删除成功".tl);
        _loadTags();
      } catch (e) {
        showToast(message: "标签删除失败: $e".tl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("标签管理".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createTag,
            tooltip: "创建标签".tl,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : tags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.label_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "暂无标签".tl,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _createTag,
                        icon: const Icon(Icons.add),
                        label: Text("创建标签".tl),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: tags.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading: tag.coverPath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(tag.coverPath!),
                                  width: 50,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.label, size: 50),
                                ),
                              )
                            : const Icon(Icons.label, size: 50),
                        title: Text(
                          tag.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text("${tag.comicCount} ${"本漫画".tl}"),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'rename':
                                _renameTag(tag);
                                break;
                              case 'cover':
                                _changeCover(tag);
                                break;
                              case 'delete':
                                _deleteTag(tag);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit),
                                  const SizedBox(width: 8),
                                  Text("重命名".tl),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'cover',
                              child: Row(
                                children: [
                                  const Icon(Icons.image),
                                  const SizedBox(width: 8),
                                  Text("更改封面".tl),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete),
                                  const SizedBox(width: 8),
                                  Text("删除".tl),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class TagInfo {
  final int id;
  final String name;
  final String? coverPath;
  final int comicCount;

  TagInfo({
    required this.id,
    required this.name,
    this.coverPath,
    required this.comicCount,
  });
}

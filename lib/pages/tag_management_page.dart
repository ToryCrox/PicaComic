import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:flutter/services.dart';

class TagManagementPage extends StatefulWidget {
  const TagManagementPage({Key? key}) : super(key: key);

  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  List<TagInfo> tags = [];
  bool loading = true;

  final _scrollController = ScrollController();

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

      // 如果有封面漫画ID,获取其封面路径
      String? coverPath;
      if (tag.coverComicId != null) {
        final comic =
            await downloadManager.getDownloadedItemById(tag.coverComicId!);
        if (comic != null) {
          await comic.fillDownloadingItemCover();
          coverPath = comic.coverPath;
        }
      }

      tagList.add(TagInfo(
        id: tag.id,
        name: tag.name,
        coverPath: coverPath,
        comicCount: count,
        category: tag.category.value,
        sortOrder: tag.sortOrder,
      ));
    }

    setState(() {
      tags = tagList;
      loading = false;
    });
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    int selectedCategory = 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("创建标签".tl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: "标签名称".tl,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: selectedCategory,
                decoration: InputDecoration(
                  labelText: "分类".tl,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                      value: 0, child: Text(TagCategory.none.label)),
                  DropdownMenuItem(
                      value: 1, child: Text(TagCategory.author.label)),
                  DropdownMenuItem(
                      value: 2, child: Text(TagCategory.work.label)),
                  DropdownMenuItem(
                      value: 3, child: Text(TagCategory.character.label)),
                  DropdownMenuItem(
                      value: 4, child: Text(TagCategory.manga.label)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedCategory = value;
                    });
                  }
                },
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
      ),
    );

    if (result == true && controller.text.isNotEmpty) {
      try {
        await downloadManager.createTag(controller.text,
            category: selectedCategory);
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

  Future<void> _changeCategory(TagInfo tag) async {
    int selectedCategory = tag.category;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("修改分类".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in TagCategory.values)
              RadioListTile<int>(
                title: Text(category.label),
                value: category.value,
                groupValue: selectedCategory,
                onChanged: (value) {
                  Navigator.pop(context, value);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("取消".tl),
          ),
        ],
      ),
    );

    if (result != null && result != tag.category) {
      try {
        await downloadManager.updateTagCategory(tag.id, result);
        showToast(message: "分类修改成功".tl);
        _loadTags();
      } catch (e) {
        showToast(message: "分类修改失败: $e".tl);
      }
    }
  }

  Future<void> _changeCover(TagInfo tag) async {
    // 获取该标签下的漫画
    final comicIds = await downloadManager.getComicIdsByTag(tag.id);
    if (comicIds.isEmpty) {
      showToast(message: "该标签下没有漫画".tl);
      return;
    }

    // 显示对话框选择封面
    final comics = await downloadManager.getAll('time', 'desc');
    final tagComics = comics.where((c) => comicIds.contains(c.id)).toList();
    for (var comic in tagComics) {
      await comic.fillDownloadingItemCover();
    }

    if (!mounted) return;

    final selectedComic = await showDialog<DownloadedItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("选择封面".tl),
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
            child: Text("取消".tl),
          ),
        ],
      ),
    );

    if (selectedComic != null) {
      try {
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
        content: Text("确定要删除标签 \"${tag.name}\" 吗?".tl),
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

  Future<void> _onReorder(ReorderedListFunction reorderedListFunction) async {
    final reorderedTags = reorderedListFunction(tags) as List<TagInfo>;

    setState(() {
      tags = reorderedTags;
    });

    // 更新所有标签的排序顺序
    try {
      for (int i = 0; i < tags.length; i++) {
        await downloadManager.updateTagSortOrder(tags[i].id, i);
      }
    } catch (e) {
      showToast(message: "排序更新失败: $e".tl);
      // 重新加载以恢复正确的顺序
      _loadTags();
    }
  }

  void _onTagTap(TagInfo tag) {
    // 返回下载页面并应用标签筛选
    Navigator.pop(context, tag.id);
  }

  String _getCategoryLabel(int category) {
    return TagCategory.fromValue(category).label;
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
      body: loading && tags.isEmpty
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
              : ReorderableBuilder(
                  scrollController: _scrollController,
                  onReorder: _onReorder,
                  children: tags.map((tag) => _buildTagItem(tag)).toList(),
                  builder: (children) {
                    return GridView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 300,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      children: children,
                    );
                  },
                ),
    );
  }

  Widget _buildTagItem(TagInfo tag) {
    return Card(
      key: ValueKey(tag.id.toString()),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTagTap(tag),
        onSecondaryTapDown: (details) {
          showMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: _buildMenuItems(tag),
          ).then((value) {
            if (value != null) {
              _handleMenuSelection(value, tag);
            }
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            Expanded(
              child: tag.coverPath != null
                  ? Image.file(
                      File(tag.coverPath!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.label, size: 48),
                      ),
                    )
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.label, size: 48),
                      ),
                    ),
            ),
            // 信息区域
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tag.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getCategoryLabel(tag.category),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "${tag.comicCount} ${"本".tl}",
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleMenuSelection(value, tag),
                    itemBuilder: (context) => _buildMenuItems(tag),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(TagInfo tag) {
    return [
      PopupMenuItem(
        value: 'copy',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 20),
            const SizedBox(width: 8),
            Text("复制".tl),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            const Icon(Icons.edit, size: 20),
            const SizedBox(width: 8),
            Text("重命名".tl),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'category',
        child: Row(
          children: [
            const Icon(Icons.category, size: 20),
            const SizedBox(width: 8),
            Text("修改分类".tl),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'cover',
        child: Row(
          children: [
            const Icon(Icons.image, size: 20),
            const SizedBox(width: 8),
            Text("更改封面".tl),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            const Icon(Icons.delete, size: 20),
            const SizedBox(width: 8),
            Text("删除".tl),
          ],
        ),
      ),
    ];
  }

  void _handleMenuSelection(String value, TagInfo tag) {
    switch (value) {
      case 'copy':
        Clipboard.setData(ClipboardData(text: tag.name));
        showToast(message: "已复制到剪贴板".tl);
        break;
      case 'rename':
        _renameTag(tag);
        break;
      case 'category':
        _changeCategory(tag);
        break;
      case 'cover':
        _changeCover(tag);
        break;
      case 'delete':
        _deleteTag(tag);
        break;
    }
  }
}

class TagInfo {
  final int id;
  final String name;
  final String? coverPath;
  final int comicCount;
  final int category;
  final int sortOrder;

  TagInfo({
    required this.id,
    required this.name,
    this.coverPath,
    required this.comicCount,
    this.category = 0,
    this.sortOrder = 0,
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';

import '../foundation/log.dart';

/// 标签分配对话框
class TagAssignmentDialog extends StatefulWidget {
  final List<String> comicIds;

  const TagAssignmentDialog({
    Key? key,
    required this.comicIds,
  }) : super(key: key);

  @override
  State<TagAssignmentDialog> createState() => _TagAssignmentDialogState();
}

class _TagAssignmentDialogState extends State<TagAssignmentDialog>
    with SingleTickerProviderStateMixin {
  List<DownloadTag> allTags = [];
  final _originalTagIds = <int>{};
  final selectedTagIds = <int>{};
  bool loading = true;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  String _searchQuery = '';

  // 当前标签分类
  TagCategory? get _currentCategory {
    final index = _tabController.index;
    if (index == 0) {
      return null;
    }
    return TagCategory.values[index - 1];
  }

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: TagCategory.values.length + 1, vsync: this);
    _loadTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    setState(() => loading = true);

    // 获取所有有漫画的共同标签(用于显示初始状态)
    if (widget.comicIds.isNotEmpty) {
      final comicTags =
          await downloadManager.getCommonComicTags(widget.comicIds);
      final ids = comicTags.map((e) => e.id).toSet();
      selectedTagIds.clear();
      selectedTagIds.addAll(ids);
      selectedTagIds.addAll(comicTags.map((e) => e.id));
      _originalTagIds.clear();
      _originalTagIds.addAll(ids);
    }

    // 获取所有标签,按updated_time倒序
    final tags = await downloadManager.getAllTags();
    // 标签已经按sort_order排序,我们需要按updated_time倒序
    tags.sort((a, b) {
      final hasA = selectedTagIds.contains(a.id);
      final hasB = selectedTagIds.contains(b.id);
      if (hasA && hasB) {
        return b.updatedTime.compareTo(a.updatedTime);
      } else if (hasA) {
        return -1;
      } else if (hasB) {
        return 1;
      }
      return b.updatedTime.compareTo(a.updatedTime);
    });

    setState(() {
      allTags = tags;
      loading = false;
    });
  }

  Future<void> _createNewTag() async {
    if (_searchController.text.isEmpty) return;

    try {
      final currentCategory = _currentCategory ?? TagCategory.none;
      final tagId = await downloadManager.createTag(_searchController.text,
          category: currentCategory.value);
      final newTag = DownloadTag(
        id: tagId,
        name: _searchController.text,
        coverComicId: null,
        createdTime: DateTime.now(),
        category: currentCategory,
      );

      setState(() {
        allTags.insert(0, newTag);
        selectedTagIds.add(tagId);
        _searchController.clear();
        _searchQuery = '';
      });

      showToast(message: "标签创建成功".tl);
    } catch (e) {
      showToast(message: "标签创建失败: $e".tl);
    }
  }

  Future<void> _applyTags() async {
    try {
      final addTags = selectedTagIds.difference(_originalTagIds);
      final removeTags = _originalTagIds.difference(selectedTagIds);
      Log.d(
          'selectedTagIds: $selectedTagIds, _originalTagIds: $_originalTagIds');
      Log.d("添加标签: $addTags, 删除标签: $removeTags");

      // 为所有选中的漫画设置标签
      for (var comicId in widget.comicIds) {
        // 添加新标签
        for (var tagId in addTags) {
          await downloadManager.addTagToComic(comicId, tagId);
        }

        // 移除取消选中的标签
        for (var tagId in removeTags) {
          await downloadManager.removeTagFromComic(comicId, tagId);
        }
      }

      if (mounted) {
        showToast(message: "标签更新成功".tl);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showToast(message: "标签更新失败: $e".tl);
      }
    }
  }

  List<DownloadTag> _getFilteredTags(int? category) {
    var tags = allTags;

    // 按分类筛选
    if (category != null) {
      tags = tags.where((tag) => tag.category.value == category).toList();
    }

    // 按搜索关键词筛选
    if (_searchQuery.isNotEmpty) {
      tags = tags
          .where((tag) =>
              tag.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return tags;
  }

  Widget _buildTagList(int? category) {
    final tags = _getFilteredTags(category);

    if (tags.isEmpty) {
      return Center(
        child: Text(
          "暂无标签".tl,
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: tags.length,
      itemBuilder: (context, index) {
        final tag = tags[index];
        final tagId = tag.id;
        final tagName = tag.name;
        final isSelected = selectedTagIds.contains(tagId);

        return FutureBuilder<String?>(
          future: _getTagCoverPath(tag),
          builder: (context, snapshot) {
            return CheckboxListTile(
              title: Text(tagName),
              subtitle: Text(tag.category.label),
              secondary: snapshot.hasData && snapshot.data != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        File(snapshot.data!),
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tag.category.color.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.label_outline, size: 20),
                    ),
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    selectedTagIds.add(tagId);
                  } else {
                    selectedTagIds.remove(tagId);
                  }
                });
              },
            );
          },
        );
      },
    );
  }

  Future<String?> _getTagCoverPath(DownloadTag tag) async {
    if (tag.coverComicId == null) return null;

    final comic =
        await downloadManager.getDownloadedItemById(tag.coverComicId!);
    if (comic != null) {
      return comic.coverPath;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("管理标签".tl),
      content: SizedBox(
        width: 500,
        height: 600,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // 搜索/新建标签输入框
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: "搜索或创建标签".tl,
                      hintText: "输入标签名称".tl,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: _createNewTag,
                                  tooltip: "创建新标签".tl,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                ),
                              ],
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    onSubmitted: (_) {
                      // 如果有匹配的标签,不创建;否则创建新标签
                      final filteredTags = _getFilteredTags(null);
                      if (filteredTags.isEmpty && _searchQuery.isNotEmpty) {
                        _createNewTag();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // TabBar
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    tabs: [
                      Tab(text: "全部".tl),
                      for (final category in TagCategory.values)
                        Tab(text: category.label),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // TabBarView
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTagList(null), // 全部
                        for (final category in TagCategory.values)
                          _buildTagList(category.value),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text("取消".tl),
        ),
        TextButton(
          onPressed: _applyTags,
          child: Text("确认".tl),
        ),
      ],
    );
  }
}

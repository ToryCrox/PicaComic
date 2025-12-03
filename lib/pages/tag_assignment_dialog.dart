import 'dart:io';
import 'dart:math' as math;

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
  final List<String>? suggestedTags;

  const TagAssignmentDialog({
    Key? key,
    required this.comicIds,
    this.suggestedTags,
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
  final Map<int, String?> _coverPathCache = {}; // 封面路径缓存

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

    // 获取所有标签
    final tags = await downloadManager.getAllTags();

    // 预计算相似度(避免在排序中重复计算)
    final similarityMap = <int, int>{};
    if (widget.suggestedTags != null && widget.suggestedTags!.isNotEmpty) {
      for (var tag in tags) {
        similarityMap[tag.id] =
            _calculateSimilarity(tag.name, widget.suggestedTags!);
      }
    }

    // 排序:已选中 > 相似度高 > 最近更新
    tags.sort((a, b) {
      final hasA = selectedTagIds.contains(a.id);
      final hasB = selectedTagIds.contains(b.id);

      // 已选中的标签优先
      if (hasA && hasB) {
        return b.updatedTime.compareTo(a.updatedTime);
      } else if (hasA) {
        return -1;
      } else if (hasB) {
        return 1;
      }

      // 如果提供了建议标签,按相似度排序
      if (similarityMap.isNotEmpty) {
        final similarityA = similarityMap[a.id] ?? 0;
        final similarityB = similarityMap[b.id] ?? 0;

        if (similarityA != similarityB) {
          return similarityB.compareTo(similarityA); // 相似度高的在前
        }
      }

      return b.updatedTime.compareTo(a.updatedTime);
    });

    // 预加载所有封面路径
    await _preloadCoverPaths(tags);

    setState(() {
      allTags = tags;
      loading = false;
    });
  }

  /// 预加载所有标签的封面路径
  Future<void> _preloadCoverPaths(List<DownloadTag> tags) async {
    _coverPathCache.clear();

    // 收集所有需要加载封面的 comicId
    final comicIds = tags
        .where((tag) => tag.coverComicId != null)
        .map((tag) => tag.coverComicId!)
        .toSet()
        .toList();

    if (comicIds.isEmpty) return;

    // 批量查询所有漫画
    final comicsMap = await downloadManager.getDownloadedItemsByIds(comicIds);

    // 为所有标签设置封面路径
    for (var tag in tags) {
      if (tag.coverComicId != null) {
        final comic = comicsMap[tag.coverComicId];
        if (comic != null) {
          _coverPathCache[tag.id] = comic.coverPath;
        }
      }
    }
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
        _coverPathCache[tagId] = null; // 新标签暂无封面
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

        return CheckboxListTile(
          title: Text(tagName),
          subtitle: Text(tag.category.label),
          secondary: _buildTagCover(tag),
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
  }

  /// 构建标签封面
  Widget _buildTagCover(DownloadTag tag) {
    final coverPath = _coverPathCache[tag.id];

    if (coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(coverPath),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultCover(tag);
          },
        ),
      );
    }

    return _buildDefaultCover(tag);
  }

  /// 构建默认封面
  Widget _buildDefaultCover(DownloadTag tag) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tag.category.color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.label_outline, size: 20),
    );
  }

  /// 计算标签与建议标签列表的相似度
  /// 返回值越大表示越相似
  int _calculateSimilarity(String tagName, List<String> suggestedTags) {
    final lowerTagName = tagName.toLowerCase();
    int maxSimilarity = 0;

    for (var suggested in suggestedTags) {
      final lowerSuggested = suggested.toLowerCase();

      // 完全匹配
      if (lowerTagName == lowerSuggested) {
        return 100;
      }

      // 包含关系
      if (lowerTagName.contains(lowerSuggested) ||
          lowerSuggested.contains(lowerTagName)) {
        maxSimilarity = math.max(maxSimilarity, 50);
        continue;
      }

      // 计算编辑距离相似度
      final distance = _levenshteinDistance(lowerTagName, lowerSuggested);
      final maxLen = math.max(lowerTagName.length, lowerSuggested.length);
      final similarity = ((maxLen - distance) * 30 / maxLen).round();
      maxSimilarity = math.max(maxSimilarity, similarity);
    }

    return maxSimilarity;
  }

  /// 计算两个字符串的编辑距离
  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = math.min(math.min(v1[j] + 1, v0[j + 1] + 1), v0[j] + cost);
      }
      List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
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

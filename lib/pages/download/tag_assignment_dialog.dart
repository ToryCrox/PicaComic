import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:worker_manager/worker_manager.dart';

/// 在 isolate 中计算所有标签与建议标签的相似度
///
/// 原本在 UI 线程执行，选中多部漫画时 suggestedTags 数量很大，
/// 每个标签都要和所有 suggestedTags 做编辑距离计算，
/// O(标签数 × 建议数 × 字符串长度²) 的计算量会严重阻塞 UI。
/// 移到 isolate 后主线程不再卡顿。
///
/// 必须是顶层函数，否则无法通过 @pragma('vm:entry-point') 注入 isolate。
@pragma('vm:entry-point')
Map<int, int> computeSimilaritiesInIsolate(List<TagSimilarityInput> inputs) {
  final result = <int, int>{};
  for (final input in inputs) {
    result[input.tagId] = _levenshteinSimilarity(
      input.tagName,
      input.suggestedTags,
    );
  }
  return result;
}

/// 计算单个标签名称与建议列表的编辑距离相似度
///
/// 完全匹配=100，包含关系=50，其余按编辑距离归一化到 0~30。
/// 返回最高分（取与所有 suggestedTags 匹配的最大值）。
int _levenshteinSimilarity(String tagName, List<String> suggestedTags) {
  final lowerTagName = tagName.toLowerCase();
  int maxSimilarity = 0;

  for (var suggested in suggestedTags) {
    final lowerSuggested = suggested.toLowerCase();

    if (lowerTagName == lowerSuggested) {
      return 100;
    }

    if (lowerTagName.contains(lowerSuggested) ||
        lowerSuggested.contains(lowerTagName)) {
      maxSimilarity = math.max(maxSimilarity, 50);
      continue;
    }

    final distance = _levenshteinDistance(lowerTagName, lowerSuggested);
    final maxLen = math.max(lowerTagName.length, lowerSuggested.length);
    final similarity = ((maxLen - distance) * 30 / maxLen).round();
    maxSimilarity = math.max(maxSimilarity, similarity);
  }

  return maxSimilarity;
}

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

/// isolate 相似度计算任务的输入参数
///
/// 必须是顶层 class（不能在 _TagAssignmentDialogState 内部），
/// 否则无法跨 isolate 传递。
class TagSimilarityInput {
  final int tagId;
  final String tagName;
  final List<String> suggestedTags;

  TagSimilarityInput({
    required this.tagId,
    required this.tagName,
    required this.suggestedTags,
  });
}

/// 构建 isolate 相似度计算任务
///
/// 必须是顶层函数，不能放在 State 类中。
/// 闭包在 State 实例方法内创建时会捕获 this，导致整个 Widget 对象图
/// 被尝试发送到 isolate，从而报 "object is unsendable" 错误。
Future<Map<int, int>> Function() _buildSimilarityTask(
  List<TagSimilarityInput> inputs,
) {
  return () async => computeSimilaritiesInIsolate(inputs);
}

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
  bool isApplying = false;
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
    _tabController = TabController(
      length: TagCategory.values.length + 1,
      vsync: this,
    );
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

    // 并行查询：共同标签 + 全部标签，减少 I/O 串行等待时间
    final tagsFuture = downloadManager.getAllTags();
    final commonFuture = widget.comicIds.isNotEmpty
        ? downloadManager.getCommonComicTags(widget.comicIds)
        : null;

    List<DownloadTag> tags;
    if (commonFuture != null) {
      final results = await Future.wait([commonFuture, tagsFuture]);
      final commonTags = results[0];
      final ids = commonTags.map((e) => e.id).toSet();
      selectedTagIds.clear();
      selectedTagIds.addAll(ids);
      _originalTagIds.clear();
      _originalTagIds.addAll(ids);
      tags = results[1];
    } else {
      tags = await tagsFuture;
    }

    // 在 isolate 中预计算相似度，避免 O(tags × suggestions × L²) 的主线程阻塞
    final similarityMap = <int, int>{};
    if (widget.suggestedTags != null && widget.suggestedTags!.isNotEmpty) {
      final inputs = tags
          .map(
            (tag) => TagSimilarityInput(
              tagId: tag.id,
              tagName: tag.name,
              suggestedTags: widget.suggestedTags!,
            ),
          )
          .toList();
      similarityMap.addAll(
        await workerManager.execute<Map<int, int>>(
          _buildSimilarityTask(inputs),
        ),
      );
    }

    // 排序:已选中 > 相似度高 > 最近更新
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

      if (similarityMap.isNotEmpty) {
        final similarityA = similarityMap[a.id] ?? 0;
        final similarityB = similarityMap[b.id] ?? 0;

        if (similarityA != similarityB) {
          return similarityB.compareTo(similarityA);
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
      final tagId = await downloadManager.createTag(
        _searchController.text,
        category: currentCategory.value,
      );
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
    setState(() {
      isApplying = true;
    });
    try {
      final addTags = selectedTagIds.difference(_originalTagIds).toList();
      final removeTags = _originalTagIds.difference(selectedTagIds).toList();
      Log.d(
        'selectedTagIds: $selectedTagIds, _originalTagIds: $_originalTagIds',
      );
      Log.d("添加标签: $addTags, 删除标签: $removeTags");

      // 批量更新标签（内部会调用 _notifyTagsChanged() 通过流通知所有监听者刷新）
      await downloadManager.batchUpdateTags(
        widget.comicIds,
        addTags,
        removeTags,
      );

      if (mounted) {
        showToast(message: "标签更新成功".tl);
        // 返回 true 通知调用方，但无需调用方手动 refresh/invalidate。
        // downloadManager.onTagsChanged 流已触发 Provider 链自动更新。
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showToast(message: "标签更新失败: $e".tl);
        setState(() {
          isApplying = false;
        });
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
          .where(
            (tag) =>
                tag.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
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
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
          onPressed: isApplying ? null : () => Navigator.pop(context, false),
          child: Text("取消".tl),
        ),
        TextButton(
          onPressed: isApplying ? null : _applyTags,
          child: isApplying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text("确认".tl),
        ),
      ],
    );
  }
}

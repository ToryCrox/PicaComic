import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:pica_comic/pages/download/components/download_tile.dart';
import '../../foundation/log.dart';

class DownloadTagFilterPanel extends StatefulWidget {
  final List<TagInfo> tags;
  final int? selectedTagId;
  final ValueChanged<int?> onTagSelected;
  final VoidCallback onClose;
  final VoidCallback onManageTags;
  final VoidCallback? onTagsReordered;

  const DownloadTagFilterPanel({
    super.key,
    required this.tags,
    required this.selectedTagId,
    required this.onTagSelected,
    required this.onClose,
    required this.onManageTags,
    this.onTagsReordered,
  });

  @override
  State<DownloadTagFilterPanel> createState() => _DownloadTagFilterPanelState();
}

class _DownloadTagFilterPanelState extends State<DownloadTagFilterPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<ScrollController> _scrollControllers = [];

  // Categories to show in tabs
  final _categories = TagCategory.values;

  // 使用List存储所有标签,便于排序
  List<TagInfo> _allTags = [];

  // 缓存每个tab的显示列表,key为tab索引
  final Map<int, List<TagInfo>> _displayTagsByTab = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length + 1, vsync: this);
    _scrollControllers.addAll([
      for (var i = 0; i < _tabController.length + 1; i++) ScrollController(),
    ]);
    _allTags = List.from(widget.tags);
    _updateAllDisplayTags();
  }

  // 更新所有tab的显示列表
  void _updateAllDisplayTags() {
    // Tab 0: 全部标签,按 sortOrder 排序
    final allTagsList = List<TagInfo>.from(_allTags);
    allTagsList.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _displayTagsByTab[0] = allTagsList;

    // 其他tab: 按分类过滤,按 categorySortOrder 排序
    for (int i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryTags =
          _allTags.where((t) => t.category == category.value).toList();
      categoryTags
          .sort((a, b) => a.categorySortOrder.compareTo(b.categorySortOrder));
      _displayTagsByTab[i + 1] = categoryTags;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          _buildTabs(),
          SizedBox(
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTagGrid(0, null), // All
                for (int i = 0; i < _categories.length; i++)
                  _buildTagGrid(i + 1, _categories[i]),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            "标签筛选".tl,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: widget.onManageTags,
            icon: const Icon(Icons.settings, size: 18),
            label: Text("管理".tl),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        const Tab(text: "全部"),
        for (var category in _categories) Tab(text: category.label),
      ],
    );
  }

  Widget _buildTagGrid(int pageIndex, TagCategory? category) {
    // 从缓存中获取该tab的显示列表
    final displayTags = _displayTagsByTab[pageIndex] ?? [];

    if (displayTags.isEmpty) {
      return Center(
        child: Text("无标签".tl),
      );
    }

    final scrollController = _scrollControllers[pageIndex];

    return SingleChildScrollView(
      controller: scrollController,
      child: ReorderableBuilder(
        key: ValueKey('reorderable_$pageIndex'),
        scrollController: scrollController,
        enableDraggable: true,
        onReorder: (reorderedListFunction) async {
          final reorderedTags =
              reorderedListFunction(displayTags) as List<TagInfo>;
          Log.d("Reordered tags: ${reorderedTags.map((e) => e.name).toList()}");

          // 立即更新缓存的显示列表
          setState(() {
            _displayTagsByTab[pageIndex] = reorderedTags;
          });

          // 更新数据库
          try {
            if (category == null) {
              // 全部标签tab,更新 sortOrder
              for (int i = 0; i < reorderedTags.length; i++) {
                final tag = reorderedTags[i];
                await downloadManager.updateTagSortOrder(tag.id, i);
                // 同时更新 _allTags 中的对应标签
                final index = _allTags.indexWhere((t) => t.id == tag.id);
                if (index != -1) {
                  _allTags[index] = tag.copyWith(sortOrder: i);
                }
              }
            } else {
              // 分类tab,更新 categorySortOrder
              for (int i = 0; i < reorderedTags.length; i++) {
                final tag = reorderedTags[i];
                await downloadManager.updateTagCategorySortOrder(tag.id, i);
                // 同时更新 _allTags 中的对应标签
                final index = _allTags.indexWhere((t) => t.id == tag.id);
                if (index != -1) {
                  _allTags[index] = tag.copyWith(categorySortOrder: i);
                }
              }
            }

            // 通知父组件刷新
            widget.onTagsReordered?.call();
          } catch (e) {
            Log.e('onReorder $e');
            // 出错时重新加载
            _updateAllDisplayTags();
            setState(() {});
          }
        },
        children: displayTags.map((tag) => _buildTagItem(tag)).toList(),
        builder: (children) {
          return GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80,
              childAspectRatio: 0.8,
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
    // 支持多标签选择，但这里只显示单个选中状态（用于兼容）
    final isSelected = widget.selectedTagId == tag.id;
    return Card(
      key: ValueKey(tag.id.toString()),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onTagSelected(isSelected ? null : tag.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: tag.coverPath != null
                  ? Image.file(
                      File(tag.coverPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.image),
                    )
                  : Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.label),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                tag.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : null,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

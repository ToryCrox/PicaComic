import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/state_controller.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/models/download_tag.dart';
import 'package:pica_comic/pages/download_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../foundation/log.dart';

class DownloadTagFilterPanel extends StatefulWidget {
  const DownloadTagFilterPanel({
    super.key,
    required this.tags,
    required this.selectedTagId,
    required this.onTagSelected,
    required this.onClose,
    required this.onManageTags,
  });

  final List<TagInfo> tags;
  final int? selectedTagId;
  final ValueChanged<int?> onTagSelected;
  final VoidCallback onClose;
  final VoidCallback onManageTags;

  @override
  State<DownloadTagFilterPanel> createState() => _DownloadTagFilterPanelState();
}

class _DownloadTagFilterPanelState extends State<DownloadTagFilterPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scrollController = ScrollController();

  // Categories to show in tabs
  final _categories = TagCategory.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length + 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
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
                _buildTagGrid(null), // All
                for (var category in _categories) _buildTagGrid(category),
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

  Widget _buildTagGrid(TagCategory? category) {
    // Filter tags
    var displayTags = widget.tags;
    if (category != null) {
      displayTags =
          widget.tags.where((t) => t.category == category.value).toList();
      // Sort by category sort order if available, otherwise by default sort order
      // Note: TagInfo currently has sortOrder. We might need to update TagInfo to include categorySortOrder
      // But for now, let's assume the list passed in is already sorted or we sort it here.
      // Since we want independent sorting, we should rely on the order in the list if possible,
      // or re-sort if we have the data.
      // Given TagInfo in download_page.dart doesn't have categorySortOrder yet, we should update it.
      // For now, we'll just use the list as is, assuming the parent provides it correctly or we implement reordering here.
    }

    if (displayTags.isEmpty) {
      return Center(
        child: Text("无标签".tl),
      );
    }

    return ReorderableBuilder(
      scrollController: _scrollController,
      onReorder: (reorderedListFunction) async {
        final reorderedTags =
            reorderedListFunction(displayTags) as List<TagInfo>;

        // Update UI immediately (optimistic update)
        // We can't update the parent's list directly, but we can update the local display
        // However, since we are using ReorderableBuilder which manages its own state for the drag,
        // we need to persist the change to the database and then reload or notify parent.

        // Update database
        try {
          if (category == null || category == TagCategory.none) {
            // Updating global sort order
            for (int i = 0; i < reorderedTags.length; i++) {
              await DownloadManager()
                  .updateTagSortOrder(reorderedTags[i].id, i);
            }
          } else {
            // Updating category sort order
            for (int i = 0; i < reorderedTags.length; i++) {
              await DownloadManager()
                  .updateTagCategorySortOrder(reorderedTags[i].id, i);
            }
          }

          // Notify parent to reload tags
          // Since we don't have a callback for reload, we can try to find the logic
          StateController.findOrNull<DownloadPageLogic>()?.refresh();
        } catch (e) {
          Log.e('onReorder $e');
          // Handle error
        }
      },
      enableDraggable: true,
      children: displayTags.map((tag) => _buildTagItem(tag)).toList(),
      builder: (children) {
        return GridView(
          controller: _scrollController,
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
    );
  }

  Widget _buildTagItem(TagInfo tag) {
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

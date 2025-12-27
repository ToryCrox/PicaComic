import 'dart:math';

import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/pages/components/download_tag_filter_panel.dart';
import 'package:pica_comic/pages/tag_management_page.dart' hide TagInfo;
import 'package:pica_comic/pages/rename_download_dialog.dart';
import 'package:pica_comic/pages/update_size_dialog.dart';
import 'package:pica_comic/pages/tag_assignment_dialog.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/download/components/download_tile.dart';

import 'package:pica_comic/components/components.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/tools/translations.dart';
// For appdata

import 'download/download_providers.dart';
import 'download/components/download_list.dart';
import 'download/components/download_menus.dart';

class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({super.key, this.showBack = true});

  final bool showBack;

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with AutomaticKeepAliveClientMixin {
  final String _pageId = "main_download_page";

  @override
  bool get wantKeepAlive => true;

  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  /// 控制 tag filter 栏显示/隐藏
  bool _showTagFilter = true;

  /// 保存的滚动位置（用于退出筛选模式时恢复）
  double? _savedScrollPosition;

  /// 判断状态是否处于筛选模式
  bool _isFilteringState(DownloadPageState state) {
    return state.keyword.isNotEmpty ||
        state.downloadTypeFilter != null ||
        state.excludeLocal ||
        state.selectedTagIds.isNotEmpty;
  }

  /// 保存当前滚动位置
  void _saveScrollPosition() {
    if (_scrollController.hasClients) {
      _savedScrollPosition = _scrollController.offset;
    }
  }

  /// 恢复滚动位置
  void _restoreScrollPosition() {
    if (_savedScrollPosition != null && _scrollController.hasClients) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _savedScrollPosition != null) {
          _scrollController.jumpTo(_savedScrollPosition!);
          _savedScrollPosition = null;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen(downloadPageStateProvider(_pageId), (previous, next) {
      if (next.keyword != _searchController.text) {
        _searchController.text = next.keyword;
      }
      
      // 监听筛选状态变化，处理滚动位置的保存和恢复
      final wasFiltering = previous != null && _isFilteringState(previous);
      final isFiltering = _isFilteringState(next);
      
      if (!wasFiltering && isFiltering) {
        // 进入筛选模式时保存滚动位置
        _saveScrollPosition();
      } else if (wasFiltering && !isFiltering) {
        // 退出筛选模式时恢复滚动位置
        _restoreScrollPosition();
      }
    });

    final pageState = ref.watch(downloadPageStateProvider(_pageId));
    final isSelecting = pageState.isSelecting;
    final selectedCount = ref.watch(selectedCountProvider(_pageId));

    return Scaffold(
      floatingActionButton: !isSelecting
          ? FloatingActionButton(
              onPressed: () => _scrollToTop(context),
              child: const Icon(Icons.arrow_upward),
            )
          : null,
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          // 检测滚动方向，控制 tag filter 的显示/隐藏
          final direction =
              notification.scrollDelta != null && notification.scrollDelta! > 0
                  ? ScrollDirection.reverse
                  : ScrollDirection.forward;
          final wasShowing = _showTagFilter;
          if (direction == ScrollDirection.reverse) {
            _showTagFilter = false;
          } else if (direction == ScrollDirection.forward) {
            _showTagFilter = true;
          }
          if (_showTagFilter != wasShowing) {
            setState(() {});
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // AppBar
            if (!isSelecting)
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  minHeight: 56,
                  maxHeight: 56,
                  child: _buildAppBarContent(context),
                ),
              ),
            // Selection AppBar
            if (isSelecting)
              SliverAppBar(
                pinned: true,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                leading: IconButton(
                  onPressed: () {
                    exitSelecting(ref, _pageId);
                  },
                  icon: const Icon(Icons.close),
                ),
                title: Text("已选择 $selectedCount 项"),
                actions: _buildSelectionActions(context, selectedCount),
              ),
            // Tag Filter
            if (!isSelecting)
              SliverPersistentHeader(
                // 根据滚动方向决定是否固定显示
                pinned: _showTagFilter && SmoothScrollProvider.isMouseScroll,
                floating: !SmoothScrollProvider.isMouseScroll,
                delegate: _SliverAppBarDelegate(
                  minHeight: 48,
                  maxHeight: 48,
                  child: _buildTagFilter(context),
                ),
              ),
            // List
            DownloadList(
              pageId: _pageId,
              onRefresh: () async => ref.refresh(allDownloadedComicsProvider),
              onRefreshTags: () {
                ref.refresh(downloadTagsProvider);
                ref.refresh(allDownloadedComicsProvider);
              },
              onShowInfo: (index) {
                // TODO: Implement info showing if needed
              },
            ),
            SliverPadding(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom)),
          ],
        ),
      ),
    );
  }

  void _scrollToTop(BuildContext context) {
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Widget _buildAppBarContent(BuildContext context) {
    final pageState = ref.watch(downloadPageStateProvider(_pageId));

    // Check if filtering
    bool isFiltering = pageState.keyword.isNotEmpty ||
        pageState.downloadTypeFilter != null ||
        pageState.excludeLocal ||
        pageState.selectedTagIds.isNotEmpty;

    Widget? leading;
    if (isFiltering) {
      leading = IconButton(
        onPressed: () {
          // clear filters
          if (pageState.keyword.isNotEmpty) updateKeyword(ref, _pageId, "");
          if (pageState.selectedTagIds.isNotEmpty)
            updateTagFilter(ref, _pageId, null); // clear all
          if (pageState.downloadTypeFilter != null)
            updateDownloadTypeFilter(ref, _pageId, null);
          if (pageState.excludeLocal) updateExcludeLocal(ref, _pageId, false);
        },
        icon: const Icon(Icons.close),
      );
    } else if (widget.showBack) {
      leading = IconButton(
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.arrow_back),
      );
    }

    return Material(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: Row(
          children: [
            if (leading != null) leading,
            Expanded(
              child: _buildTitle(context, pageState),
            ),
            ..._buildActions(context, pageState),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, DownloadPageState pageState) {
    if (pageState.keyword.isNotEmpty && !pageState.isSelecting) {
      return TextField(
        controller: _searchController,
        decoration:
            InputDecoration(border: InputBorder.none, hintText: "搜索".tl),
        onChanged: (v) => updateKeyword(ref, _pageId, v),
      );
    } else {
      final summaryAsync = ref.watch(downloadedComicsSummaryProvider(_pageId));
      final summary = summaryAsync.when(
        data: (s) => s,
        loading: () => "",
        error: (_, __) => "",
      );

      String suffix = '';
      if (pageState.selectedTagIds.isNotEmpty) {
        final tags = ref.watch(downloadTagsProvider).valueOrNull ?? [];
        final tagNames = pageState.selectedTagIds
            .map((id) => tags
                .firstWhere((t) => t.id == id,
                    orElse: () => TagInfo(id: id, name: "", comicCount: 0))
                .name)
            .where((name) => name.isNotEmpty)
            .join(', ');
        if (tagNames.isNotEmpty) {
          suffix = ' [$tagNames]';
        }
      }
      if (pageState.downloadTypeFilter != null) {
        final typeName = _getDownloadTypeName(pageState.downloadTypeFilter!);
        if (suffix.isNotEmpty) {
          suffix = '$suffix / $typeName';
        } else {
          suffix = ' [$typeName]';
        }
      }
      if (pageState.excludeLocal) {
        final excludeText = "非本地".tl;
        if (suffix.isNotEmpty) {
          suffix = '$suffix / $excludeText';
        } else {
          suffix = ' [$excludeText]';
        }
      }

      if (pageState.isSelecting) {
        final count = ref.watch(selectedCountProvider(_pageId));
        return Text("已选择 @num 个项目$suffix".tlParams({"num": count.toString()}));
      } else {
        return Text('${"已下载".tl}$summary$suffix');
      }
    }
  }

  String _getDownloadTypeName(DownloadType type) {
    switch (type) {
      case DownloadType.picacg:
        return "哔咔";
      case DownloadType.ehentai:
        return "E-Hentai";
      case DownloadType.jm:
        return "禁漫";
      case DownloadType.hitomi:
        return "Hitomi";
      case DownloadType.htmanga:
        return "HTManga";
      case DownloadType.nhentai:
        return "nhentai";
      case DownloadType.other:
        return "其他";
      case DownloadType.favorite:
        return "收藏";
      case DownloadType.local:
        return "本地".tl;
    }
  }

  List<Widget> _buildActions(
      BuildContext context, DownloadPageState pageState) {
    return [
      IconButton(
        icon: const Icon(Icons.search),
        onPressed: () {
          updateKeyword(ref, _pageId, " "); // trigger search UI
        },
      ),
      Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            showDownloadTypeFilterMenu(
                buttonContext: context, ref: ref, pageId: _pageId);
          },
        ),
      ),
      IconButton(
        icon: const Icon(Icons.sort),
        onPressed: () {
          showComicSortDialog(
            context: context,
            onRefresh: () => ref.refresh(allDownloadedComicsProvider),
          );
        },
      ),
      IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: () {
          showMenu(context: context, position: RelativeRect.fill, items: [
            PopupMenuItem(
                child: Text("多选".tl),
                onTap: () => enterSelecting(ref, _pageId)),
          ]);
        },
      ),
    ];
  }

  List<Widget> _buildSelectionActions(BuildContext context, int count) {
    return [
      Tooltip(
        message: "更多".tl,
        child: IconButton(
          icon: const Icon(Icons.more_horiz),
          onPressed: () {
            _showSelectingMenu(context);
          },
        ),
      ),
    ];
  }

  void _showSelectingMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width - 60,
          50, MediaQuery.of(context).size.width - 60, 50),
      items: [
        PopupMenuItem(
          child: Text("全选".tl),
          onTap: () async {
            final comics =
                await ref.read(filteredComicsProvider(_pageId).future);
            selectAll(ref, _pageId, comics.map((e) => e.id).toList());
          },
        ),
        PopupMenuItem(
          child: Text("删除"
              .tl), // Added based on user feedback, though missing in legacy file, it's essential.
          onTap: () {
            final state = ref.read(downloadPageStateProvider(_pageId));
            if (state.selectedIds.isEmpty) return;
            Future.delayed(const Duration(milliseconds: 200), () {
              showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                        title: Text("确认删除".tl),
                        content: Text("确认删除".tl +
                            " ${state.selectedIds.length} " +
                            "项".tl +
                            "?"),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text("取消".tl)),
                          TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await DownloadManager()
                                    .delete(state.selectedIds.toList());
                                exitSelecting(ref, _pageId);
                              },
                              child: Text("确认".tl)),
                        ],
                      ));
            });
          },
        ),
        PopupMenuItem(
          child: Text("管理标签".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final state = ref.read(downloadPageStateProvider(_pageId));
              final comics =
                  await ref.read(filteredComicsProvider(_pageId).future);
              final selectedComics = comics
                  .where((e) => state.selectedIds.contains(e.id))
                  .toList();

              final suggestedTags = [
                ...selectedComics.map((e) => e.name),
                ...selectedComics.map((e) => e.subTitle),
                ...selectedComics
                    .expand((e) => e.tags), // simplified getting tags
              ];

              final result = await showDialog<bool>(
                context: App.globalContext!,
                builder: (context) => TagAssignmentDialog(
                  comicIds: selectedComics.map((e) => e.id).toList(),
                  suggestedTags: suggestedTags,
                ),
              );
              if (result == true) {
                exitSelecting(ref, _pageId);
                ref.refresh(downloadTagsProvider);
                ref.refresh(allDownloadedComicsProvider);
              }
            },
          ),
        ),
        PopupMenuItem(
          child: Text("重命名下载目录".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final state = ref.read(downloadPageStateProvider(_pageId));
              final comics =
                  await ref.read(filteredComicsProvider(_pageId).future);
              final selectedComics = comics
                  .where((e) => state.selectedIds.contains(e.id))
                  .toList();

              await showDialog(
                context: App.globalContext!,
                builder: (context) => RenameDownloadDialog(
                  comics: selectedComics,
                  onComplete: () {
                    exitSelecting(ref, _pageId);
                    ref.refresh(allDownloadedComicsProvider);
                  },
                ),
              );
            },
          ),
        ),
        PopupMenuItem(
          child: Text("查看漫画详情".tl),
          onTap: () => Future.delayed(const Duration(milliseconds: 200), () {
            final state = ref.read(downloadPageStateProvider(_pageId));
            if (state.selectedIds.length != 1) {
              showToast(message: "请选择一个漫画".tl);
            } else {
              // Logic to view comic info
            }
          }),
        ),
        PopupMenuItem(
          child: Text("更新漫画文件大小".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final state = ref.read(downloadPageStateProvider(_pageId));
              final comics =
                  await ref.read(filteredComicsProvider(_pageId).future);
              final selectedComics = comics
                  .where((e) => state.selectedIds.contains(e.id))
                  .toList();

              await showDialog(
                context: App.globalContext!,
                builder: (context) => UpdateSizeDialog(
                  comics: selectedComics,
                  onComplete: () {
                    exitSelecting(ref, _pageId);
                    ref.refresh(allDownloadedComicsProvider);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTagFilter(BuildContext context) {
    final tagsAsync = ref.watch(filteredTagsProvider(_pageId));
    final pageState = ref.watch(downloadPageStateProvider(_pageId));

    return tagsAsync.when(
      skipLoadingOnReload: true,
      data: (tags) {
        // 限制显示数量 (legacy behavior: max 20)
        var displayTags = tags;
        if (displayTags.length > 20) {
          displayTags = displayTags.sublist(0, 20);
        }

        return Material(
          elevation: 1,
          surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var tag in displayTags)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: InkWell(
                              key: ValueKey(tag.id),
                              onTap: () =>
                                  updateTagFilter(ref, _pageId, tag.id),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: pageState.selectedTagIds
                                          .contains(tag.id)
                                      ? Theme.of(context).colorScheme.primary
                                      : TagCategory.fromValue(tag.category)
                                          .color
                                          .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      pageState.selectedTagIds.contains(tag.id)
                                          ? null
                                          : Border.all(
                                              color: TagCategory.fromValue(
                                                      tag.category)
                                                  .color,
                                              width: 1,
                                            ),
                                ),
                                child: Text(
                                  tag.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: pageState.selectedTagIds
                                            .contains(tag.id)
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    // 获取所有标签用于展开的标签面板
                    final allTags = await ref.read(downloadTagsProvider.future);
                    if (!context.mounted) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      constraints: const BoxConstraints(maxWidth: 1000),
                      backgroundColor: Colors.transparent,
                      builder: (context) => DownloadTagFilterPanel(
                        tags: allTags,
                        selectedTagId: pageState.selectedTagIds.isNotEmpty
                            ? pageState.selectedTagIds.first
                            : null,
                        onTagSelected: (id) {
                          updateTagFilter(ref, _pageId, id);
                          Navigator.pop(context);
                        },
                        onClose: () => Navigator.pop(context),
                        onManageTags: () {
                          Navigator.pop(context);
                          App.globalTo(() => const TagManagementPage());
                        },
                        onTagsReordered: () {
                          ref.refresh(downloadTagsProvider);
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: "展开标签".tl,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(
          height: 48, child: Center(child: CircularProgressIndicator())),
      error: (e, s) => const SizedBox(height: 48),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(
      {required this.child, required this.maxHeight, required this.minHeight});

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(
      child: child,
    );
  }

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => max(maxHeight, minHeight);

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

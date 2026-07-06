import 'dart:math';
import 'dart:ui';

// ignore_for_file: implementation_imports

import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'package:pica_comic/network/download/models/download_tag.dart';
import 'package:pica_comic/pages/components/download_tag_filter_panel.dart';
import 'tag_management_page.dart' hide TagInfo;
import 'package:pica_comic/pages/rename_download_dialog.dart';
import 'package:pica_comic/pages/update_size_dialog.dart';
import 'tag_assignment_dialog.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'components/download_tile.dart';

import 'package:pica_comic/components/components.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:silky_scroll/src/silky_scroll_widget.dart';

import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/tools/extensions.dart';

import 'download_providers.dart';
import 'components/download_list.dart';
import 'components/download_menus.dart';

import 'import_local_comic_dialog.dart';
import 'local_repository_management_page.dart';
import 'downloading_page.dart';
import 'components/multi_select_drag_dialog.dart';

class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({super.key, this.showBack = true});

  final bool showBack;

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage>
    with AutomaticKeepAliveClientMixin {
  /// 每个 DownloadPage 实例的唯一标识符
  /// 用于隔离不同页面实例的筛选/搜索等状态
  late final String _pageId;

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
    return state.isSearching ||
        state.keyword.isNotEmpty ||
        state.downloadTypeFilter != null ||
        state.excludeLocal ||
        state.tagCategoryFilter != null ||
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
    // 为每个页面实例生成唯一 ID，确保筛选/搜索状态独立
    _pageId = "download_page_${UniqueKey().hashCode}";
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
    final slivers = [
      // AppBar
      SliverPersistentHeader(
        pinned: true,
        delegate: _SliverAppBarDelegate(
          minHeight: 56,
          maxHeight: 56,
          child: _buildAppBarContent(context),
        ),
      ),
      // Tag Filter
      SliverPersistentHeader(
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
        onRefresh: () {
          ref.invalidate(allDownloadedComicsProvider);
        },
        // 标签变更后只需惰性失效 downloadTagsProvider，无需刷新 allDownloadedComicsProvider
        // 因为 batchUpdateTags 内部已通过 _notifyTagsChanged() 流通知了 allTagsProvider
        // 和 comicUserTagsProvider，下游 Provider 会沿依赖链自动更新
        onRefreshTags: () {
          ref.invalidate(downloadTagsProvider);
        },
      ),
      SliverPadding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      ),
    ];

    return Scaffold(
      floatingActionButton: isSelecting
          ? (selectedCount > 0 ? _buildSelectionFAB(context, _pageId) : null)
          : _buildFAB(context),
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.scrollDelta == null) return false;
          final ScrollDirection direction = notification.scrollDelta! < 0
              ? ScrollDirection.forward
              : ScrollDirection.reverse;
          var showTagFilter = _showTagFilter;
          if (direction == ScrollDirection.reverse) {
            _showTagFilter = false;
          } else if (direction == ScrollDirection.forward) {
            _showTagFilter = true;
          }
          if (_showTagFilter == showTagFilter) return true;
          setState(() {
            _showTagFilter = _showTagFilter;
          });
          return false;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.trackpad,
              // 开启“鼠标模式” (isDragDisabled == false) 时，禁用鼠标拖拽滚动，允许项拖拽
              // 关闭“鼠标模式” (isDragDisabled == true) 时，允许鼠标拖拽滚动，禁用项拖拽
              if (pageState.isDragDisabled) PointerDeviceKind.mouse,
            },
          ),
          child: _buildDownloadScrollView(slivers),
        ),
      ),
    );
  }

  Widget _buildDownloadScrollView(List<Widget> slivers) {
    if (!App.isDesktop) {
      return CustomScrollView(
        controller: _scrollController,
        slivers: slivers,
      );
    }

    return SilkyScroll(
      controller: _scrollController,
      silkyScrollDuration: const Duration(milliseconds: 900),
      animationCurve: Curves.easeOutCubic,
      builder: (context, controller, physics, pointerDeviceKind) {
        return CustomScrollView(
          controller: controller,
          physics: physics,
          slivers: slivers,
        );
      },
    );
  }

  Widget _buildSelectionFAB(BuildContext context, String pageId) {
    return FloatingActionButton(
      onPressed: () async {
        final state = ref.read(downloadPageStateProvider(pageId));
        final comics = await ref.read(filteredComicsProvider(pageId).future);
        final selectedComics =
            comics.where((e) => state.selectedIds.contains(e.id)).toList();

        if (!context.mounted) return;

        showDialog(
          context: context,
          builder: (context) =>
              MultiSelectDragDialog(selectedItems: selectedComics),
        );
      },
      child: const Icon(Icons.drag_handle),
    );
  }

  /// 构建 FAB - 切换正序/倒序排序
  Widget _buildFAB(BuildContext context) {
    // 判断当前是否为倒序（desc），settings[26][1] == "1" 表示升序（asc），否则为降序（desc）
    final isDescending = appdata.settings[26][1] != "1";

    return FloatingActionButton(
      enableFeedback: true,
      onPressed: () {
        // 切换正序/倒序
        if (isDescending) {
          // 当前是倒序，切换为正序
          appdata.settings[26] = appdata.settings[26].setValueAt("1", 1);
        } else {
          // 当前是正序，切换为倒序
          appdata.settings[26] = appdata.settings[26].setValueAt("0", 1);
        }
        appdata.updateSettings();
        // 触发排序更新（内存排序，不重新从数据库读取）
        triggerSortUpdate(ref, _pageId);
      },
      tooltip: isDescending ? "切换为正序".tl : "切换为倒序".tl,
      child: isDescending
          ? const Icon(Icons.arrow_downward)
          : const Icon(Icons.arrow_upward),
    );
  }

  Widget _buildAppBarContent(BuildContext context) {
    final pageState = ref.watch(downloadPageStateProvider(_pageId));

    // Check if filtering
    bool isFiltering = pageState.isSearching ||
        pageState.keyword.isNotEmpty ||
        pageState.downloadTypeFilter != null ||
        pageState.excludeLocal ||
        pageState.tagCategoryFilter != null ||
        pageState.selectedTagIds.isNotEmpty;

    Widget? leading;
    if (pageState.isSelecting) {
      leading = IconButton(
        onPressed: () {
          exitSelecting(ref, _pageId);
        },
        icon: const Icon(Icons.close),
      );
    } else if (isFiltering) {
      leading = IconButton(
        onPressed: () {
          // clear filters
          if (pageState.isSearching) setIsSearching(ref, _pageId, false);
          if (pageState.keyword.isNotEmpty) updateKeyword(ref, _pageId, "");
          if (pageState.selectedTagIds.isNotEmpty) {
            updateTagFilter(ref, _pageId, null); // clear all
          }
          if (pageState.downloadTypeFilter != null) {
            updateDownloadTypeFilter(ref, _pageId, null);
          }
          if (pageState.tagCategoryFilter != null) {
            updateTagCategoryFilter(ref, _pageId, null);
          }
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
            if (pageState.isSelecting)
              ..._buildSelectionActions(
                context,
                ref.watch(selectedCountProvider(_pageId)),
              )
            else
              ..._buildActions(context, pageState),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, DownloadPageState pageState) {
    if (pageState.isSearching && !pageState.isSelecting) {
      return TextField(
        controller: _searchController,
        decoration:
            InputDecoration(border: InputBorder.none, hintText: "搜索".tl),
        onChanged: (v) => updateKeyword(ref, _pageId, v),
      );
    } else {
      final summaryAsync = ref.watch(downloadedComicsSummaryProvider(_pageId));
      final summary = summaryAsync.when(
        skipLoadingOnReload: true, // 避免排序时闪烁
        data: (s) => s,
        loading: () => "",
        error: (_, __) => "",
      );

      String suffix = '';
      if (pageState.selectedTagIds.isNotEmpty) {
        final tags = ref.watch(downloadTagsProvider).value ?? [];
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
      if (pageState.tagCategoryFilter != null) {
        final categoryName =
            TagCategory.fromValue(pageState.tagCategoryFilter!).label;
        if (suffix.isNotEmpty) {
          suffix = '$suffix / $categoryName';
        } else {
          suffix = ' [$categoryName]';
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
      // 标签管理
      Tooltip(
        message: "标签管理".tl,
        child: IconButton(
          icon: const Icon(Icons.label_outline),
          onPressed: () async {
            final tagId = await App.globalTo(() => const TagManagementPage());
            if (tagId != null && tagId is int) {
              updateTagFilter(ref, _pageId, tagId);
            }
          },
        ),
      ),
      // 导入本地漫画
      Tooltip(
        message: "导入本地漫画".tl,
        child: IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (context) => const ImportLocalComicDialog(),
            );
            ref.refresh(allDownloadedComicsProvider);
          },
        ),
      ),
      // 存储库管理
      Tooltip(
        message: "存储库管理".tl,
        child: IconButton(
          icon: const Icon(Icons.storage),
          onPressed: () {
            App.globalTo(() => const LocalRepositoryManagementPage());
          },
        ),
      ),
      // 下载管理器
      Tooltip(
        message: "下载管理器".tl,
        child: IconButton(
          icon: const Icon(Icons.download_for_offline),
          onPressed: () {
            showPopUpWidget(
              App.globalContext!,
              const DownloadingPage(),
            );
          },
        ),
      ),
      // 搜索
      IconButton(
        icon: const Icon(Icons.search),
        onPressed: () {
          setIsSearching(ref, _pageId, true); // trigger search UI
        },
      ),
      // 类型筛选
      Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            showDownloadTypeFilterMenu(
                buttonContext: context, ref: ref, pageId: _pageId);
          },
        ),
      ),
      // 标签分类筛选
      _buildTagCategoryFilterAction(pageState),
      // 排序
      buildComicSortMenuAnchor(
        onChanged: () => triggerSortUpdate(ref, _pageId),
      ),
      // 更多菜单
      Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            final RenderBox button = context.findRenderObject() as RenderBox;
            final RenderBox overlay = Navigator.of(context)
                .overlay!
                .context
                .findRenderObject() as RenderBox;
            final RelativeRect position = RelativeRect.fromRect(
              Rect.fromPoints(
                button.localToGlobal(Offset.zero, ancestor: overlay),
                button.localToGlobal(button.size.bottomRight(Offset.zero),
                    ancestor: overlay),
              ),
              Offset.zero & overlay.size,
            );

            showMenu(
              context: context,
              position: position,
              items: [
                PopupMenuItem(
                  child: Text("多选".tl),
                  onTap: () => enterSelecting(ref, _pageId),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      Icon(pageState.isDragDisabled
                          ? Icons.mouse_outlined
                          : Icons.mouse),
                      const SizedBox(width: 8),
                      Text(
                          pageState.isDragDisabled ? "开启拖拽模式".tl : "关闭拖拽模式".tl),
                    ],
                  ),
                  onTap: () => toggleDragDisabled(ref, _pageId),
                ),
              ],
            );
          },
        ),
      ),
    ];
  }

  Widget _buildTagCategoryFilterAction(DownloadPageState pageState) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: pageState.tagCategoryFilter == null
              ? const Icon(Icons.check)
              : const SizedBox(width: 24),
          onPressed: () => updateTagCategoryFilter(ref, _pageId, null),
          child: Text("全部分类".tl),
        ),
        const Divider(height: 1),
        for (final category in TagCategory.values)
          MenuItemButton(
            leadingIcon: pageState.tagCategoryFilter == category.value
                ? const Icon(Icons.check)
                : const SizedBox(width: 24),
            onPressed: () =>
                updateTagCategoryFilter(ref, _pageId, category.value),
            child: Text(category.label),
          ),
      ],
      builder: (context, controller, child) {
        final hasFilter = pageState.tagCategoryFilter != null;
        return Tooltip(
          message: "标签分类筛选".tl,
          child: IconButton(
            color: hasFilter ? Theme.of(context).colorScheme.primary : null,
            icon: const Icon(Icons.category_outlined),
            onPressed: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          ),
        );
      },
    );
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
                        content: Text(
                            "${"确认删除".tl} ${state.selectedIds.length} ${"项".tl}?"),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text("取消".tl)),
                          TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                await downloadManager
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
          child: Text("重新下载".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final state = ref.read(downloadPageStateProvider(_pageId));
              final comics =
                  await ref.read(filteredComicsProvider(_pageId).future);
              final selectedComics = comics
                  .where((e) => state.selectedIds.contains(e.id))
                  .toList();

              final result =
                  await downloadManager.redownloadComics(selectedComics);
              showDownloadBatchResultToast(
                result,
                actionName: "已加入重新下载队列".tl,
              );
              if (result.successCount > 0) {
                exitSelecting(ref, _pageId);
                ref.invalidate(allDownloadedComicsProvider);
              }
            },
          ),
        ),
        PopupMenuItem(
          child: Text("更新封面".tl),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () async {
              final state = ref.read(downloadPageStateProvider(_pageId));
              final comics =
                  await ref.read(filteredComicsProvider(_pageId).future);
              final selectedComics = comics
                  .where((e) => state.selectedIds.contains(e.id))
                  .toList();

              final result =
                  await downloadManager.refreshComicCovers(selectedComics);
              showDownloadBatchResultToast(
                result,
                actionName: "已更新封面".tl,
              );
              if (result.successCount > 0) {
                exitSelecting(ref, _pageId);
                ref.invalidate(allDownloadedComicsProvider);
              }
            },
          ),
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
                // 标签更新后 exitSelecting 即可，无需手动刷新 Provider。
                // batchUpdateTags -> _notifyTagsChanged() 流已触发 allTagsProvider
                // 和 comicUserTagsProvider 自动刷新，依赖链会逐层更新下游。
                exitSelecting(ref, _pageId);
              }
            },
          ),
        ),
        PopupMenuItem(
          child: Text("标记颜色".tl),
          onTap: () async {
            final state = ref.read(downloadPageStateProvider(_pageId));
            if (state.selectedIds.isEmpty) return;
            // Delay to allow menu to close
            Future.delayed(const Duration(milliseconds: 200), () async {
              final color = await showDialog<DownloadColorTag>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: Text("选择颜色".tl),
                  children: [
                    for (var tag in DownloadColorTag.values)
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, tag),
                        child: Row(
                          children: [
                            if (tag.color != null)
                              Icon(Icons.circle, color: tag.color!, size: 24)
                            else
                              const Icon(Icons.circle_outlined, size: 24),
                            const SizedBox(width: 12),
                            Text(tag.label),
                          ],
                        ),
                      ),
                  ],
                ),
              );

              if (color != null) {
                await downloadManager.batchUpdateColor(
                    state.selectedIds.toList(), color);
                exitSelecting(ref, _pageId);
              }
            });
          },
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
                            child: _buildTagFilterChip(
                              context,
                              tag,
                              pageState.selectedTagIds.contains(tag.id),
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
                    final panelTags = pageState.tagCategoryFilter == null
                        ? allTags
                        : allTags
                            .where((tag) =>
                                tag.category == pageState.tagCategoryFilter)
                            .toList();
                    if (!context.mounted) return;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      constraints: const BoxConstraints(maxWidth: 1000),
                      backgroundColor: Colors.transparent,
                      builder: (context) => DownloadTagFilterPanel(
                        tags: panelTags,
                        selectedTagIds: pageState.selectedTagIds,
                        onTagSelected: (id) {
                          updateTagFilter(ref, _pageId, id);
                          Navigator.pop(context);
                        },
                        onClose: () => Navigator.pop(context),
                        onManageTags: () {
                          Navigator.pop(context);
                          App.globalTo(() => const TagManagementPage());
                        },
                        // 惰性失效即可，排序变更不涉及漫画数据重载
                        onTagsReordered: () {
                          ref.invalidate(downloadTagsProvider);
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

  Widget _buildTagFilterChip(
    BuildContext context,
    TagInfo tag,
    bool isSelected,
  ) {
    final category = TagCategory.fromValue(tag.category);

    return InkWell(
      key: ValueKey(tag.id),
      onTap: () => updateTagFilter(ref, _pageId, tag.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : category.color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? null
              : Border.all(
                  color: category.color,
                  width: 1,
                ),
        ),
        child: Text(
          tag.name,
          style: TextStyle(
            fontSize: 12,
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
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

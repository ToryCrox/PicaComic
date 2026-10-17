import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/app_settings_provider.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/net_fav_to_local.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/translations.dart';

import 'favorite_action_widgets.dart';
import 'favorites_order_page.dart';
import 'favorites_session.dart';
import 'local_favorites.dart';
import 'local_favorites_providers.dart';
import 'local_search_page.dart';
import 'network_favorite_page.dart';

const _kSecondaryTopBarHeight = 48.0;

/// 收藏页的目录、位置和多选均观察 Riverpod 会话。
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(favoritesSessionProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _topBar(context, ref, session),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(child: _content(session)),
                  AnimatedPositioned(
                    key: const Key('folders'),
                    duration: const Duration(milliseconds: 180),
                    left: 0,
                    right: 0,
                    bottom: session.selectingFolder ? 0 : constraints.maxHeight,
                    child: Material(
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: _folders(context, ref),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶栏保留原有目录切换与批量操作。
  Widget _topBar(
    BuildContext context,
    WidgetRef ref,
    FavoritesSessionState session,
  ) {
    final actions = ref.read(favoritesSessionProvider.notifier);
    final color = Theme.of(context).colorScheme.primary;
    List<FavoriteItem> items = const [];
    if (session.isNetwork == false && session.current != null) {
      items =
          ref.watch(folderFavoritesProvider(session.current!)).asData?.value ??
          const [];
    }
    var folderIcon = Icons.folder_outlined;
    if (session.isNetwork != null) {
      folderIcon = session.isNetwork! ? Icons.folder_special : Icons.folder;
    }
    final selected = items
        .where((e) => session.selected.contains(e.identity))
        .toList();
    Widget child;
    if (session.selected.isNotEmpty) {
      child = Row(
        children: [
          Icon(Icons.rule_folder, color: color),
          const SizedBox(width: 8),
          Text(
            '已选择 @num 个项目'.tlParams({
              'num': session.selected.length.toString(),
            }),
          ),
          const Spacer(),
          IconButton(
            tooltip: '全选'.tl,
            icon: const Icon(Icons.select_all),
            onPressed: () => actions.selectAll(items),
          ),
          IconButton(
            tooltip: '取消'.tl,
            icon: const Icon(Icons.deselect),
            onPressed: actions.clearSelection,
          ),
          if (selected.length == 1)
            IconButton(
              tooltip: '菜单'.tl,
              icon: const Icon(Icons.more_horiz),
              onPressed: () => LocalFavoriteTile(
                selected.first,
                session.current!,
                true,
              ).showMenu(ref.read(downloadManagerProvider.notifier)),
            )
          else
            PopupMenuButton<void>(
              tooltip: '菜单'.tl,
              icon: const Icon(Icons.more_horiz),
              itemBuilder: (_) =>
                  _selectionMenu(ref, session.current!, selected),
            ),
        ],
      );
    } else {
      child = InkWell(
        mouseCursor: appClickableMouseCursor,
        onTap: actions.toggleFolders,
        child: Row(
          children: [
            Icon(folderIcon, color: color),
            const SizedBox(width: 8),
            Text(
              session.current?.tl ?? '未选择'.tl,
              style: const TextStyle(fontSize: 16),
            ),
            const Spacer(),
            Icon(
              session.selectingFolder
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
          ],
        ),
      );
    }
    return Material(
      elevation: 1,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _kSecondaryTopBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    );
  }

  /// 多选操作仅传入稳定快照，不存储菜单回调。
  List<PopupMenuEntry<void>> _selectionMenu(
    WidgetRef ref,
    String folder,
    List<FavoriteItem> items,
  ) => [
    popupMenuItem(
      text: '删除'.tl,
      icon: Icons.delete_outline,
      onTap: () async {
        final actions = ref.read(localFavoritesProvider.notifier);
        await performFavoriteAction(() => actions.deleteComics(folder, items));
      },
    ),
    popupMenuItem(
      text: '复制到'.tl,
      icon: Icons.drive_file_move_outlined,
      onTap: () => copyAllTo(folder, items),
    ),
    popupMenuItem(
      text: '下载'.tl,
      icon: Icons.download,
      onTap: () async {
        final manager = ref.read(downloadManagerProvider.notifier);
        for (final comic in items) {
          await comic.addDownload(manager);
        }
        showToast(message: '已添加下载任务'.tl);
      },
    ),
    popupMenuItem(
      text: '更新漫画信息'.tl,
      icon: Icons.sync,
      onTap: () => UpdateFavoritesInfoDialog.show(items, folder),
    ),
  ];

  /// 保持网络与本地目录的原有网格布局。
  Widget _folders(BuildContext context, WidgetRef ref) {
    ref.watch(comicSourceRegistryProvider);
    final sources = ref
        .watch(appSettingProvider(AppSettingKeys.networkFavoritePages))
        .split(',')
        .map(getFavoriteDataOrNull)
        .whereType<FavoriteData>()
        .toList();
    final local = ref.watch(localFavoritesProvider);
    return SmoothCustomScrollView(
      slivers: [
        _title('网络'.tl),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedHeight(
              maxCrossAxisExtent: 240,
              itemHeight: 48,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => InkWell(
                mouseCursor: appClickableMouseCursor,
                onTap: () => ref
                    .read(favoritesSessionProvider.notifier)
                    .openNetwork(sources[i]),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(
                      Icons.folder_special,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(sources[i].title.tl),
                  ],
                ),
              ),
              childCount: sources.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider()),
        _title('本地'.tl),
        SliverToBoxAdapter(
          child: Wrap(
            children: [
              _utility(
                '新建'.tl,
                Icons.create_new_folder_outlined,
                () => showDialog(
                  context: context,
                  builder: (_) => const CreateFolderDialog(),
                ),
              ),
              _utility(
                '搜索'.tl,
                Icons.search,
                () => App.to(context, () => const LocalSearchPage()),
              ),
              _utility(
                '排序'.tl,
                Icons.reorder,
                () => App.to(context, () => const FavoritesOrderPage()),
              ),
            ],
          ),
        ),
        local.when(
          loading: () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: TextButton(
              onPressed: () => ref.invalidate(localFavoritesProvider),
              child: Text('本地收藏加载失败: $error'),
            ),
          ),
          data: (data) => SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedHeight(
                maxCrossAxisExtent: 260,
                itemHeight: 48,
              ),
              delegate: SliverChildBuilderDelegate((context, i) {
                final folder = data.folderNames[i];
                return GestureDetector(
                  onLongPressStart: (details) =>
                      _folderMenu(context, ref, folder, details.globalPosition),
                  child: InkWell(
                    mouseCursor: appClickableMouseCursor,
                    onTap: () => ref
                        .read(favoritesSessionProvider.notifier)
                        .openLocal(folder),
                    onSecondaryTapUp: (details) => _folderMenu(
                      context,
                      ref,
                      folder,
                      details.globalPosition,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          Icons.folder,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            folder,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ref
                            .watch(localFavoriteCountProvider(folder))
                            .when(
                              data: (count) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              loading: () => const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              error: (_, __) => const Text('–'),
                            ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                );
              }, childCount: data.folderNames.length),
            ),
          ),
        ),
      ],
    );
  }

  /// 分区标题。
  Widget _title(String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, style: const TextStyle(fontSize: 18)),
    ),
  );

  /// 收藏夹工具按钮。
  Widget _utility(String title, IconData icon, VoidCallback onTap) => InkWell(
    mouseCursor: appClickableMouseCursor,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 72,
      height: 72,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(icon, size: 24),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  /// 内容按收藏位置复用，条目数量变化不销毁滚动控制器。
  Widget _content(FavoritesSessionState session) {
    if (session.current == null) return const SizedBox.shrink();
    if (session.isNetwork == true) {
      final data = getFavoriteDataOrNull(session.sourceKey!);
      return data == null
          ? const SizedBox.shrink()
          : NetworkFavoritePage(data, key: ValueKey(data.key));
    }
    return ComicsPageView(
      folder: session.current!,
      key: ValueKey(session.current),
    );
  }

  /// 收藏夹菜单的写操作统一通过 Notifier。
  void _folderMenu(
    BuildContext context,
    WidgetRef ref,
    String folder,
    Offset position,
  ) {
    showContextMenu(
      context: context,
      globalPosition: position,
      items: [
        popupMenuItem(
          text: '删除'.tl,
          icon: Icons.delete_outline,
          onTap: () {
            final actions = ref.read(localFavoritesProvider.notifier);
            showConfirmDialog(
              context,
              '确认删除'.tl,
              '此操作无法撤销, 是否继续?'.tl,
              () => performFavoriteAction(() => actions.deleteFolder(folder)),
            );
          },
        ),
        popupMenuItem(
          text: '排序'.tl,
          icon: Icons.sort,
          onTap: () => App.to(context, () => LocalFavoritesFolder(folder)),
        ),
        popupMenuItem(
          text: '重命名'.tl,
          icon: Icons.drive_file_rename_outline,
          onTap: () => showDialog(
            context: context,
            builder: (_) => RenameFolderDialog(folder),
          ),
        ),
        popupMenuItem(
          text: '检查漫画存活'.tl,
          icon: Icons.fact_check_outlined,
          onTap: () => checkFolder(folder),
        ),
        popupMenuItem(
          text: '导出'.tl,
          icon: Icons.file_upload_outlined,
          onTap: () => performFavoriteAction(() async {
            final json = await ref
                .read(localFavoritesRepositoryProvider)
                .folderToJsonString(folder);
            await exportStringDataAsFile(json, '$folder.json');
          }),
        ),
        popupMenuItem(
          text: '下载全部'.tl,
          icon: Icons.download,
          onTap: () => performFavoriteAction(() async {
            final manager = ref.read(downloadManagerProvider.notifier);
            final items = await ref.read(
              folderFavoritesProvider(folder).future,
            );
            for (final comic in items) {
              await comic.addDownload(manager);
            }
            showToast(message: '已添加下载任务'.tl);
          }),
        ),
        popupMenuItem(
          text: '更新漫画信息'.tl,
          icon: Icons.sync,
          onTap: () => performFavoriteAction(() async {
            final items = await ref.read(
              folderFavoritesProvider(folder).future,
            );
            await UpdateFavoritesInfoDialog.show(items, folder);
          }),
        ),
      ],
    );
  }
}

/// 收藏夹内容视图，控制器仅保存滚动与动画状态。
class ComicsPageView extends ConsumerStatefulWidget {
  const ComicsPageView({required this.folder, super.key});
  final String folder;
  @override
  ConsumerState<ComicsPageView> createState() => _ComicsPageViewState();
}

class _ComicsPageViewState extends ConsumerState<ComicsPageView> {
  final _scrollController = ScrollController();
  bool _showButton = true;
  double _location = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollChanged);
  }

  /// 浮动按钮可见性是当前滚动视图的局部动画状态。
  void _scrollChanged() {
    final offset = _scrollController.offset;
    final show = offset <= _location || offset == 0;
    if (show != _showButton) setState(() => _showButton = show);
    _location = offset;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 有网络关联时同步，否则重新读取当前收藏夹。
  Future<void> _refresh() async {
    await performFavoriteAction(() async {
      final sync = await ref.read(
        favoriteFolderSyncProvider(widget.folder).future,
      );
      if (!mounted) return;
      if (sync == null) {
        ref.invalidate(folderFavoritesProvider(widget.folder));
        await ref.read(folderFavoritesProvider(widget.folder).future);
      } else {
        await startFolderSync(context, sync);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(folderFavoritesProvider(widget.folder));
    final session = ref.watch(favoritesSessionProvider);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () =>
                ref.invalidate(folderFavoritesProvider(widget.folder)),
            child: Text('收藏加载失败，点击重试: $error'),
          ),
        ),
        data: (comics) => RefreshIndicator(
          onRefresh: _refresh,
          child: Scrollbar(
            controller: _scrollController,
            interactive: true,
            thickness: App.isMobile ? 12 : null,
            radius: const Radius.circular(8),
            child: SmoothScrollProvider(
              controller: _scrollController,
              builder: (context, controller, physics) {
                if (comics.isEmpty) {
                  return CustomScrollView(
                    controller: controller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        child: Center(child: Text('这里什么都没有'.tl)),
                      ),
                    ],
                  );
                }
                return GridView.builder(
                  controller: controller,
                  physics: physics,
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithComics(),
                  itemCount: comics.length,
                  itemBuilder: (context, index) {
                    final comic = comics[index];
                    final selected = session.selected.contains(comic.identity);
                    return AnimatedContainer(
                      key: ValueKey(comic.identity),
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : null,
                      ),
                      child: LocalFavoriteTile(
                        comic,
                        widget.folder,
                        true,
                        showFolderInfo: true,
                        onTap: () {
                          if (session.selected.isEmpty) return false;
                          ref
                              .read(favoritesSessionProvider.notifier)
                              .toggle(comic.identity);
                          return true;
                        },
                        onLongPressed: () => ref
                            .read(favoritesSessionProvider.notifier)
                            .toggle(comic.identity),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _showButton
            ? FloatingActionButton(
                key: const Key('FAB'),
                onPressed: _refresh,
                child: const Icon(Icons.refresh),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

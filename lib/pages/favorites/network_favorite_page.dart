import 'package:pica_comic/foundation/def.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';

import 'network_favorites_providers.dart';

/// 网络收藏，收藏夹查询与操作状态均由 Riverpod 管理。
class NetworkFavoritePage extends StatelessWidget {
  const NetworkFavoritePage(this.data, {super.key});
  final FavoriteData data;
  @override
  Widget build(BuildContext context) => data.multiFolder
      ? _NetworkFoldersView(data: data)
      : _NetworkComicsView(data: data);
}

/// 网络收藏夹目录。
class _NetworkFoldersView extends ConsumerWidget {
  const _NetworkFoldersView({required this.data});
  final FavoriteData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (sourceKey: data.key, comicId: null as String?);
    final folders = ref.watch(networkFavoriteFoldersProvider(query));
    return folders.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: TextButton(
          onPressed: () =>
              ref.invalidate(networkFavoriteFoldersProvider(query)),
          child: Text('加载失败，点击重试: $error'),
        ),
      ),
      data: (value) {
        final entries = value.folders.entries.toList();
        if (data.allFavoritesId != null &&
            !value.folders.containsKey(data.allFavoritesId)) {
          entries.insert(0, MapEntry(data.allFavoritesId!, '全部'.tl));
        }
        return SmoothCustomScrollView(
          slivers: [
            SliverGridViewWithFixedItemHeight(
              maxCrossAxisExtent: 450,
              itemHeight: 64,
              delegate: SliverChildBuilderDelegate((context, i) {
                final entry = entries[i];
                return ListTile(
                  title: Text(entry.value),
                  leading: const Icon(Icons.folder),
                  onTap: () => App.to(
                    context,
                    () => _NetworkComicsView(
                      data: data,
                      folderId: entry.key,
                      title: entry.value,
                    ),
                  ),
                  trailing:
                      data.deleteFolder == null ||
                          entry.key == data.allFavoritesId
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () {
                            final actions = ref.read(
                              networkFavoriteActionsProvider.notifier,
                            );
                            showConfirmDialog(
                              context,
                              '删除'.tl,
                              '确认删除收藏夹?'.tl,
                              () async {
                                final result = await actions.deleteFolder(
                                  data.key,
                                  entry.key,
                                );
                                if (result.error) {
                                  showToast(
                                    message: result.errorMessageWithoutNull,
                                  );
                                }
                              },
                            );
                          },
                        ),
                );
              }, childCount: entries.length),
            ),
            if (data.addFolder != null)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 60,
                  child: Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('创建收藏夹'.tl),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) =>
                            _CreateNetworkFolderDialog(sourceKey: data.key),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 未提交的名称属于输入草稿，提交状态由操作 Provider 管理。
class _CreateNetworkFolderDialog extends ConsumerStatefulWidget {
  const _CreateNetworkFolderDialog({required this.sourceKey});
  final String sourceKey;
  @override
  ConsumerState<_CreateNetworkFolderDialog> createState() =>
      _CreateNetworkFolderDialogState();
}

class _CreateNetworkFolderDialogState
    extends ConsumerState<_CreateNetworkFolderDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('创建收藏夹'.tl),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: '名称'.tl,
        border: const OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: ref.watch(networkFavoriteActionsProvider).isLoading
            ? null
            : () async {
                final actions = ref.read(
                  networkFavoriteActionsProvider.notifier,
                );
                final result = await actions.createFolder(
                  widget.sourceKey,
                  _controller.text,
                );
                if (result.error) {
                  showToast(message: result.errorMessageWithoutNull);
                } else if (context.mounted) {
                  Navigator.pop(context);
                }
              },
        child: Text('提交'.tl),
      ),
    ],
  );
}

/// 每次浏览持有独立游标会话，账户变化时丢弃旧列表。
class _NetworkComicsView extends ConsumerStatefulWidget {
  const _NetworkComicsView({required this.data, this.folderId, this.title});
  final FavoriteData data;
  final String? folderId;
  final String? title;
  @override
  ConsumerState<_NetworkComicsView> createState() => _NetworkComicsViewState();
}

class _NetworkComicsViewState extends ConsumerState<_NetworkComicsView> {
  final _session = UniqueKey().toString();
  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(
      networkFavoriteRevisionProvider(widget.data.key),
    );
    final query = (
      sourceKey: widget.data.key,
      folderId: widget.folderId,
      sessionId: '$_session:${revision.session}',
    );
    final loader = ref.watch(networkFavoriteLoaderProvider(query));
    final page = _NetworkComicsList(
      data: widget.data,
      folderId: widget.folderId,
      title: widget.title,
      sessionId: query.sessionId,
      loader: loader,
    );
    ref.listen(networkFavoriteRevisionProvider(widget.data.key), (
      previous,
      next,
    ) {
      if (previous != null &&
          previous.session == next.session &&
          previous.revision != next.revision) {
        loader.reset();
        scheduleMicrotask(() {
          if (mounted) {
            ref
                .read(comicListPageLogicProvider(page.pageConfig()).notifier)
                .refresh();
          }
        });
      }
    });
    return page;
  }
}

/// 继续使用现有漫画列表的连续浏览与分页模式。
class _NetworkComicsList extends ComicsPage<BaseComic> {
  const _NetworkComicsList({
    required this.data,
    required this.folderId,
    required this.sessionId,
    required this.loader,
    this.title,
  });
  final FavoriteData data;
  final String? folderId;
  final String sessionId;
  final NetworkFavoritePageLoader loader;
  @override
  final String? title;
  @override
  String get tag => 'favorites:${data.key}:${folderId ?? ""}:$sessionId';
  @override
  ComicType get comicType => ComicType.fromString(data.key);
  @override
  Future<Res<List<BaseComic>>> getComics(int page, Ref ref) =>
      loader.load(page);
  @override
  List<ComicTileMenuOption>? buildAddonMenuOptions(
    ComicListPageLogic logic,
    WidgetRef ref,
  ) => [
    if (data.addOrDelFavorite != null)
      ComicTileMenuOption('取消收藏'.tl, Icons.playlist_remove_outlined, (
        id,
      ) async {
        if (id == null) return;
        final result = await ref
            .read(networkFavoriteActionsProvider.notifier)
            .change(data.key, id, folderId ?? '0', false);
        if (result.error) showToast(message: result.errorMessageWithoutNull);
      }),
  ];
}

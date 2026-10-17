import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/tools/translations.dart';

import 'favorite_action_widgets.dart';
import 'local_favorites.dart';
import 'local_favorites_providers.dart';

/// 拖动结束即保存排序，页面退出不再承担持久化工作。
class FavoritesOrderPage extends ConsumerStatefulWidget {
  const FavoritesOrderPage({this.folder, super.key});
  final String? folder;
  @override
  ConsumerState<FavoritesOrderPage> createState() => _FavoritesOrderPageState();
}

class _FavoritesOrderPageState extends ConsumerState<FavoritesOrderPage> {
  final _scrollController = ScrollController();
  List<String>? _folderDraft;
  List<FavoriteItem>? _comicDraft;
  int _generation = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 仅最新一次拖动提交后清除本地草稿。
  Future<void> _save(Future<void> Function() operation) async {
    final generation = ++_generation;
    await performFavoriteAction(operation);
    if (mounted && generation == _generation) {
      setState(() {
        _folderDraft = null;
        _comicDraft = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    return Scaffold(
      appBar: AppBar(title: Text(folder ?? '排序'.tl)),
      body: folder == null
          ? ref
                .watch(localFavoritesProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _error(
                    error,
                    () => ref.invalidate(localFavoritesProvider),
                  ),
                  data: (data) => _folders(_folderDraft ?? data.folderNames),
                )
          : ref
                .watch(folderFavoritesProvider(folder))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _error(
                    error,
                    () => ref.invalidate(folderFavoritesProvider(folder)),
                  ),
                  data: (data) => _comics(folder, _comicDraft ?? data),
                ),
    );
  }

  /// 显示读取错误并允许重试。
  Widget _error(Object error, VoidCallback retry) => Center(
    child: TextButton(onPressed: retry, child: Text('加载失败，点击重试: $error')),
  );

  /// 收藏夹排序网格。
  Widget _folders(List<String> folders) => ReorderableBuilder(
    scrollController: _scrollController,
    longPressDelay: Duration(milliseconds: App.isDesktop ? 100 : 500),
    onReorder: (reorder) {
      final next = reorder(folders.toList()).cast<String>();
      setState(() => _folderDraft = next);
      final actions = ref.read(localFavoritesProvider.notifier);
      _save(() => actions.reorderFolders(next));
    },
    builder: (children) => GridView(
      controller: _scrollController,
      gridDelegate: const SliverGridDelegateWithFixedHeight(
        maxCrossAxisExtent: 260,
        itemHeight: 56,
      ),
      children: children,
    ),
    children: [
      for (final folder in folders)
        ListTile(
          key: ValueKey(folder),
          leading: const Icon(Icons.folder),
          title: Text(folder),
        ),
    ],
  );

  /// 收藏夹内作品排序网格，作品身份包含来源。
  Widget _comics(String folder, List<FavoriteItem> comics) =>
      ReorderableBuilder(
        scrollController: _scrollController,
        longPressDelay: Duration(milliseconds: App.isDesktop ? 100 : 500),
        onReorder: (reorder) {
          final next = reorder(comics.toList()).cast<FavoriteItem>();
          setState(() => _comicDraft = next);
          final actions = ref.read(localFavoritesProvider.notifier);
          _save(() => actions.reorder(folder, next));
        },
        builder: (children) => GridView(
          controller: _scrollController,
          gridDelegate: SliverGridDelegateWithComics(),
          children: children,
        ),
        children: [
          for (final comic in comics)
            LocalFavoriteTile(
              comic,
              folder,
              false,
              key: ValueKey(comic.identity),
            ),
        ],
      );
}

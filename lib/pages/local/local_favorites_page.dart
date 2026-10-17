import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/directory_favorites_providers.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/translations.dart';

import '../reader/comic_reading_page.dart';
import 'local_comic_page.dart';
import 'local_comic_tile.dart';

/// 本地目录收藏列表，收藏状态变化后自动更新。
class LocalFavoritesPage extends ConsumerWidget {
  const LocalFavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(directoryFavoritesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('本地收藏'.tl)),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(directoryFavoritesProvider),
            child: Text('加载失败，点击重试: $error'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) return Center(child: Text('暂无收藏'.tl));
          final paths = items.map((e) => e.path).toList();
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.7,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final title = path.basename(item.path);
              return LocalComicTile(
                key: ValueKey(item.path),
                model: LocalComicModel(
                  path: item.path,
                  title: title,
                  cover: '',
                ),
                onReload: () {},
                allDirPaths: paths,
                onTap: (history) => App.globalTo(
                  () => ComicReadingPage.localComic(
                    item.path,
                    title,
                    allDirPaths: paths,
                    initialPage: history?.optInt('pageIndex', 1) ?? 1,
                    isReversed: history?.optInt('isReversed') == 1,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

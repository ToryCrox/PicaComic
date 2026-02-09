import 'package:flutter/material.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/foundation/app.dart';
import 'dart:io';
import 'package:path/path.dart' as Path;
import '../reader/comic_reading_page.dart';
import 'local_comic_page.dart';
import 'local_comic_tile.dart';

class LocalFavoritesPage extends StatefulWidget {
  const LocalFavoritesPage({super.key});

  @override
  State<LocalFavoritesPage> createState() => _LocalFavoritesPageState();
}

class _LocalFavoritesPageState extends State<LocalFavoritesPage> {
  List<LocalComicModel> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final favoritesData = await downloadManager.getAllLocalFavorites();
    final List<LocalComicModel> list = [];
    for (final data in favoritesData) {
      final path = data['path'] as String;
      if (Directory(path).existsSync()) {
        final cover = await _getCoverImage(path);
        list.add(LocalComicModel(
          path: path,
          title: Path.basename(path),
          cover: cover,
        ));
      }
    }
    if (mounted) {
      setState(() {
        _favorites = list;
        _loading = false;
      });
    }
  }

  Future<String> _getCoverImage(String directory) async {
    final dir = Directory(directory);
    try {
      final file = await dir.list(recursive: true).firstWhere((e) =>
          e is File &&
          (e.path.endsWith('.jpg') ||
              e.path.endsWith('.png') ||
              e.path.endsWith('.webp') ||
              e.path.endsWith('.jpeg')));
      return file.path;
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("本地收藏".tl),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(child: Text("暂无收藏".tl))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.7,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final model = _favorites[index];
                    return LocalComicTile(
                      model: model,
                      onReload: _loadFavorites,
                      allDirPaths: _favorites.map((e) => e.path).toList(),
                      onTap: (history) async {
                        // 收藏页点击只能是阅读，因为收藏的是具体项
                        final initIndex = history?.optInt('pageIndex', 1) ?? 1;
                        final isReversed = history?.optInt('isReversed') == 1;
                        await App.globalTo(() => ComicReadingPage.localComic(
                              model.path,
                              model.title,
                              allDirPaths: _favorites.map((e) => e.path).toList(),
                              initialPage: initIndex,
                              isReversed: isReversed,
                            ));
                      },
                    );
                  },
                ),
    );
  }
}

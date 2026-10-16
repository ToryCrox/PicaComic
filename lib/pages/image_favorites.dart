import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';

import '../comic_source/comic_source.dart';
import '../components/components.dart';
import '../foundation/app.dart';
import '../foundation/app_settings_provider.dart';
import '../foundation/image_favorites.dart';
import '../foundation/image_favorites_providers.dart';
import '../foundation/log.dart';
import '../foundation/ui_mode.dart';
import '../network/eh_network/eh_models.dart';
import '../network/hitomi_network/hitomi_models.dart';
import '../tools/map_extension.dart';
import '../tools/translations.dart';
import 'reader/comic_reading_page.dart';

/// 图片收藏列表与标题分组。
class ImageFavoritesPage extends ConsumerStatefulWidget {
  const ImageFavoritesPage({super.key, this.filterTitle = ''});
  final String filterTitle;

  @override
  ConsumerState<ImageFavoritesPage> createState() => _ImageFavoritesPageState();
}

/// 页面仅保存显示方式，收藏数据由 Riverpod 管理。
class _ImageFavoritesPageState extends ConsumerState<ImageFavoritesPage> {
  bool _showGroup = false;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      '图片收藏'.tl +
          (widget.filterTitle.isEmpty ? '' : ' - ${widget.filterTitle}'),
    );
    final actions = [
      IconButton(
        tooltip: _showGroup ? '显示列表'.tl : '显示分组'.tl,
        icon: Icon(_showGroup ? Icons.list : Icons.grid_view),
        onPressed: () => setState(() => _showGroup = !_showGroup),
      ),
    ];
    return Scaffold(
      appBar: UiMode.m1(context)
          ? AppBar(title: title, actions: actions)
          : Appbar(title: title, actions: actions),
      body: _body(),
    );
  }

  /// 为分组及列表提供明确的加载、错误、空状态。
  Widget _body() {
    if (_showGroup) {
      return ref
          .watch(imageFavoriteTitlesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _error(error),
            data: (titles) => titles.isEmpty
                ? Center(child: Text('暂无图片收藏'.tl))
                : ListView.separated(
                    itemCount: titles.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) => ListTile(
                      title: Text(titles[index]),
                      onTap: () => context.to(
                        () => ImageFavoritesPage(filterTitle: titles[index]),
                      ),
                    ),
                  ),
          );
    }
    final scale = ref.watch(
      appearanceSettingsProvider.select((value) => value.imageFavoriteScale),
    );
    return ref
        .watch(filteredImageFavoritesProvider(widget.filterTitle))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _error(error),
          data: (images) => images.isEmpty
              ? Center(child: Text('暂无图片收藏'.tl))
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200 * scale,
                    childAspectRatio: 9 / 16,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  padding: const EdgeInsets.all(12),
                  itemCount: images.length,
                  itemBuilder: (_, index) => FavoriteImageTile(
                    images[index],
                    key: ValueKey(images[index].recordId),
                  ),
                ),
        );
  }

  /// 数据读取失败时允许重试。
  Widget _error(Object error) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('图片收藏加载失败'.tl),
        TextButton(
          onPressed: () => ref.invalidate(imageFavoritesProvider),
          child: Text('重试'.tl),
        ),
      ],
    ),
  );
}

/// 使用磁盘 WebP 缩略图的竖向收藏卡片。
class FavoriteImageTile extends ConsumerWidget {
  const FavoriteImageTile(this.image, {super.key});
  final ImageFavorite image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnail = ref.watch(imageFavoriteThumbnailProvider(image));
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumbnail.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _fallback(ref),
            data: (file) => Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _retry(ref),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
              ),
              child: Text(
                image.title.replaceAll('\n', ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          InkWell(
            mouseCursor: appClickableMouseCursor,
            onTap: () => _openComic(ref),
            onLongPress: () => _menu(context, ref, null),
            onSecondaryTapDown: (details) =>
                _menu(context, ref, details.globalPosition),
          ),
        ],
      ),
    );
  }

  /// 工具不可用时用限定解码尺寸的原图临时预览。
  Widget _fallback(WidgetRef ref) => FutureBuilder<File>(
    future: ref.read(imageFavoritesRepositoryProvider).originalFile(image),
    builder: (_, snapshot) => snapshot.hasData
        ? Image(
            image: ResizeImage(
              FileImage(snapshot.data!),
              width: 432,
              height: 768,
              policy: ResizeImagePolicy.fit,
            ),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _retry(ref),
          )
        : _retry(ref),
  );

  /// 失败占位；卡片菜单提供重新生成操作。
  Widget _retry(WidgetRef ref) => Center(
    child: Icon(
      Icons.broken_image_outlined,
      color: Theme.of(ref.context).colorScheme.onSecondaryContainer,
    ),
  );

  /// 按来源打开原章节；本地或已移除的来源查看收藏原图。
  void _openComic(WidgetRef ref) {
    if (image.sourceKey == 'local' ||
        (ComicSource.find(image.sourceKey) == null &&
            !const [
              'picacg',
              'ehentai',
              'jm',
              'hitomi',
              'htmanga',
              'nhentai',
            ].contains(image.sourceKey))) {
      _viewOriginal(ref);
      return;
    }
    try {
      _readWithKey(
        image.sourceKey,
        image.comicId,
        image.ep,
        image.page,
        image.title,
        image.otherInfo,
      );
    } catch (error, stack) {
      Log.e('打开收藏漫画失败', error: error, stackTrace: stack);
      _viewOriginal(ref);
    }
  }

  void _readWithKey(
    String key,
    String target,
    int ep,
    int page,
    String title,
    Map<String, dynamic> otherInfo,
  ) {
    switch (key) {
      case "picacg":
        App.globalTo(
          () => ComicReadingPage.picacg(
            target,
            ep,
            List.from(otherInfo.optStringList("eps")),
            title,
            initialPage: page,
          ),
        );
      case "ehentai":
        App.globalTo(
          () => ComicReadingPage.ehentai(
            Gallery.fromJson(otherInfo["gallery"]),
            initialPage: page,
          ),
        );
      case "jm":
        App.globalTo(
          () => ComicReadingPage(
            JmReadingData(
              title,
              target,
              List.from(otherInfo.optStringList('eps')),
              List.from(otherInfo.optStringList("jmEpNames")),
            ),
            page,
            ep,
          ),
        );
      case "hitomi":
        App.globalTo(
          () => ComicReadingPage(
            HitomiReadingData(
              title,
              target,
              otherInfo
                  .optDynamicList("hitomi")
                  .map((e) => HitomiFile.fromMap(e))
                  .toList(),
              target,
            ),
            page,
            0,
          ),
        );
      case "htManga":
      case "htmanga":
        App.globalTo(
          () => ComicReadingPage.htmanga(target, title, initialPage: page),
        );
      case "nhentai":
        App.globalTo(
          () => ComicReadingPage.nhentai(target, title, initialPage: page),
        );
      default:
        var source = ComicSource.find(key);
        if (source == null) throw "Unknown source $key";
        App.globalTo(
          () => ComicReadingPage(
            ReadingData.fromSource(
              target,
              title,
              source,
              Map.from(otherInfo["eps"]),
              chapterGroups: [
                for (final group
                    in otherInfo['chapterGroups'] as List? ?? const [])
                  ComicChapterGroup.fromMap(
                    Map<String, dynamic>.from(group as Map),
                  ),
              ],
            ),
            page,
            ep,
          ),
        );
    }
  }

  /// 显示原图，可缩放，不使用缩略图替代原图。
  Future<void> _viewOriginal(WidgetRef ref) async {
    try {
      final file = await ref
          .read(imageFavoritesRepositoryProvider)
          .originalFile(image);
      if (!ref.context.mounted) return;
      await Navigator.of(ref.context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(image.title)),
            body: PhotoView(imageProvider: FileImage(file)),
          ),
        ),
      );
    } catch (error, stack) {
      Log.e('查看收藏原图失败', error: error, stackTrace: stack);
      showToast(message: '收藏原图不存在'.tl);
    }
  }

  /// 删除成功后由 Provider 自动刷新所有收藏页面。
  Future<void> _delete(WidgetRef ref) async {
    try {
      await ref.read(imageFavoritesProvider.notifier).delete(image.recordId);
      showToast(message: '删除成功'.tl);
    } catch (error, stack) {
      Log.e('删除图片收藏失败', error: error, stackTrace: stack);
      showToast(message: '图片收藏操作失败'.tl);
    }
  }

  /// 重新生成缩略图，不影响原图。
  Future<void> _regenerate(WidgetRef ref) async {
    try {
      await ref
          .read(imageFavoritesRepositoryProvider)
          .regenerateThumbnail(image);
      if (ref.context.mounted) {
        ref.invalidate(imageFavoriteThumbnailProvider(image));
      }
    } catch (error) {
      showToast(message: '图片收藏操作失败'.tl);
    }
  }

  /// 长按与右键共用操作菜单。
  void _menu(BuildContext context, WidgetRef ref, Offset? position) {
    final items = [
      popupMenuItem(
        text: '查看'.tl,
        icon: Icons.menu_book,
        onTap: () => _openComic(ref),
      ),
      popupMenuItem(
        text: '查看原图'.tl,
        icon: Icons.image_outlined,
        onTap: () => _viewOriginal(ref),
      ),
      popupMenuItem(
        text: '重新生成缩略图'.tl,
        icon: Icons.refresh,
        onTap: () async {
          final repository = ref.read(imageFavoritesRepositoryProvider);
          try {
            await repository.regenerateThumbnail(image);
            if (context.mounted) {
              ref.invalidate(imageFavoriteThumbnailProvider(image));
            }
          } catch (error) {
            showToast(message: '图片收藏操作失败'.tl);
          }
        },
      ),
      popupMenuItem(
        text: '分组'.tl,
        icon: Icons.folder_outlined,
        onTap: () =>
            context.to(() => ImageFavoritesPage(filterTitle: image.title)),
      ),
      popupMenuItem(
        text: '删除'.tl,
        icon: Icons.delete_outline,
        onTap: () => showConfirmDialog(
          context,
          '确认删除'.tl,
          '要删除这个图片吗'.tl,
          () => _delete(ref),
        ),
      ),
    ];
    if (position != null) {
      showContextMenu(context: context, globalPosition: position, items: items);
    } else {
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text('查看原图'.tl),
                onTap: () {
                  Navigator.pop(context);
                  _viewOriginal(ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('重新生成缩略图'.tl),
                onTap: () {
                  Navigator.pop(context);
                  _regenerate(ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('删除'.tl),
                onTap: () {
                  Navigator.pop(context);
                  showConfirmDialog(
                    context,
                    '确认删除'.tl,
                    '要删除这个图片吗'.tl,
                    () => _delete(ref),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
  }
}

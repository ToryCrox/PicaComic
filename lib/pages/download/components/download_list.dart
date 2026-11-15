import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/ai/ai.dart';
import 'package:pica_comic/ai/ai_cached_title_builder.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/local/local_thumbs_page.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/image_utils.dart';
import 'package:path/path.dart' as Path;

import 'package:pica_comic/base.dart';
import 'package:pica_comic/pages/download/download_helper.dart';
import '../download_providers.dart';
import 'download_comic_card.dart';
import 'download_tile.dart';
import 'download_menus.dart';
import 'comic_info_view.dart';

/// 下载列表组件
///
/// 使用 Riverpod 管理状态，显示过滤后的漫画列表
class DownloadList extends ConsumerWidget {
  const DownloadList({
    super.key,
    required this.pageId,
    required this.onRefresh,
    required this.onRefreshTags,
  });

  final String pageId;
  final VoidCallback onRefresh;
  final VoidCallback onRefreshTags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comicsAsync = ref.watch(filteredComicsProvider(pageId));
    final pageState = ref.watch(downloadPageStateProvider(pageId));

    return comicsAsync.when(
      skipLoadingOnReload: true,
      data: (comics) => _buildGrid(context, ref, comics, pageState),
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) =>
          SliverToBoxAdapter(child: Center(child: Text("加载失败: $error"))),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<DownloadedItem> comics,
    DownloadPageState pageState,
  ) {
    final selectedComics = pageState.isSelecting
        ? comics
              .where((comic) => pageState.selectedIds.contains(comic.id))
              .toList(growable: false)
        : const <DownloadedItem>[];
    return SliverPadding(
      padding: const EdgeInsets.all(8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          childCount: comics.length,
          (context, index) => _buildItem(
            context,
            ref,
            comics[index],
            pageState,
            selectedComics,
          ),
        ),
        gridDelegate: SliverGridDelegateWithDownloadComics(
          infoHeight: downloadComicCardInfoHeight(
            MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref,
    DownloadedItem item,
    DownloadPageState pageState,
    List<DownloadedItem> selectedComics,
  ) {
    final downloadManager = ref.read(downloadManagerProvider.notifier);
    final isSelected = pageState.selectedIds.contains(item.id);

    return AiCachedTitleBuilder(
      resource: AiComicResource(
        sourceKey: item.sourceKey,
        downloadId: item.id,
        targetLanguage: App.locale.toLanguageTag(),
      ),
      // 显示名对 EH 等来源会追加页数和下载 ID；缓存校验必须使用
      // 详情页实际参与翻译的原始标题，不能使用这个仅供 UI 的拼接文本。
      title: item.name,
      builder: (context, translatedTitle) => DownloadComicCard(
        item: item,
        pageId: pageId,
        translatedName: translatedTitle,
        isSelected: isSelected,
        isDragDisabled: pageState.isDragDisabled,
        draggedItems: pageState.isSelecting && selectedComics.isNotEmpty
            ? selectedComics
            : null,
        onTap: () async {
          if (pageState.isSelecting) {
            toggleSelection(ref, pageId, item.id);
            // 如果没有选中项，退出选择模式
            final newState = ref.read(downloadPageStateProvider(pageId));
            if (newState.selectedIds.isEmpty) {
              exitSelecting(ref, pageId);
            }
          } else {
            if (item.type == DownloadType.local) {
              item.read();
            } else {
              toComicInfoPage(item);
            }
          }
        },
        onLongTap: () {
          if (pageState.isSelecting) return;
          toggleSelection(ref, pageId, item.id);
          enterSelecting(ref, pageId);
        },
        onSecondaryTap: (details) async {
          final batchComics = pageState.isSelecting
              ? selectedComics
              : const <DownloadedItem>[];
          await showTileContextMenu(
            context: context,
            manager: downloadManager,
            details: details,
            comic: item,
            getOriginalTags: (item) => _originalTags(ref, item),
            onRefresh: onRefresh,
            onRefreshTags: onRefreshTags,
            onRemoveComic: () {
              // Provider will automatically update when DownloadManager notifies
            },
            onShowInfo: () {
              showDownloadedComicInfo(
                context: context,
                comic: item,
                onRefresh: onRefresh,
              );
            },
            onShowImageList: () => _goLocalComicPage(context, ref, item),
            selectedComics: batchComics,
            onBatchComplete: batchComics.isNotEmpty
                ? () {
                    exitSelecting(ref, pageId);
                    onRefresh();
                  }
                : null,
          );
        },
      ),
    );
  }

  /// 来源标签（排除已被用户标签覆盖的部分）。
  List<String> _originalTags(WidgetRef ref, DownloadedItem item) {
    final userTagsMap =
        ref.read(comicUserTagsProvider).asData?.value ??
        const <String, List<String>>{};
    return getOriginalTags(item, userTagsMap);
  }

  /// 打开图片列表页面
  void _goLocalComicPage(
    BuildContext context,
    WidgetRef ref,
    DownloadedItem comic,
  ) async {
    var dirPath = await ref
        .read(downloadManagerProvider.notifier)
        .getFullDirectory(comic.id);
    App.globalTo(
      () => LocalThumbsPage(
        dirPath: dirPath,
        onItemTap: (index, filePath) async {
          if (index <= 0) {
            comic.read();
            return;
          }
          int ep = 0;
          final file = File(filePath);
          final absPath = file.absolute.path;
          if (comic.type == DownloadType.picacg ||
              comic.type == DownloadType.jm) {
            final fileParent = file.parent;
            final fileParentPath = Path.normalize(file.parent.absolute.path);
            for (final e in comic.downloadedEps) {
              final epDirPath = Path.normalize("$dirPath/$e");
              if (epDirPath == fileParentPath) {
                ep = e;
                sFileRelativeFromPath = fileParent.path;
                final imageNames =
                    (await fileParent.list(recursive: true).toList())
                        .where(
                          (e) => !isInsideComicBackupDirectory(
                            e.path,
                            fileParent.path,
                          ),
                        )
                        .where(predictImageFile)
                        .sortedByName()
                        .map((e) => e.name)
                        .toList();
                index = imageNames.indexOf(Path.basename(absPath));
                if (index < 0) {
                  index = 0;
                }
                index += 1;
                break;
              }
            }
          }
          debugPrint(
            "Local thumbs eps: ${comic.downloadedEps}, ep: $ep, index: $index, page: $filePath",
          );
          comic.read(initialPage: index, ep: ep);
        },
      ),
    );
  }
}

/// SliverPersistentHeader 代理
class SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  SliverAppBarDelegate({
    required this.child,
    required this.maxHeight,
    required this.minHeight,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
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

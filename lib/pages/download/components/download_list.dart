import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/download/tag_assignment_dialog.dart';
import 'package:pica_comic/pages/local/local_thumbs_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/image_utils.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/foundation/file_utils.dart';
import 'package:path/path.dart' as Path;

import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/pages/download/download_helper.dart';
import '../download_providers.dart';
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
    final allTagsAsync = ref.watch(downloadTagsProvider);
    final userTagsMapAsync = ref.watch(comicUserTagsProvider);

    return comicsAsync.when(
      skipLoadingOnReload: true,
      data: (comics) {
        return allTagsAsync.when(
          skipLoadingOnReload: true,
          data: (allTags) {
            return userTagsMapAsync.when(
              skipLoadingOnReload: true,
              data: (userTagsMap) {
                return _buildGrid(
                  context,
                  ref,
                  comics,
                  pageState,
                  allTags,
                  userTagsMap,
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, s) =>
                  SliverToBoxAdapter(child: Center(child: Text("$e"))),
            );
          },
          loading: () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, s) => SliverToBoxAdapter(child: Center(child: Text("$e"))),
        );
      },
      loading: () => const SliverToBoxAdapter(
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
    List<TagInfo> allTags,
    Map<String, List<String>> userTagsMap,
  ) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        childCount: comics.length,
        (context, index) => _buildItem(
          context,
          ref,
          comics[index],
          index,
          pageState,
          allTags,
          userTagsMap,
        ),
      ),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref,
    DownloadedItem item,
    int index,
    DownloadPageState pageState,
    List<TagInfo> allTags,
    Map<String, List<String>> userTagsMap,
  ) {
    final isSelected = pageState.selectedIds.contains(item.id);
    final typeName = getComicTypeName(item);
    final displayName = getComicDisplayName(item);
    final sizeText = getComicSizeText(item);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: DownloadedComicTile(
          id: item.id,
          name: displayName,
          author: item.subTitle,
          imagePath: File(item.coverPath ?? ''),
          type: typeName,
          primaryTags: getUserTags(item, userTagsMap),
          tag: getRawTags(item, userTagsMap),
          onTagTap: (tag) => updateKeyword(ref, pageId, tag),
          onTagSecondaryTap: (tag, details) => _showTagMenu(
            context,
            ref,
            tag,
            item,
            false,
            details,
            userTagsMap,
          ),
          onPrimaryTagSecondaryTap: (tag, details) =>
              _showTagMenu(context, ref, tag, item, true, details, userTagsMap),
          onPrimaryTagTap: (tag) async {
            final tagId = allTags
                .firstWhere(
                  (element) => element.name == tag,
                  orElse: () => TagInfo(id: -1, name: '', comicCount: 0),
                )
                .id;
            if (tagId != -1) {
              updateTagFilter(ref, pageId, tagId);
            }
          },
          onManageTags: () async {
            final suggestedTags = [
              item.name,
              item.subTitle,
              ...getOriginalTags(item, userTagsMap),
            ];
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => TagAssignmentDialog(
                comicIds: [item.id],
                suggestedTags: suggestedTags,
              ),
            );
            if (result == true) {
              onRefreshTags();
            }
          },
          onOpenFolder: () async {
            var path = await downloadManager.getFullDirectory(item.id);
            FileUtils.openFileOrDirectory(path);
          },
          onRead: () async {
            item.read();
          },
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
          size: sizeText,
          onLongTap: () {
            if (pageState.isSelecting) return;
            toggleSelection(ref, pageId, item.id);
            enterSelecting(ref, pageId);
          },
          onSecondaryTap: (details) async {
            await showTileContextMenu(
              context: context,
              details: details,
              comic: item,
              getOriginalTags: (item) => getOriginalTags(item, userTagsMap),
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
              onShowImageList: () => _goLocalComicPage(item),
            );
          },
          isDragDisabled: pageState.isDragDisabled,
          downloadedItem: item,
        ),
      ),
    );
  }

  /// 打开图片列表页面
  void _goLocalComicPage(DownloadedItem comic) async {
    var dirPath = await downloadManager.getFullDirectory(comic.id);
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

  void _showTagMenu(
    BuildContext context,
    WidgetRef ref,
    String tag,
    DownloadedItem comic,
    bool isPrimary,
    TapDownDetails details,
    Map<String, List<String>> userTagsMap,
  ) {
    showDesktopMenu(
      App.globalContext!,
      Offset(details.globalPosition.dx, details.globalPosition.dy),
      [
        DesktopMenuEntry(
          text: "管理标签".tl,
          onClick: () async {
            await Future.delayed(const Duration(milliseconds: 300));
            final suggestedTags = [
              comic.name,
              comic.subTitle,
              ...getOriginalTags(comic, userTagsMap),
            ];
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => TagAssignmentDialog(
                comicIds: [comic.id],
                suggestedTags: suggestedTags,
              ),
            );
            if (result == true) {
              onRefreshTags();
            }
          },
        ),
        DesktopMenuEntry(
          text: "复制".tl,
          onClick: () {
            Clipboard.setData(ClipboardData(text: tag));
            showToast(message: "已复制".tl);
          },
        ),
        DesktopMenuEntry(
          text: "本地搜索".tl,
          onClick: () {
            updateKeyword(ref, pageId, tag);
          },
        ),
        DesktopMenuEntry(
          text: "搜索漫画".tl,
          onClick: () {
            String searchTag = tag;
            if (!isPrimary) {
              // 查找原始标签
              searchTag = comic.tags.firstWhere(
                (t) => t.translateTagsToCN == tag,
                orElse: () => tag,
              );
            } else {
              // 检查用户标签是否对应原始标签
              var originalTag = comic.tags.firstWhereOrNull(
                (t) => t.translateTagsToCN == tag || t == tag,
              );
              if (originalTag != null) {
                searchTag = originalTag;
              }
            }
            // 根据漫画类型确定搜索来源
            String sourceKey = "picacg";
            if (comic.type == DownloadType.ehentai) {
              sourceKey = "ehentai";
            } else if (comic.type == DownloadType.jm) {
              sourceKey = "jm";
            } else if (comic.type == DownloadType.hitomi) {
              sourceKey = "hitomi";
            } else if (comic.type == DownloadType.htmanga) {
              sourceKey = "htmanga";
            } else if (comic.type == DownloadType.nhentai) {
              sourceKey = "nhentai";
            } else if (comic.type == DownloadType.other) {
              if (comic is CustomDownloadedItem) {
                sourceKey = comic.sourceKey;
              }
            }
            context.to(
              () => SearchResultPage(
                keyword: searchTag,
                comicType: ComicType.fromString(sourceKey),
              ),
            );
          },
        ),
      ],
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

import 'dart:io';

import 'package:flutter/material.dart'; // ignore: unused_import
// ignore: unused_import

import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:path/path.dart' as path;

import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/ehentai/eh_gallery_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_comic_page.dart';
import 'package:pica_comic/pages/htmanga/ht_comic_page.dart';
import 'package:pica_comic/pages/jm/jm_comic_page.dart';
import 'package:pica_comic/pages/nhentai/comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/pages/download/translation_result_replacer.dart';

import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/type_util.dart';

/// 下载的漫画卡片组件
///
/// 继承自 ComicTile，用于显示已下载的漫画信息
class DownloadedComicTile extends ComicTile {
  final String id;
  final String size;
  final File imagePath;
  final String author;
  final String name;
  final String type;
  final String? translatedName;

  @override
  final List<String> primaryTags;
  final List<String> tag;
  final void Function() onTap;
  final void Function() onLongTap;
  final void Function(TapDownDetails details) onSecondaryTap;
  @override
  final void Function(String tag)? onTagTap;
  @override
  final void Function(String tag)? onPrimaryTagTap;
  @override
  final void Function(String tag, TapDownDetails details)? onTagSecondaryTap;
  @override
  final void Function(String tag, TapDownDetails details)?
  onPrimaryTagSecondaryTap;

  final VoidCallback? onManageTags;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRead;

  /// 是否禁用拖动
  final bool isDragDisabled;

  /// 下载的漫画项（用于获取图片文件）
  final DownloadedItem downloadedItem;

  /// 可替换的翻译结果摘要。
  final TranslationResultInfo? translationResult;

  /// 点击翻译结果标记时执行的操作。
  final VoidCallback? onTranslationResultTap;

  const DownloadedComicTile({
    super.key,
    required this.id,
    required this.size,
    required this.imagePath,
    required this.author,
    required this.name,
    required this.onTap,
    required this.onLongTap,
    required this.onSecondaryTap,
    required this.type,
    this.translatedName,
    this.primaryTags = const [],
    this.tag = const [],
    this.onTagTap,
    this.onPrimaryTagTap,
    this.onTagSecondaryTap,
    this.onPrimaryTagSecondaryTap,
    this.onManageTags,
    this.onOpenFolder,
    this.onRead,
    this.isDragDisabled = false,
    required this.downloadedItem,
    this.translationResult,
    this.onTranslationResultTap,
  });

  @override
  List<String>? get tags => tag
      .map((e) => App.locale.languageCode == "zh" ? e.translateTagsToCN : e)
      .toList();

  @override
  String get description {
    final sizeText = double.tryParse(size) == null ? size : "${size}MB";
    final authorText = author.trim();
    if (authorText.isEmpty) {
      return sizeText;
    }
    return "$authorText · $sizeText";
  }

  @override
  int get descriptionMaxLines => 1;

  @override
  String? get comicID {
    if (downloadedItem is DownloadedGallery) {
      return (downloadedItem as DownloadedGallery).gallery.link;
    }
    return downloadManager.getComicIdFromDownloadId(
      downloadedItem.type.toComicType(),
      downloadedItem.id,
    );
  }

  @override
  ComicType? get comicType => downloadedItem.type.toComicType();

  @override
  bool get showDownload => false;

  @override
  bool get showRead => false;

  @override
  Widget? buildSubDescription(BuildContext context) {
    if (onManageTags == null && onOpenFolder == null && onRead == null) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels = constraints.maxWidth >= 300;
          final actions = <Widget>[
            if (onRead != null)
              _buildActionItem(
                context,
                onTap: onRead!,
                icon: Icons.menu_book,
                title: "阅读".tl,
                isPrimary: true,
                showLabel: showLabels,
              ),
            if (onOpenFolder != null)
              _buildActionItem(
                context,
                onTap: onOpenFolder!,
                icon: Icons.folder_open,
                title: "目录".tl,
                showLabel: showLabels,
              ),
            if (onManageTags != null)
              _buildActionItem(
                context,
                onTap: onManageTags!,
                icon: Icons.label_outline,
                title: "标签".tl,
                showLabel: showLabels,
              ),
            _buildColorTagButton(context, showLabel: showLabels),
          ];
          return Row(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 6),
                actions[index],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    bool isPrimary = false,
    bool showLabel = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isPrimary
        ? colorScheme.primaryContainer
        : colorScheme.secondaryContainer;
    final foregroundColor = isPrimary
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;

    return Tooltip(
      message: title,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: showLabel ? 7 : 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: foregroundColor),
                  if (showLabel) ...[
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: foregroundColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorTagButton(BuildContext context, {required bool showLabel}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: "标记".tl,
      child: Material(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTapDown: (details) async {
            final overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox;
            final targetPosition = overlay.globalToLocal(
              details.globalPosition,
            );
            final position = RelativeRect.fromRect(
              Rect.fromPoints(targetPosition, targetPosition),
              Offset.zero & overlay.size,
            );
            final color = await showMenu<DownloadColorTag>(
              context: context,
              position: position,
              items: [
                for (var tag in DownloadColorTag.values)
                  PopupMenuItem(
                    value: tag,
                    child: Row(
                      children: [
                        if (tag.color != null)
                          Icon(Icons.circle, color: tag.color!, size: 18)
                        else
                          const Icon(Icons.circle_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(tag.label),
                      ],
                    ),
                  ),
              ],
            );
            if (color != null) {
              downloadManager.updateColor(downloadedItem.id, color);
            }
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 24),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: showLabel ? 7 : 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (downloadedItem.color?.color != null)
                    Icon(
                      Icons.circle,
                      size: 15,
                      color: downloadedItem.color!.color!,
                    )
                  else
                    Icon(
                      Icons.circle_outlined,
                      size: 15,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  if (showLabel) ...[
                    const SizedBox(width: 4),
                    Text(
                      "标记".tl,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void onTap_() => onTap();

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(TapDownDetails details) => onSecondaryTap(details);

  @override
  String get subTitle => "";

  @override
  String get title => name;

  @override
  String? get translatedTitle => translatedName;

  @override
  Widget get image => Image.file(
    imagePath,
    fit: BoxFit.cover,
    height: double.infinity,
    cacheWidth: (100 * MediaQuery.of(App.globalContext!).devicePixelRatio)
        .toInt(),
  );

  @override
  Widget? get badge => Text(type);

  @override
  Widget build(BuildContext context) {
    final baseTile = _buildTranslationResultMarkedTile(
      context,
      super.build(context),
    );

    // 如果禁用拖拽，直接返回基础 Tile，移除所有拖拽相关的包装控件
    if (isDragDisabled) {
      return baseTile;
    }

    // 单本漫画直接拖出下载目录；批量拖拽仍由独立对话框导出图片。
    return _DownloadedComicTileDragWrapper(
      downloadedItem: downloadedItem,
      child: baseTile,
    );
  }

  Widget _buildTranslationResultMarkedTile(BuildContext context, Widget child) {
    final result = translationResult;
    if (result == null) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        Positioned(
          top: 8,
          left: 8,
          child: IgnorePointer(
            ignoring: onTranslationResultTap == null,
            child: Tooltip(
              message: '发现 @num 张翻译结果，分布在 @dirs 个目录'.tlParams({
                'num': result.pairCount.toString(),
                'dirs': result.resultDirectoryCount.toString(),
              }),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTranslationResultTap,
                  borderRadius: BorderRadius.circular(7),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.94),
                      border: Border.all(
                        color: Colors.red.shade700,
                        width: 1.2,
                      ),
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 3),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        '翻译结果 @num'.tlParams({
                          'num': result.pairCount.toString(),
                        }),
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DownloadedComicTileDragWrapper extends StatelessWidget {
  final DownloadedItem downloadedItem;
  final Widget child;

  const _DownloadedComicTileDragWrapper({
    required this.downloadedItem,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        final directoryPath = downloadedItem.directoryPath;
        if (directoryPath.isEmpty) return null;

        final directory = Directory(directoryPath);
        if (!await directory.exists()) return null;

        final item = DragItem(suggestedName: path.basename(directory.path));
        item.add(Formats.fileUri(Uri.file(directory.path)));
        return item;
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.opaque,
        isLocationDraggable: (location) => true,
        child: child,
      ),
    );
  }
}

/// 导航到漫画详情页
void toComicInfoPage(DownloadedItem comic) {
  var context = App.mainNavigatorKey!.currentContext!;
  if (comic is DownloadedComic) {
    context.to(() => PicacgComicPage((comic).comicItem.id, null));
  } else if (comic is DownloadedGallery) {
    context.to(() => EhGalleryPage((comic).gallery.toBrief()));
  } else if (comic is DownloadedJmComic) {
    context.to(() => JmComicPage((comic).comic.id));
  } else if (comic is DownloadedHitomiComic) {
    context.to(() => HitomiComicPage(comic.toBrief()));
  } else if (comic is DownloadedHtComic) {
    context.to(() => HtComicPage(comic.id.replaceFirst('Ht', '')));
  } else if (comic is NhentaiDownloadedComic) {
    context.to(() => NhentaiComicPage(comic.id.replaceFirst("nhentai", "")));
  } else if (comic is CustomDownloadedItem) {
    context.to(
      () => ComicPage(
        comicType: ComicType.fromString(comic.sourceKey),
        id: comic.comicId,
      ),
    );
  } else if (comic.type == DownloadType.local) {
    // 本地漫画不支持查看详情页面，可以显示提示
    showToast(message: "本地漫画不支持查看详情".tl);
  }
}

/// 从正在下载的任务导航到漫画详情页
void toDownloadingComicInfoPage(DownloadingTask task) {
  var context = App.mainNavigatorKey!.currentContext!;
  switch (task.type) {
    case DownloadType.picacg:
      context.to(() => PicacgComicPage(task.id, null));
      break;
    case DownloadType.ehentai:
      // E-Hentai: 需要检查是否是 EhDownloadingTask 以获取完整 link
      if (task is EhDownloadingTask) {
        context.to(() => EhGalleryPage.fromLink(task.gallery.link));
      } else {
        // 如果不是 EhDownloadingTask，尝试构造完整链接
        final link = task.id.contains('/')
            ? task.id
            : 'https://e-hentai.org/g/$task.id/';
        context.to(() => EhGalleryPage.fromLink(link));
      }
      break;
    case DownloadType.jm:
      // JM: ID 格式为 "jm{id}"，需要去掉 "jm" 前缀
      final jmId = task.id.startsWith('jm') ? task.id.substring(2) : task.id;
      context.to(() => JmComicPage(jmId));
      break;
    case DownloadType.hitomi:
      // Hitomi: 需要检查是否是 HitomiDownloadingTask 以获取 link
      if (task is HitomiDownloadingTask) {
        context.to(() => HitomiComicPage.fromLink(task.link));
      } else {
        // 如果不是 HitomiDownloadingTask，尝试使用 ID 构造链接
        final hitomiId = task.id.startsWith('hitomi')
            ? task.id.substring(6)
            : task.id;
        context.to(() => HitomiComicPage.fromLink(hitomiId));
      }
      break;
    case DownloadType.htmanga:
      // HTManga: ID 格式为 "Ht{id}"，需要去掉 "Ht" 前缀
      final htId = task.id.startsWith('Ht') ? task.id.substring(2) : task.id;
      context.to(() => HtComicPage(htId));
      break;
    case DownloadType.nhentai:
      // Nhentai: ID 格式为 "nhentai{id}"，需要去掉前缀
      final nhentaiId = task.id.startsWith('nhentai')
          ? task.id.replaceFirst('nhentai', '')
          : task.id;
      context.to(() => NhentaiComicPage(nhentaiId));
      break;
    case DownloadType.other:
      // 自定义源：需要检查是否是 CustomDownloadingTask
      if (task is CustomDownloadingTask) {
        context.to(
          () => ComicPage(
            comicType: ComicType.fromString(task.comic.sourceKey),
            id: task.comic.comicId,
          ),
        );
      } else {
        showToast(message: "无法打开该漫画详情".tl);
      }
      break;
    case DownloadType.favorite:
      // 收藏夹下载不支持查看详情
      showToast(message: "收藏夹下载不支持查看详情".tl);
      break;
    case DownloadType.local:
      // 本地漫画不支持查看详情
      showToast(message: "本地漫画不支持查看详情".tl);
      break;
  }
}

/// 标签信息类
class TagInfo {
  final int id;
  final String name;
  String? coverPath;
  final int comicCount;
  final int category;
  final int sortOrder;
  final int categorySortOrder;

  TagInfo({
    required this.id,
    required this.name,
    this.coverPath,
    required this.comicCount,
    this.category = 0,
    this.sortOrder = 0,
    this.categorySortOrder = 0,
  });

  TagInfo copyWith({
    int? id,
    String? name,
    String? coverPath,
    int? comicCount,
    int? category,
    int? sortOrder,
    int? categorySortOrder,
  }) {
    return TagInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPath: coverPath ?? this.coverPath,
      comicCount: comicCount ?? this.comicCount,
      category: category ?? this.category,
      sortOrder: sortOrder ?? this.sortOrder,
      categorySortOrder: categorySortOrder ?? this.categorySortOrder,
    );
  }

  @override
  String toString() {
    return 'TagInfo{id: $id, name: $name, coverPath: $coverPath, comicCount: $comicCount, category: $category, sortOrder: $sortOrder, categorySortOrder: $categorySortOrder}';
  }

  factory TagInfo.fromMap(Map<String, dynamic> map) {
    return TagInfo(
      id: TypeUtil.parseInt(map['id']),
      name: TypeUtil.parseString(map['name']),
      coverPath: map['cover_path'] == null
          ? null
          : TypeUtil.parseString(map['cover_path']),
      comicCount: TypeUtil.parseInt(map['comic_count']),
      category: TypeUtil.parseInt(map['category']),
      sortOrder: TypeUtil.parseInt(map['sort_order']),
      categorySortOrder: TypeUtil.parseInt(map['category_sort_order']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_path': coverPath,
      'comic_count': comicCount,
      'category': category,
      'sort_order': sortOrder,
      'category_sort_order': categorySortOrder,
    };
  }
}

/// 获取漫画类型显示名称
String getComicTypeName(DownloadedItem item) {
  var type = item.type.name;
  if (item.type == DownloadType.other) {
    type = (item as CustomDownloadedItem).sourceName;
  } else if (item.type == DownloadType.local) {
    type = "本地".tl;
  }
  return type;
}

/// 获取漫画显示名称
String getComicDisplayName(DownloadedItem comic) {
  String name = comic.name;
  String maxPage = '';
  if (comic.type == DownloadType.ehentai) {
    maxPage = (comic as DownloadedGallery).gallery.maxPage;
  }
  if (maxPage.isNotEmpty && maxPage != '0') {
    name = '(${maxPage}P)[${comic.id}]${comic.name}';
  }
  return name;
}

/// 获取漫画大小显示文本
String getComicSizeText(DownloadedItem comic) {
  if (comic.comicSize != null) {
    return comic.comicSize!.toStringAsFixed(2);
  } else {
    return "未知大小".tl;
  }
}

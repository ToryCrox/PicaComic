import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart'; // ignore: unused_import
import 'package:flutter/rendering.dart'; // ignore: unused_import

import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:path/path.dart' as Path;
import 'package:super_native_extensions/raw_drag_drop.dart' as raw;
import 'package:super_native_extensions/widget_snapshot.dart';

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
  });

  @override
  List<String>? get tags => tag
      .map((e) => App.locale.languageCode == "zh" ? e.translateTagsToCN : e)
      .toList();

  @override
  String get description => "${size}MB";

  @override
  String? get comicID {
    if (downloadedItem is DownloadedGallery) {
      return (downloadedItem as DownloadedGallery).gallery.link;
    }
    return downloadManager.getComicIdFromDownloadId(
        downloadedItem.type.toComicType(), downloadedItem.id);
  }

  @override
  ComicType? get comicType => downloadedItem.type.toComicType();

  @override
  Widget? buildSubDescription(BuildContext context) {
    if (onManageTags == null && onOpenFolder == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Row(
        children: [
          if (onRead != null)
            _buildActionItem(
              context,
              onTap: onRead!,
              icon: Icons.menu_book,
              title: "阅读".tl,
              isPrimary: true,
            ),
          if (onRead != null && (onOpenFolder != null || onManageTags != null))
            const SizedBox(width: 8),
          if (onOpenFolder != null)
            _buildActionItem(
              context,
              onTap: onOpenFolder!,
              icon: Icons.folder_open,
              title: "目录".tl,
            ),
          if (onOpenFolder != null && onManageTags != null)
            const SizedBox(width: 8),
          if (onManageTags != null)
            _buildActionItem(
              context,
              onTap: onManageTags!,
              icon: Icons.label_outline,
              title: "标签".tl,
            ),
          const SizedBox(width: 8),
          _buildColorTagButton(context),
        ],
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    bool isPrimary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor =
        isPrimary ? colorScheme.primaryContainer : colorScheme.secondaryContainer;
    final foregroundColor = isPrimary
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorTagButton(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTapDown: (details) async {
          final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final targetPosition = overlay.globalToLocal(details.globalPosition);
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (downloadedItem.color?.color != null)
                Icon(
                  Icons.circle,
                  size: 16,
                  color: downloadedItem.color!.color!,
                )
              else
                Icon(
                  Icons.circle_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              const SizedBox(width: 6),
              Text(
                "标记".tl,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
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
  String get subTitle => author;

  @override
  String get title => name;

  @override
  Widget get image => Image.file(
        imagePath,
        fit: BoxFit.cover,
        height: double.infinity,
        cacheWidth:
            (100 * MediaQuery.of(App.globalContext!).devicePixelRatio).toInt(),
      );

  @override
  Widget? get badge => Text(type);

  @override
  Widget build(BuildContext context) {
    final baseTile = super.build(context);

    // 如果禁用拖拽，直接返回基础 Tile，移除所有拖拽相关的包装控件
    if (isDragDisabled) {
      return baseTile;
    }

    // 将拖拽逻辑封装在 StatefulWidget 中以缓存文件列表
    return _DownloadedComicTileDragWrapper(
      downloadedItem: downloadedItem,
      isDragDisabled: isDragDisabled,
      child: baseTile,
    );
  }
}

class _DownloadedComicTileDragWrapper extends StatefulWidget {
  final DownloadedItem downloadedItem;
  final bool isDragDisabled;
  final Widget child;

  const _DownloadedComicTileDragWrapper({
    required this.downloadedItem,
    required this.isDragDisabled,
    required this.child,
  });

  @override
  State<_DownloadedComicTileDragWrapper> createState() =>
      _DownloadedComicTileDragWrapperState();
}

class _DownloadedComicTileDragWrapperState
    extends State<_DownloadedComicTileDragWrapper> {
  List<File>? _cachedFiles;
  bool _isScanning = false;

  /// 获取所有图片文件（带简单缓存）
  Future<List<File>> _getImageFiles() async {
    if (_cachedFiles != null) return _cachedFiles!;
    if (_isScanning) {
      // 避免并发扫描，等待当前扫描完成
      while (_isScanning) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _cachedFiles ?? [];
    }

    _isScanning = true;
    try {
      final dirPath = widget.downloadedItem.directoryPath;
      if (dirPath.isEmpty) {
        _cachedFiles = [];
        return [];
      }

      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        _cachedFiles = [];
        return [];
      }

      final imageFiles = <File>[];

      // 递归遍历目录获取所有图片文件
      await for (var entity in dir.list(recursive: true)) {
        if (entity is! File) continue;

        final fileName = Path.basename(entity.path);

        // 排除封面文件
        if (fileName == 'cover.jpg' ||
            fileName == 'cover.webp' ||
            fileName == 'cover.png') {
          continue;
        }

        // 检查是否为图片文件
        final ext = Path.extension(fileName).toLowerCase();
        if (ext == '.jpg' ||
            ext == '.jpeg' ||
            ext == '.png' ||
            ext == '.gif' ||
            ext == '.webp' ||
            ext == '.bmp') {
          imageFiles.add(entity);
        }
      }

      // 按照文件名排序，确保顺序正确（可选，但对连贯性有帮助）
      imageFiles.sort((a, b) => a.path.compareTo(b.path));

      _cachedFiles = imageFiles;
      return imageFiles;
    } catch (e) {
      print('Error getting image files: $e');
      _cachedFiles = [];
      return [];
    } finally {
      _isScanning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragItemProvider: (request) async {
        // 尝试获取文件列表（会触发缓存）
        final imageFiles = await _getImageFiles();
        if (imageFiles.isEmpty) return null;

        // 返回第一个文件作为基础
        final item = DragItem(suggestedName: Path.basename(imageFiles[0].path));
        item.add(Formats.fileUri(Uri.file(imageFiles[0].path)));
        return item;
      },
      child: DraggableWidget(
        hitTestBehavior: HitTestBehavior.opaque,
        isLocationDraggable: (location) {
          // 在包装器存在时（即非禁用状态），始终允许拖拽
          return true;
        },
        onDragConfiguration: (configuration, session) async {
          final imageFiles = await _getImageFiles();
          if (imageFiles.length <= 1) return configuration;

          final items = <DragConfigurationItem>[];

          // 使用引用计数包装镜像，防止多个项共享同一个对象时重复释放导致崩溃
          final refCountingImage = _RefCountingSnapshot(
            configuration.items[0].image.snapshot,
            configuration.items[0].image.rect,
            imageFiles.length,
          );

          // 为所有图片添加拖拽项
          for (int i = 0; i < imageFiles.length; i++) {
            final file = imageFiles[i];
            final item = DragItem(suggestedName: Path.basename(file.path));
            item.add(Formats.fileUri(Uri.file(file.path)));
            items.add(DragConfigurationItem(
              item: item,
              image: refCountingImage,
            ));
          }

          return DragConfiguration(
            items: items,
            allowedOperations: configuration.allowedOperations,
          );
        },
        child: widget.child,
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
    context.to(() => ComicPage(comicType: ComicType.fromString(comic.type.name), id: comic.comicId));
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
        final link = task.id.contains('/') ? task.id : 'https://e-hentai.org/g/$task.id/';
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
        final hitomiId = task.id.startsWith('hitomi') ? task.id.substring(6) : task.id;
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
      final nhentaiId = task.id.startsWith('nhentai') ? task.id.replaceFirst('nhentai', '') : task.id;
      context.to(() => NhentaiComicPage(nhentaiId));
      break;
    case DownloadType.other:
      // 自定义源：需要检查是否是 CustomDownloadingTask
      if (task is CustomDownloadingTask) {
        context.to(() => ComicPage(comicType: ComicType.fromString(task.comic.sourceKey), id: task.comic.comicId));
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

/// 引用计数镜像包装器，用于解决批量拖拽时共享镜像导致的重复释放问题
class _RefCountingSnapshot extends raw.TargetedWidgetSnapshot {
  int _count;
  _RefCountingSnapshot(WidgetSnapshot snapshot, Rect rect, this._count)
      : super(snapshot, rect);

  @override
  void dispose() {
    _count--;
    if (_count <= 0) {
      super.dispose();
    }
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

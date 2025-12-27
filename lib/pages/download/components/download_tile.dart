import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final void Function(String tag)? onTagTap;
  final void Function(String tag)? onPrimaryTagTap;
  @override
  final void Function(String tag, TapDownDetails details)? onTagSecondaryTap;
  @override
  final void Function(String tag, TapDownDetails details)?
      onPrimaryTagSecondaryTap;

  final VoidCallback? onManageTags;
  final VoidCallback? onOpenFolder;

  List<String>? get tags => tag
      .map((e) => App.locale.languageCode == "zh" ? e.translateTagsToCN : e)
      .toList();

  @override
  String get description => "${size}MB";

  @override
  Widget? buildSubDescription(BuildContext context) {
    if (onManageTags == null && onOpenFolder == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Row(
        children: [
          if (onOpenFolder != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onOpenFolder,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        "目录".tl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (onOpenFolder != null && onManageTags != null)
            const SizedBox(width: 12),
          if (onManageTags != null)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onManageTags,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label_outline,
                          size: 18,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        "标签".tl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget get image => Image.file(
        imagePath,
        fit: BoxFit.cover,
        height: double.infinity,
        cacheWidth:
            (100 * MediaQuery.of(App.globalContext!).devicePixelRatio).toInt(),
      );

  @override
  void onTap_() => onTap();

  @override
  String get subTitle => author;

  @override
  String get title => name;

  @override
  void onLongTap_() => onLongTap();

  @override
  void onSecondaryTap_(details) => onSecondaryTap(details);

  @override
  Widget? get badge => Text(type);

  const DownloadedComicTile({
    required this.id,
    required this.size,
    required this.imagePath,
    required this.author,
    required this.name,
    required this.onTap,
    required this.onLongTap,
    required this.onSecondaryTap,
    required this.type,
    required this.tag,
    this.primaryTags = const [],
    this.onTagTap,
    this.onPrimaryTagTap,
    this.onTagSecondaryTap,
    this.onPrimaryTagSecondaryTap,
    this.onManageTags,
    this.onOpenFolder,
    super.key,
  });
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
    context.to(() => ComicPage(sourceKey: comic.sourceKey, id: comic.comicId));
  } else if (comic.type == DownloadType.local) {
    // 本地漫画不支持查看详情页面，可以显示提示
    showToast(message: "本地漫画不支持查看详情".tl);
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

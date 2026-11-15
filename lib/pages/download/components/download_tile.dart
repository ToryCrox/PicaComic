import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/download/custom_download_model.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloaded_item.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloading_task.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_download_model.dart';
import 'package:pica_comic/network/htmanga_network/ht_download_model.dart';
import 'package:pica_comic/network/jm_network/jm_download.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloaded_item.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloading_task.dart';
import 'package:pica_comic/network/nhentai_network/download.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/ehentai/eh_gallery_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_comic_page.dart';
import 'package:pica_comic/pages/htmanga/ht_comic_page.dart';
import 'package:pica_comic/pages/jm/jm_comic_page.dart';
import 'package:pica_comic/pages/nhentai/comic_page.dart';
import 'package:pica_comic/pages/picacg/comic_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/type_util.dart';

/// 导航到漫画详情页
void toComicInfoPage(DownloadedItem comic) {
  final context = App.mainNavigatorKey!.currentContext!;
  final coverPath = comic.coverPath;
  final cover = coverPath == null ? null : Uri.file(coverPath).toString();

  void open(ComicType type, String id) {
    context.to(() => ComicPage(comicType: type, id: id, cover: cover));
  }

  if (comic is DownloadedComic) {
    open(ComicType.picacg, comic.comicItem.id);
  } else if (comic is DownloadedGallery) {
    open(ComicType.ehentai, comic.gallery.link);
  } else if (comic is DownloadedJmComic) {
    open(ComicType.jm, comic.comic.id);
  } else if (comic is DownloadedHitomiComic) {
    open(ComicType.hitomi, comic.link);
  } else if (comic is DownloadedHtComic) {
    open(ComicType.htmanga, comic.id.replaceFirst('Ht', ''));
  } else if (comic is NhentaiDownloadedComic) {
    open(ComicType.nhentai, comic.id.replaceFirst('nhentai', ''));
  } else if (comic is ManhuaguiDownloadedItem) {
    open(ComicType.manhuagui, comic.comicId);
  } else if (comic is HiperdexDownloadedItem) {
    open(ComicType.hiperdex, comic.comicId);
  } else if (comic is CustomDownloadedItem) {
    open(ComicType.fromString(comic.sourceKey), comic.comicId);
  } else if (comic.type == DownloadType.local) {
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
    case DownloadType.manhuagui:
      if (task is ManhuaguiDownloadingTask) {
        context.to(
          () =>
              ComicPage(comicType: ComicType.manhuagui, id: task.comic.comicId),
        );
      }
      break;
    case DownloadType.hiperdex:
      if (task is HiperdexDownloadingTask) {
        context.to(
          () =>
              ComicPage(comicType: ComicType.hiperdex, id: task.comic.comicId),
        );
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
  } else if (item.type == DownloadType.manhuagui) {
    type = '漫画柜'.tl;
  } else if (item.type == DownloadType.hiperdex) {
    type = 'HiperDEX';
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

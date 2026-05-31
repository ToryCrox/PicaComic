import 'package:flutter/material.dart';

typedef ActionFunc = void Function();

enum ComicType {
  /// 哔咔
  picacg,

  /// E-Hentai
  ehentai,

  /// 禁漫天堂
  jm,

  /// Hitomi
  hitomi,

  /// 绅士漫画
  htmanga,

  /// 绅士漫画收藏
  htFavorite,

  /// nhentai
  nhentai,

  /// Kemono
  kemono,

  /// 本地漫画
  local,

  /// 其他
  other;

  @override
  toString() => name;

  static ComicType fromString(String? name) {
    for (var value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return ComicType.other;
  }
}

/// 生成漫画详情页内部使用的稳定标签。
String comicPageTag(ComicType comicType, String id) {
  return switch (comicType) {
    ComicType.picacg => "Picacg Comic Page $id",
    ComicType.ehentai => "Eh ComicPage $id",
    ComicType.jm => "${comicType.name} comic page $id",
    ComicType.hitomi => "Hitomi $id",
    ComicType.htmanga => "HtManga $id",
    ComicType.nhentai => "Nhentai $id",
    ComicType.kemono => "Kemono $id",
    _ => "${comicType.name} comic page with id: $id",
  };
}

/// 生成漫画封面在列表页和详情页之间共享的 Hero 标签。
String comicCoverHeroTag(ComicType comicType, String id) {
  return "image${comicPageTag(comicType, id)}";
}

const String webUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36";

//App版本
const appVersion = "4.2.11";

//定义宽屏设备的临界值
const changePoint = 600;
const changePoint2 = 1300;

List<MaterialAccentColor> get colors => [
  Colors.redAccent,
  Colors.pinkAccent,
  Colors.purpleAccent,
  Colors.indigoAccent,
  Colors.blueAccent,
  Colors.cyanAccent,
  Colors.tealAccent,
  Colors.greenAccent,
  Colors.limeAccent,
  Colors.yellowAccent,
  Colors.amberAccent,
  Colors.orangeAccent,
];

const builtInSources = [
  ComicType.picacg,
  ComicType.ehentai,
  ComicType.jm,
  ComicType.hitomi,
  ComicType.htmanga,
  ComicType.nhentai,
  ComicType.kemono,
];

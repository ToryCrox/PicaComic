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

const String webUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36";

//App版本
const appVersion = "4.2.9";

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
  ComicType.kemono
];

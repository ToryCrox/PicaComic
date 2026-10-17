import 'image_favorites.dart';

/// 收藏的章节展示信息，兼容旧阅读元数据。
extension ImageFavoriteChapter on ImageFavorite {
  /// 优先使用新增标记，否则根据来源及旧章节目录判断。
  bool get hasChapters {
    final flag = otherInfo['hasEp'];
    if (flag is bool) return flag;
    if (const [
      'ehentai',
      'hitomi',
      'htmanga',
      'htManga',
      'nhentai',
    ].contains(sourceKey)) {
      return false;
    }
    if (const ['picacg', 'jm'].contains(sourceKey)) return true;
    final eps = otherInfo['eps'];
    return (eps is Map && eps.isNotEmpty) ||
        (eps is List && eps.isNotEmpty) ||
        ep > 1;
  }

  /// 当前章节名；旧列表中只有哔咔的 eps 表示名称。
  String? get chapterName {
    final explicit = _name(otherInfo['chapterName']);
    if (explicit != null) return explicit;
    if (ep < 1) return null;
    final names = otherInfo['jmEpNames'];
    if (names is List && ep <= names.length) {
      final name = _name(names[ep - 1]);
      if (name != null) return name;
    }
    final eps = otherInfo['eps'];
    if (eps is Map && ep <= eps.length) {
      return _name(eps.values.elementAt(ep - 1));
    }
    if (sourceKey == 'picacg' && eps is List && ep <= eps.length) {
      return _name(eps[ep - 1]);
    }
    return null;
  }

  /// 章节索引相对于正常阅读顺序的方向。
  int get chapterStep {
    final explicit = otherInfo['chapterStep'];
    if (explicit is int && (explicit == 1 || explicit == -1)) return explicit;
    if (sourceKey != 'hiperdex') return 1;
    final eps = otherInfo['eps'];
    double? previous;
    for (final key in eps is Map ? eps.keys : const []) {
      final number = double.tryParse(key.toString().split('|').first);
      if (number == null) continue;
      if (previous != null && number != previous) {
        return number < previous ? -1 : 1;
      }
      previous = number;
    }
    return -1;
  }

  /// 只接受非空名称，忽略损坏的元数据。
  static String? _name(dynamic value) {
    if (value is! String) return null;
    final name = value.replaceAll('\n', ' ').trim();
    return name.isEmpty ? null : name;
  }
}

/// 按最近收藏作品、作品内章节及页码生成新的显示列表。
List<ImageFavorite> sortImageFavorites(
  List<ImageFavorite> images, {
  bool reversed = false,
}) {
  final groups = <(String, String), List<(int, ImageFavorite)>>{};
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    (groups[(image.sourceKey, image.comicId)] ??= []).add((index, image));
  }
  final ordered = groups.values.toList()
    ..sort((a, b) => b.last.$1.compareTo(a.last.$1));
  final result = <ImageFavorite>[];
  for (final group in ordered) {
    final step = group.last.$2.chapterStep;
    group.sort((a, b) {
      final chapter = (a.$2.ep * step).compareTo(b.$2.ep * step);
      if (chapter != 0) return chapter;
      final page = a.$2.page.compareTo(b.$2.page);
      return page == 0 ? a.$1.compareTo(b.$1) : page;
    });
    result.addAll(group.map((entry) => entry.$2));
  }
  return reversed ? result.reversed.toList() : result;
}

/// 每个作品取最近收藏记录作为分组入口，保持最近收藏顺序。
List<ImageFavorite> groupImageFavorites(List<ImageFavorite> images) {
  final seen = <(String, String)>{};
  return images.reversed
      .where((image) => seen.add((image.sourceKey, image.comicId)))
      .toList();
}

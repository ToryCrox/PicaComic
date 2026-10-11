import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';

/// HiperDEX 下载记录，按稳定章节 ID 保存真实章号目录和下载状态。
class HiperdexDownloadedItem extends DownloadedItem {
  final Map<String, String> chapterDirectories;

  /// 将独立下载记录转换为本地收藏项。
  FavoriteItem toFavoriteItem() => FavoriteItem(
    target: comicId,
    name: name,
    coverPath: cover,
    author: subTitle,
    type: FavoriteType(ComicType.hiperdex.index),
    tags: tags,
  );

  /// 根据一基章节索引获取磁盘目录，兼容旧的数字目录。
  @override
  String getEpisodeDirectoryName(int episodeIndex) {
    final key = chapters?.keys.elementAtOrNull(episodeIndex - 1);
    final name = chapterDirectories[key];
    if (name == null ||
        name == '.' ||
        name == '..' ||
        path.isAbsolute(name) ||
        name.contains('/') ||
        name.contains('\\')) {
      return '$episodeIndex';
    }
    return name;
  }

  /// 详情更新时按章节 ID 重新映射已下载索引，避免新增章节造成错章。
  HiperdexDownloadedItem withComicInfo(ComicInfoData updated) {
    final oldChapters = chapters ?? <String, String>{};
    final mergedChapters = <String, String>{...?updated.chapters};
    final downloadedKeys = downloadedEps
        .map((index) => oldChapters.keys.elementAtOrNull(index))
        .whereType<String>()
        .toSet();
    for (final key in downloadedKeys) {
      mergedChapters.putIfAbsent(key, () => oldChapters[key]!);
    }
    final keys = mergedChapters.keys.toList();
    final result = HiperdexDownloadedItem(
      comicSize,
      [
        for (var i = 0; i < keys.length; i++)
          if (downloadedKeys.contains(keys[i])) i,
      ],
      id,
      updated.copyWith(chapters: mergedChapters),
      sourceName,
      color: color,
      chapterDirectories: chapterDirectories,
    );
    result.directory = directory;
    result.time = time;
    result.aiTranslationCompletedAt = aiTranslationCompletedAt;
    return result;
  }

  /// 将旧索引目录改为真实章号；目标已有文件时保留旧目录，避免覆盖。
  Future<bool> migrateChapterDirectories(String comicRoot) async {
    if (comicRoot.isEmpty) return false;
    final root = path.normalize(path.absolute(comicRoot));
    var changed = false;
    for (final index in downloadedEps) {
      final key = chapters?.keys.elementAtOrNull(index);
      if (key == null) continue;
      final oldName = chapterDirectories[key] ?? '${index + 1}';
      final newName = hiperdexChapterDirectoryName(chapters!, key);
      if (oldName == newName) continue;
      final oldPath = path.normalize(path.join(root, oldName));
      final newPath = path.normalize(path.join(root, newName));
      if (path.dirname(oldPath) != root || path.dirname(newPath) != root) {
        continue;
      }
      try {
        final oldDirectory = Directory(oldPath);
        final newDirectory = Directory(newPath);
        if (await oldDirectory.exists()) {
          if (await FileSystemEntity.type(newPath) !=
              FileSystemEntityType.notFound) {
            Log.w('HiperDEX 章节目录已存在，保留旧目录：$oldPath');
            continue;
          }
          await oldDirectory.rename(newPath);
        } else if (!await newDirectory.exists()) {
          continue;
        }
        chapterDirectories[key] = newName;
        changed = true;
      } catch (error, stackTrace) {
        Log.w(
          'HiperDEX 章节目录迁移失败：$oldPath',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return changed;
  }

  @override
  double? comicSize;

  @override
  final List<int> downloadedEps;

  final ComicInfoData comic;

  final String sourceName;

  Map<String, String>? get chapters => comic.chapters;

  @override
  List<String> get eps => chapters?.values.toList() ?? ["EP 1"];

  String get comicId => comic.comicId;

  @override
  final String id;

  @override
  String get name => comic.title;

  @override
  String get subTitle => comic.subTitle ?? '';

  @override
  List<String> get tags => comic.tags.values.expand((e) => e).toList();

  @override
  DownloadType get type => DownloadType.hiperdex;

  @override
  String get sourceKey => ComicType.hiperdex.name;

  String get cover => comic.cover;

  HiperdexDownloadedItem(
    this.comicSize,
    this.downloadedEps,
    this.id,
    this.comic,
    this.sourceName, {
    DownloadColorTag? color,
    Map<String, String>? chapterDirectories,
  }) : chapterDirectories = Map.of(chapterDirectories ?? {}) {
    this.color = color;
  }

  @override
  Map<String, dynamic> toJson() => {
    "modelVersion": 1,
    "comicSize": comicSize,
    "downloadedEps": downloadedEps,
    "id": id,
    "comic": comic.toJson(),
    "sourceName": sourceName,
    "color": color?.name,
    "chapterDirectories": chapterDirectories,
  };

  HiperdexDownloadedItem.fromJson(Map<String, dynamic> json)
    : comicSize = json["comicSize"],
      downloadedEps = List<int>.from(json["downloadedEps"]),
      id = json["id"],
      comic = json["comic"] != null
          ? ComicInfoData.fromJson(Map<String, dynamic>.from(json["comic"]))
          : ComicInfoData(
              title: json["name"] ?? '',
              subTitle: json["subTitle"],
              cover: json["cover"] ?? '',
              description: json["description"],
              tags: {"Tags": List<String>.from(json["tags"] ?? [])},
              chapters: json["chapters"] == null
                  ? null
                  : Map<String, String>.from(json["chapters"]),
              sourceKey: json["sourceKey"] ?? '',
              comicId: json["comicId"] ?? '',
            ),
      sourceName = json["sourceName"],
      chapterDirectories = Map<String, String>.from(
        json['chapterDirectories'] ?? {},
      ) {
    // 保存旧快照的索引目录，后续详情重排时仍能找到正确的本地章节。
    color = DownloadColorTag.fromString(json["color"]);
    for (final index in downloadedEps) {
      final key = chapters?.keys.elementAtOrNull(index);
      if (key != null) {
        chapterDirectories.putIfAbsent(key, () => '${index + 1}');
      }
    }
  }
}

/// 生成真实章号目录；同章号不同版本使用站点章节 ID 区分。
String hiperdexChapterDirectoryName(Map<String, String> chapters, String key) {
  final parts = key.split('|');
  final number = num.tryParse(parts.first);
  if (number == null || number < 0 || !number.isFinite) {
    throw FormatException('HiperDEX 章节号无效：$key');
  }
  final label = number == number.toInt() ? '${number.toInt()}' : '$number';
  final duplicate =
      chapters.keys
          .where((other) => num.tryParse(other.split('|').first) == number)
          .length >
      1;
  if (duplicate && parts.length > 1 && int.tryParse(parts[1]) != null) {
    return 'Chapter $label - ${parts[1]}';
  }
  return 'Chapter $label';
}

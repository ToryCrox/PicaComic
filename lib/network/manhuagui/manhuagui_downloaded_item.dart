import 'package:path/path.dart' as path;
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/download/models/download_color_tag.dart';

/// 漫画柜下载记录，按稳定章节 ID 保存目录和下载状态。
class ManhuaguiDownloadedItem extends DownloadedItem {
  final Map<String, String> chapterDirectories;

  /// 将独立下载记录转换为本地收藏项。
  FavoriteItem toFavoriteItem() => FavoriteItem(
    target: comicId,
    name: name,
    coverPath: cover,
    author: subTitle,
    type: FavoriteType(ComicType.manhuagui.index),
    tags: tags,
  );

  /// 根据一基章节索引取得稳定的磁盘目录。
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
      return key == null
          ? '$episodeIndex'
          : manhuaguiChapterDirectoryName(chapters!, key);
    }
    return name;
  }

  /// 详情更新时按章节 ID 重新映射已下载索引，避免新增章节造成错章。
  ManhuaguiDownloadedItem withComicInfo(ComicInfoData updated) {
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
    final result = ManhuaguiDownloadedItem(
      comicSize,
      [
        for (var i = 0; i < keys.length; i++)
          if (downloadedKeys.contains(keys[i])) i,
      ],
      id,
      updated.copyWith(
        chapters: mergedChapters,
        chapterGroups: [
          ...updated.chapterGroups,
          for (final group in comic.chapterGroups)
            if (group.chapterIds.any(
              (key) =>
                  downloadedKeys.contains(key) &&
                  !updated.chapters!.containsKey(key),
            ))
              group.copyWith(
                id: 'local-${group.id.replaceFirst(RegExp(r"^local-"), "")}',
                title: group.title.endsWith('（本地保留）')
                    ? group.title
                    : '${group.title}（本地保留）',
                chapterIds: group.chapterIds
                    .where(
                      (key) =>
                          downloadedKeys.contains(key) &&
                          !updated.chapters!.containsKey(key),
                    )
                    .toList(),
              ),
        ],
      ),
      sourceName,
      color: color,
      chapterDirectories: chapterDirectories,
    );
    result.directory = directory;
    result.time = time;
    result.aiTranslationCompletedAt = aiTranslationCompletedAt;
    return result;
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
  DownloadType get type => DownloadType.manhuagui;

  @override
  String get sourceKey => ComicType.manhuagui.name;

  String get cover => comic.cover;

  ManhuaguiDownloadedItem(
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

  ManhuaguiDownloadedItem.fromJson(Map<String, dynamic> json)
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
    // 补全按章节 ID 命名的目录，避免恢复快照时依赖当前目录顺序。
    color = DownloadColorTag.fromString(json["color"]);
    for (final index in downloadedEps) {
      final key = chapters?.keys.elementAtOrNull(index);
      if (key != null) {
        chapterDirectories.putIfAbsent(
          key,
          () => manhuaguiChapterDirectoryName(chapters!, key),
        );
      }
    }
  }
}

/// 按站点章节 ID 生成稳定目录，避免组名及章名变化导致错章。
String manhuaguiChapterDirectoryName(Map<String, String> chapters, String key) {
  if (!RegExp(r'^\d+$').hasMatch(key)) {
    throw FormatException('漫画柜章节 ID 无效：$key');
  }
  return 'chapter-$key';
}

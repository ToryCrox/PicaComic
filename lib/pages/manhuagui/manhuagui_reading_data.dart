import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloaded_item.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';

/// 漫画柜阅读会话：组内切章、稳定章节历史及离线目录映射。
class ManhuaguiReadingData extends ReadingData {
  ManhuaguiReadingData(this.comic);

  final ComicInfoData comic;
  final _localChapters = <String, int>{};

  @override
  String get id => comic.comicId;
  @override
  String get title => comic.title;
  @override
  String get downloadId => 'manhuagui-$id';
  @override
  ComicType get type => ComicType.manhuagui;
  @override
  Map<String, String>? get eps => comic.chapters;
  @override
  bool get hasEp => eps?.isNotEmpty ?? false;
  @override
  List<ComicChapterGroup> get chapterGroups => comic.chapterGroups;
  @override
  bool get cacheChapterLinks => false;
  @override
  FavoriteType get favoriteType => FavoriteType(ComicType.manhuagui.index);

  /// 到达当前分组首尾时停止，其他组只允许用户手动切换。
  @override
  int? adjacentEpisode(int episode, int direction) {
    if (episode < 1) return null;
    final key = eps?.keys.elementAtOrNull(episode - 1);
    if (key == null) return null;
    for (final group in chapterGroups) {
      final index = group.chapterIds.indexOf(key);
      if (index < 0) continue;
      final next = index + direction;
      if (next < 0) return null;
      final target = group.chapterIds.elementAtOrNull(next);
      if (target == null) return null;
      final mapped = eps!.keys.toList().indexOf(target);
      return mapped < 0 ? null : mapped + 1;
    }
    return super.adjacentEpisode(episode, direction);
  }

  @override
  void markEpisodeRead(int episode) {
    super.markEpisodeRead(episode);
    final key = eps?.keys.elementAtOrNull(episode - 1);
    if (key != null) history?.readChapterIds.add(key);
  }

  @override
  void saveChapterPosition(int episode, int page) {
    final current = history;
    if (current == null) return;
    current.chapterId = eps?.keys.elementAtOrNull(episode - 1);
    current.ep = episode;
    current.page = page;
    markEpisodeRead(episode);
  }

  @override
  void onDownloadedItemLoaded(DownloadedItem item) {
    if (item is! ManhuaguiDownloadedItem) return;
    _localChapters.clear();
    final keys = item.chapters?.keys.toList() ?? <String>[];
    for (var i = 0; i < keys.length; i++) {
      _localChapters[keys[i]] = i + 1;
    }
  }

  @override
  int localEpisode(int ep) =>
      _localChapters[eps?.keys.elementAtOrNull(ep - 1)] ?? -1;

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) {
    final key = eps?.keys.elementAtOrNull(ep - 1);
    if (key == null) return Future.value(const Res.error('找不到该章节'));
    return sourceServices.manhuagui.pages(id, key);
  }

  /// 签名过期后仅刷新当前章，再重试对应图片。
  @override
  Stream<DownloadProgress> loadImageNetwork(
    int ep,
    int page,
    String url,
  ) async* {
    try {
      yield* ImageManager(
        downloadManager,
      ).getImage(url, ManhuaguiNetwork.imageHeaders);
    } catch (_) {
      final refreshed = await loadEpNetwork(ep);
      final target = refreshed.dataOrNull?.elementAtOrNull(page);
      if (target == null) rethrow;
      yield* ImageManager(
        downloadManager,
      ).getImage(target, ManhuaguiNetwork.imageHeaders);
    }
  }

  @override
  String buildImageKey(int ep, int page, String url) =>
      '$sourceKey-$id-${eps?.keys.elementAtOrNull(ep - 1)}-$page';
}

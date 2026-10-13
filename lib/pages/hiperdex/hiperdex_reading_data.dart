import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_downloaded_item.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';

/// HiperDEX 阅读数据，按章节 ID 在在线目录与下载快照之间定位。
class HiperdexReadingData extends ReadingData {
  HiperdexReadingData(this.id, this.title, this.eps);

  @override
  final String id;

  @override
  final String title;

  @override
  final Map<String, String>? eps;

  /// HiperDEX 通常以新章在前排列，同时兼容已有的正序下载快照。
  @override
  int get chapterStep {
    double? previous;
    for (final key in eps?.keys ?? const <String>[]) {
      final number = double.tryParse(key.split('|').first);
      if (number == null) continue;
      if (previous != null && number != previous) {
        return number < previous ? -1 : 1;
      }
      previous = number;
    }
    return -1;
  }

  final Map<String, int> _localChapters = {};

  @override
  String get downloadId => 'hiperdex-$id';

  @override
  ComicType get type => ComicType.hiperdex;

  @override
  bool get hasEp => eps != null;

  @override
  FavoriteType get favoriteType => FavoriteType(ComicType.hiperdex.index);

  @override
  void onDownloadedItemLoaded(DownloadedItem item) {
    if (item is! HiperdexDownloadedItem) return;
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
    return sourceServices.hiperdex.getChapterPages(id, key);
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) =>
      ImageManager(downloadManager).getImage(url, HiperdexNetwork.imageHeaders);

  @override
  String buildImageKey(int ep, int page, String url) =>
      '$sourceKey-$id-${eps?.keys.elementAtOrNull(ep - 1)}-$url';
}

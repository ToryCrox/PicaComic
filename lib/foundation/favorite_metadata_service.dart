import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/res.dart';

import 'local_favorites.dart';

/// 收藏元数据加载服务，由 Provider 注入网络依赖。
class FavoriteMetadataService {
  FavoriteMetadataService(this._services, this._loadCustom);

  final ComicSourceServices _services;
  final Future<Res<ComicInfoData>> Function(ComicInfoQuery query) _loadCustom;

  /// 保留各漫画源已有的数据转换和错误语义。
  Future<Res<FavoriteItem>> load(FavoriteItem item) async {
    final type = item.type;
    final target = item.target;
    FavoriteItem updated = item;
    if (type == FavoriteType.picacg) {
      var res = await _services.picacg.getComicInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(
        name: res.data.title,
        author: res.data.author,
        tags: res.data.tags,
        coverPath: res.data.cover,
      );
    } else if (type == FavoriteType.ehentai) {
      var res = await _services.ehentai.getGalleryInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(name: res.data.title, coverPath: res.data.cover);
    } else if (type == FavoriteType.jm) {
      var res = await _services.jm.getComicInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(
        name: res.data.title,
        author: res.data.author.firstOrNull ?? '',
        tags: res.data.tags,
        coverPath: res.data.cover,
      );
    } else if (type == FavoriteType.nhentai) {
      var res = await _services.nhentai.getComicInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(name: res.data.title, coverPath: res.data.cover);
    } else if (type == FavoriteType.htmanga) {
      var res = await _services.htmanga.getComicInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(
        name: res.data.title,
        author: res.data.uploader,
        coverPath: res.data.cover,
      );
    } else if (type == FavoriteType.hitomi) {
      var res = await _services.hitomi.getComicInfo(target);
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(
        name: res.data.title,
        author: res.data.subTitle,
        coverPath: res.data.cover,
      );
    } else {
      var comicSource = type.comicSource;
      if (comicSource == null) return const Res.error('漫画源不可用');
      var res = await _loadCustom(ComicInfoQuery(comicSource.key.name, target));
      if (res.error) return Res.error(res.errorMessageWithoutNull);
      updated = item.copyWith(
        name: res.data.title,
        author: res.data.subTitle ?? '',
        coverPath: res.data.cover,
      );
    }
    return Res(updated);
  }
}

/// 只接受明确的 404 状态，避免 URL 或连接错误中包含 404 时误标记。
bool isFavoriteUnavailable(Res<FavoriteItem> result) {
  if (!result.error) return false;
  if (result.subData is int) return result.subData == 404;
  final message = result.errorMessageWithoutNull.trim();
  return RegExp(r'^404(?:\D|$)').hasMatch(message) ||
      RegExp(
        r'\bhttp(?:\s+status)?\s*[:=]?\s*404\b',
        caseSensitive: false,
      ).hasMatch(message) ||
      RegExp(
        r'\bstatus\s*code\s*(?:of|:|=)?\s*404\b',
        caseSensitive: false,
      ).hasMatch(message);
}

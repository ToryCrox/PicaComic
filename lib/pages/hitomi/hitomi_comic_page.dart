import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../comic_page.dart';

/// Hitomi 漫画详情页兼容入口。
class HitomiComicPage extends StatelessWidget {
  HitomiComicPage(HitomiComicBrief comic, {super.key})
    : link = comic.link,
      comicCover = comic.cover;

  const HitomiComicPage.fromLink(this.link, {super.key, String? cover})
    : comicCover = cover;

  final String link;
  final String? comicCover;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.hitomi, id: link, cover: comicCover);
  }
}

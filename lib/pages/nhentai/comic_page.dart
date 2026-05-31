import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../comic_page.dart';

/// Nhentai 漫画详情页兼容入口。
class NhentaiComicPage extends StatelessWidget {
  const NhentaiComicPage(String id, {super.key, this.comicCover}) : _id = id;

  final String _id;
  final String? comicCover;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.nhentai, id: _id, cover: comicCover);
  }
}

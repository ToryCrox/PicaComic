import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../comic_page.dart';

/// 绅士漫画详情页兼容入口。
class HtComicPage extends StatelessWidget {
  const HtComicPage(this.id, {super.key, this.comicCover});

  final String id;
  final String? comicCover;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.htmanga, id: id, cover: comicCover);
  }
}

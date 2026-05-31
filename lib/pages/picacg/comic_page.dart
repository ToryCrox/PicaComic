import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../comic_page.dart';

/// Picacg 漫画详情页兼容入口。
class PicacgComicPage extends StatelessWidget {
  const PicacgComicPage(this.id, this.cover, {super.key});

  final String id;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.picacg, id: id, cover: cover);
  }
}

import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../comic_page.dart';

/// Kemono 投稿详情页兼容入口。
class KemonoComicPage extends StatelessWidget {
  const KemonoComicPage(this.id, this.cover, {super.key});

  final String id;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.kemono, id: id, cover: cover);
  }
}

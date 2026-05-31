import 'package:flutter/material.dart';

import '../../foundation/def.dart';
import '../comic_page.dart';

/// 禁漫天堂漫画详情页兼容入口。
class JmComicPage extends StatelessWidget {
  const JmComicPage(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ComicPage(comicType: ComicType.jm, id: id);
  }
}

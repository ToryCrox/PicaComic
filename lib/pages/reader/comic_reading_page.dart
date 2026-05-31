// Compatibility shim — delegates to ComicReaderPage.
// All existing call sites continue to work via named constructors.
// New code should use ComicReaderPage.open() instead.
import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/app.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import '../../network/jm_network/jm_models.dart';
import '../../network/jm_network/jm_image.dart';
import 'comic_reader_page.dart';
import 'reading_data.dart';
import 'reading_type.dart';

export 'reading_data.dart';
export 'reading_type.dart';

@Deprecated('Use ComicReaderPage.open() instead')
class ComicReadingPage extends StatelessWidget implements RootNavigatorPage {
  final ReadingData readingData;
  final int initialPage;
  final int initialEp;

  ReadingType get type => readingData.type;

  ComicReadingPage._(
    this.readingData,
    this.initialPage,
    this.initialEp, {
    super.key,
  });

  ComicReadingPage(
    ReadingData readingData,
    int initialPage,
    int initialEp, {
    super.key,
  }) : readingData = readingData,
       initialPage = initialPage,
       initialEp = initialEp;

  ComicReadingPage.picacg(
    String target,
    int initialEp,
    List<String> eps,
    String title, {
    super.key,
    int initialPage = 1,
  }) : readingData = PicacgReadingData(title, target, eps),
       initialPage = initialPage,
       initialEp = initialEp;

  ComicReadingPage.ehentai(Gallery gallery, {super.key, int initialPage = 1})
    : initialEp = 1,
      readingData = EhReadingData(gallery),
      initialPage = initialPage;

  ComicReadingPage.jmComic(
    JmComicInfo comic,
    int initialEp, {
    super.key,
    int initialPage = 1,
  }) : readingData = JmReadingData(
         comic.name,
         comic.id,
         comic.series.values.toList(),
         comic.epNames,
       ),
       initialPage = initialPage,
       initialEp = initialEp;

  ComicReadingPage.hitomi(
    HitomiComic comic,
    String link, {
    super.key,
    int initialPage = 1,
  }) : initialEp = 1,
       readingData = HitomiReadingData(
         comic.title,
         comic.target,
         comic.files,
         link,
       ),
       initialPage = initialPage;

  ComicReadingPage.htmanga(
    String target,
    String title, {
    super.key,
    int initialPage = 1,
  }) : initialEp = 1,
       readingData = HtReadingData(title, target),
       initialPage = initialPage;

  ComicReadingPage.nhentai(
    String target,
    String title, {
    super.key,
    int initialPage = 1,
  }) : initialEp = 1,
       readingData = NhentaiReadingData(title, target),
       initialPage = initialPage;

  ComicReadingPage.localComic(
    String dirPath,
    String title, {
    super.key,
    int initialPage = 1,
    final List<String> allDirPaths = const [],
    bool isReversed = false,
    final bool isAutoFullscreenAndScroll = false,
  }) : initialEp = 1,
       readingData = LocalReadingData(
         dirPath,
         title,
         allDirPaths: allDirPaths,
         isReversed: isReversed,
       ),
       initialPage = initialPage;

  bool get useDarkBackground => appdata.appSettings.useDarkBackground;

  @override
  Widget build(BuildContext context) {
    // Delegate to new reader
    return ComicReaderPage(
      readingData: readingData,
      initialPage: initialPage,
      initialEp: initialEp,
    );
  }
}

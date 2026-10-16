import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/grouped_chapters.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_downloaded_item.dart';
import 'package:pica_comic/pages/comic_page.dart' show EpsData;
import 'package:pica_comic/pages/comic_page/default_comic_page_adapter.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';

import 'manhuagui_comments_page.dart';
import 'manhuagui_reading_data.dart';

/// 漫画柜详情适配，连接分组目录、评论和独立下载模型。
class ManhuaguiAdapter extends DefaultComicPageAdapter {
  ManhuaguiAdapter() : super(ComicType.manhuagui);

  @override
  String url(ComicInfoData data) =>
      'https://www.manhuagui.com/comic/${data.comicId}/';

  /// 在系统默认浏览器中打开当前漫画详情。
  @override
  List<Widget>? buildExtraActionButtons(
    ComicInfoData data,
    BuildContext context,
    Widget Function(
      BuildContext,
      String,
      IconData,
      VoidCallback, [
      VoidCallback?,
    ])
    buildActionItem,
  ) => [
    buildActionItem(context, '打开链接'.tl, Icons.open_in_browser, () async {
      try {
        final opened = await launchUrlString(
          url(data),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) showToast(message: '打开链接失败'.tl);
      } catch (_) {
        showToast(message: '打开链接失败'.tl);
      }
    }),
  ];

  @override
  ComicInfoData? dataFromDownloadedItem(DownloadedItem item) =>
      item is ManhuaguiDownloadedItem ? item.comic : null;

  @override
  DownloadedItem? mergeDownloadedItem(
    DownloadedItem item,
    ComicInfoData data,
  ) => item is ManhuaguiDownloadedItem ? item.withComicInfo(data) : null;

  @override
  void addDownload(
    ComicInfoData data,
    List<int> selectedEps,
    DownloadManager manager,
  ) => manager.addManhuaguiDownload(data, selectedEps);

  @override
  EpsData? eps(ComicInfoData data, BuildContext context) {
    final chapters = data.chapters;
    if (chapters == null || chapters.isEmpty) return null;
    return EpsData(
      chapters.values.toList(),
      (index) async {
        await History.findOrCreate(data);
        App.globalTo(
          () => ComicReadingPage(ManhuaguiReadingData(data), 0, index + 1),
        );
      },
      groups: data.chapterGroups,
      chapterIds: chapters.keys.toList(),
    );
  }

  @override
  void read(ComicInfoData data, History? history, BuildContext context) async {
    final current = await History.createIfNull(history, data);
    final episode = data.episodeForHistory(current);
    final missing =
        current.chapterId != null &&
        !data.chapters!.containsKey(current.chapterId);
    App.globalTo(
      () => ComicReadingPage(
        ManhuaguiReadingData(data),
        missing ? 0 : current.page,
        episode,
      ),
    );
  }

  @override
  ActionFunc openComments(ComicInfoData data, BuildContext context) =>
      () => showSideBar(context, ManhuaguiCommentsPage(comicId: data.comicId));

  @override
  void download(
    ComicInfoData data,
    BuildContext context,
    DownloadManager manager,
  ) async {
    final id = downloadId(data.comicId, manager);
    if (manager.downloading.any((task) => task.id == id)) {
      showToast(message: '下载中'.tl);
      return;
    }
    final previous = await manager.getComicOrNull(id);
    if (!context.mounted) return;
    final keys = data.chapters!.keys.toList();
    final downloaded = <String>{};
    if (previous is ManhuaguiDownloadedItem) {
      for (final index in previous.downloadedEps) {
        final key = previous.chapters?.keys.elementAtOrNull(index);
        if (key != null) downloaded.add(key);
      }
    }
    final selector = GroupedDownloadChapters(
      chapters: data.chapters!,
      groups: data.chapterGroups,
      downloadedIds: downloaded,
      onDownload: (selected) {
        final indices = selected
            .map(keys.indexOf)
            .where((index) => index >= 0)
            .toList();
        if (indices.isEmpty) return;
        addDownload(data, indices, manager);
        App.globalBack();
        showToast(message: '已加入下载队列'.tl);
      },
      onDelete: (key) async {
        final item = await manager.getComicOrNull(id);
        if (item is! ManhuaguiDownloadedItem) return;
        final index = item.chapters!.keys.toList().indexOf(key);
        if (index < 0) return;
        if (item.downloadedEps.length == 1) {
          await manager.delete([id]);
        } else {
          final error = await manager.deleteEpisode(item, index);
          if (error != null) throw StateError(error);
        }
      },
    );
    if (UiMode.m1(context)) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .8,
          child: selector,
        ),
      );
    } else {
      showSideBar(context, selector, useSurfaceTintColor: true);
    }
  }
}

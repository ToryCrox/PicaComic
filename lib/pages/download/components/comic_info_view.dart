import 'package:flutter/material.dart';

import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/tools/translations.dart';

import 'download_tile.dart';
import 'package:pica_comic/pages/download/download_helper.dart';

/// 已下载漫画详情视图（显示章节列表）
class DownloadedComicInfoView extends StatefulWidget {
  const DownloadedComicInfoView({
    super.key,
    required this.item,
    this.onRefresh,
  });

  final DownloadedItem item;
  final VoidCallback? onRefresh;

  @override
  State<DownloadedComicInfoView> createState() =>
      _DownloadedComicInfoViewState();
}

class _DownloadedComicInfoViewState extends State<DownloadedComicInfoView> {
  String name = "";
  List<String> eps = [];
  List<int> downloadedEps = [];
  late final comic = widget.item;

  void deleteEpisode(int i) {
    showConfirmDialog(context, "确认删除".tl, "要删除这个章节吗".tl, () async {
      var message = await downloadManager.deleteEpisode(comic, i);
      if (message == null) {
        setState(() {});
        widget.onRefresh?.call();
      } else {
        showToast(message: message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    getInfo();
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
            child: Text(name, style: const TextStyle(fontSize: 22)),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 4,
              ),
              itemBuilder: (BuildContext context, int i) {
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                        color: downloadedEps.contains(i)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(child: Text(eps[i])),
                          const SizedBox(width: 4),
                          if (downloadedEps.contains(i))
                            const Icon(Icons.download_done),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                    onTap: () => readSpecifiedEps(i),
                    onLongPress: () {
                      deleteEpisode(i);
                    },
                    onSecondaryTapDown: (details) {
                      deleteEpisode(i);
                    },
                  ),
                );
              },
              itemCount: eps.length,
            ),
          ),
          SizedBox(
            height: 50,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      App.globalBack();
                      toComicInfoPage(widget.item);
                    },
                    child: Text("查看详情".tl),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: () => read(),
                    child: Text("阅读".tl),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  void getInfo() {
    name = comic.name;
    eps = comic.eps;
    downloadedEps = comic.downloadedEps;
  }

  void read() {
    comic.read();
  }

  void readSpecifiedEps(int i) {
    comic.read(ep: i + 1);
  }
}

/// 显示已下载漫画的章节信息
void showDownloadedComicInfo({
  required BuildContext context,
  required DownloadedItem comic,
  VoidCallback? onRefresh,
}) {
  if (UiMode.m1(context)) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return DownloadedComicInfoView(item: comic, onRefresh: onRefresh);
      },
    );
  } else {
    showSideBar(
      App.globalContext!,
      DownloadedComicInfoView(item: comic, onRefresh: onRefresh),
      useSurfaceTintColor: true,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/eh_network/eh_download_model.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/components/components.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({Key? key}) : super(key: key);

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage> {
  var comics = <DownloadingTask>[];

  @override
  void dispose() {
    downloadManager.removeListener(onChange);
    super.dispose();
  }

  @override
  void initState() {
    downloadManager.addListener(onChange);
    comics = List.from(downloadManager.downloading);
    super.initState();
  }

  void onChange() {
    if(downloadManager.error) {
      setState(() {});
    } else if (downloadManager.downloading.length != comics.length) {
      rebuild();
    } else if (key.currentState != null){
      key.currentState!.updateUi();
    }
  }

  void rebuild() {
    key = GlobalKey<_DownloadingTileState>();
    setState(() {
      comics = List.from(downloadManager.downloading);
    });
  }

  var key = GlobalKey<_DownloadingTileState>();

  @override
  Widget build(BuildContext context) {
    var widgets = <Widget>[];
    for (var i in comics) {
      var key = Key(i.id);
      if(i == comics.first) {
        key = this.key;
      }

      widgets.add(_DownloadingTile(
        comic: i,
        cancel: () {
          showConfirmDialog(context, "取消".tl, "取消下载任务?".tl, () {
            setState(() {
              downloadManager.cancel(i.id);
            });
          });
        },
        onComicPositionChange: rebuild,
        key: key,
      ));
    }

    final body = ListView.builder(
        itemCount: downloadManager.downloading.length + 1,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          if (index == 0) {
            String downloadStatus;
            if (downloadManager.isDownloading) {
              downloadStatus = " 下载中".tl;
            } else if (downloadManager.downloading.isNotEmpty) {
              downloadStatus = " 已暂停".tl;
            } else {
              downloadStatus = "";
            }

            String downloadTaskText = "@length 项下载任务".tlParams(
                {"length": downloadManager.downloading.length.toString()});

            String displayText = downloadManager.error
                ? "下载出错".tl
                : downloadTaskText + downloadStatus;
            return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                    ),
                    downloadManager.isDownloading
                        ? const Icon(
                            Icons.downloading,
                            color: Colors.blue,
                          )
                        : const Icon(
                            Icons.pause_circle_outline_outlined,
                            color: Colors.red,
                          ),
                    const SizedBox(
                      width: 12,
                    ),
                    Text(displayText),
                    const Spacer(),
                    if (downloadManager.downloading.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          downloadManager.isDownloading
                              ? downloadManager.pause()
                              : downloadManager.start();
                          setState(() {});
                        },
                        child: downloadManager.isDownloading
                            ? Text("暂停".tl)
                            : (downloadManager.error
                                ? Text("重试".tl)
                                : Text("继续".tl)),
                      ),
                    const SizedBox(
                      width: 16,
                    ),
                  ],
                ));
          } else {
            return widgets[index - 1];
          }
        });

    return PopUpWidgetScaffold(
      title: "下载管理器".tl,
      body: body,
    );
  }
}

class _DownloadingTile extends StatefulWidget {
  const _DownloadingTile({
    required this.comic,
    required this.cancel,
    required this.onComicPositionChange,
    super.key,
  });

  final DownloadingTask comic;

  final void Function() cancel;

  final void Function() onComicPositionChange;

  @override
  State<_DownloadingTile> createState() => _DownloadingTileState();
}

class _DownloadingTileState extends State<_DownloadingTile> {
  late DownloadingTask comic;

  double value = 0.0;
  int downloadPages = 0;
  int? pagesCount;
  int? speed;
  bool _isExpanded = true;

  @override
  initState() {
    super.initState();
    comic = widget.comic;
    updateStatistic();
  }

  @override
  void didUpdateWidget(covariant _DownloadingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.comic != comic) {
      setState(() {
        comic = widget.comic;
      });
    }
  }

  void updateStatistic() {
    if(comic != DownloadManager().downloading.first) {
      return;
    }
    comic = DownloadManager().downloading.first;
    speed = comic.currentSpeed;
    downloadPages = comic.downloadedPages;
    pagesCount = comic.totalPages;
    if (pagesCount == 0) {
      pagesCount = null;
    }
    if (pagesCount != null && pagesCount! > 0) {
      value = downloadPages / pagesCount!;
    }
  }

  void updateUi() {
    setState(() {
      updateStatistic();
    });
  }

  /// 判断是否为单章节漫画（如 EH、Hitomi 等）
  bool get _isSingleEpisode {
    final progress = comic.episodeProgress;
    // 单章节的情况：没有进度数据，或者只有一个章节
    return progress.isEmpty || progress.length <= 1;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMainTile(context),
        if (_isExpanded && !_isSingleEpisode) _buildEpisodeList(context),
      ],
    );
  }

  Widget _buildMainTile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SizedBox(
        height: 114,
        width: double.infinity,
        child: Row(
          children: [
            Container(
              width: 84,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: context.colorScheme.secondaryContainer,
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedImage(
                image: CachedImageProvider(comic.cover,
                    headers: {"User-Agent": webUA}),
                width: 84,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: _isSingleEpisode ? null : () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comic.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!_isSingleEpisode)
                          Icon(
                            _isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      getProgressText(),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: value),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 50,
              child: Column(
                children: [
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.cancel,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.vertical_align_top),
                    onPressed: () {
                      DownloadManager().moveToFirst(comic);
                      widget.onComicPositionChange();
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeList(BuildContext context) {
    final progress = comic.episodeProgress;
    if (progress.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedKeys = progress.keys.toList()..sort();

    return Container(
      margin: const EdgeInsets.only(left: 100, right: 12, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 12,
        runSpacing: 10,
        children: sortedKeys.map((epIndex) {
          final ep = progress[epIndex]!;
          final epName = comic.getEpisodeName(epIndex);
          final epValue = ep.total > 0 ? ep.downloaded / ep.total : 0.0;
          final isCompleted = ep.downloaded >= ep.total && ep.total > 0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green.withOpacity(0.15)
                  : context.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCompleted
                    ? Colors.green.withOpacity(0.5)
                    : context.colorScheme.outline.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 完成状态指示器
                if (isCompleted)
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green,
                  )
                else if (epValue == 0)
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: context.colorScheme.primary,
                  )
                else
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      value: epValue,
                      strokeWidth: 2,
                    ),
                  ),
                const SizedBox(width: 6),
                // 章节名称
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    "$epName (${ep.downloaded}/${ep.total})",
                    style: TextStyle(
                      fontSize: 12,
                      color: isCompleted
                          ? Colors.green.shade700
                          : context.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 取消按钮（仅未完成时显示）
                if (!isCompleted) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      showConfirmDialog(
                        context,
                        "取消".tl,
                        "取消下载 $epName ?".tl,
                        () {
                          downloadManager.cancelEpisode(comic.id, epIndex);
                          setState(() {});
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _bytesToSize(int bytes) {
    if (bytes < 1024) {
      return "$bytes B";
    } else if (bytes < 1024 * 1024) {
      return "${(bytes / 1024).toStringAsFixed(2)} KB";
    } else if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / 1024 / 1024).toStringAsFixed(2)} MB";
    } else {
      return "${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
    }
  }

  String getProgressText() {
    if (pagesCount == null) {
      if (comic == DownloadManager().downloading.first) {
        return "获取图片信息...".tl;
      } else {
        return "";
      }
    }

    String speedInfo = "";
    if (speed != null) {
      speedInfo = "${_bytesToSize(speed!)}/s";
    }

    String status = "${"已下载".tl}$downloadPages/$pagesCount";

    // 对于 EhDownloadingTask 和 KemonoAttachmentDownloadingTask，以字节为单位显示
    if ((comic is EhDownloadingTask &&
            (comic as EhDownloadingTask).downloadType != 0) ||
        comic.runtimeType.toString() == 'KemonoAttachmentDownloadingTask') {
      status = "${_bytesToSize(downloadPages).split(' ').first}"
          "/${_bytesToSize(pagesCount!)}";
    }

    return "$status  $speedInfo";
  }
}

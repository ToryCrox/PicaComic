import 'package:pica_comic/foundation/def.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../foundation/history_providers.dart';
import '../foundation/app.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/comic_source_services.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  bool searchMode = false;
  String keyword = '';
  final _focusNode = FocusNode();

  /// 释放搜索焦点，业务数据由 Provider 持有。
  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 持久化失败时保留当前列表。
  Future<void> _perform(Future<void> Function() operation) async {
    try {
      await operation();
      if (mounted) App.back(context);
    } catch (error) {
      showToast(message: '操作失败: $error');
    }
  }

  Widget buildTitle(int count) {
    if (searchMode) {
      return TextField(
        focusNode: _focusNode,
        autofocus: true,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "搜索".tl,
        ),
        onChanged: (s) {
          setState(() {
            keyword = s.toLowerCase();
          });
        },
      );
    } else {
      return Text("${"历史记录".tl}(${count})");
    }
  }

  /// 观察持久化快照，搜索只派生当前列表。
  @override
  Widget build(BuildContext context) {
    final history = ref.watch(allHistoryProvider);
    final comics = history.asData?.value ?? const <HistoryRecord>[];
    final results = comics
        .where(
          (e) =>
              e.title.toLowerCase().contains(keyword) ||
              e.subtitle.toLowerCase().contains(keyword),
        )
        .toList();
    return Scaffold(
      body: SmoothCustomScrollView(
        slivers: [
          SliverAppBar(
            title: buildTitle(comics.length),
            actions: [
              Tooltip(
                message: "清除".tl,
                child: IconButton(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text("清除记录".tl),
                      content: Text("要清除历史记录吗?".tl),
                      actions: [
                        TextButton(
                          onPressed: () => App.globalBack(),
                          child: Text("取消".tl),
                        ),
                        TextButton(
                          onPressed: () => _perform(
                            ref.read(historyActionsProvider.notifier).clear,
                          ),
                          child: Text("清除".tl),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: "搜索".tl,
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      searchMode = !searchMode;
                      if (!searchMode) {
                        keyword = "";
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          if (history.isLoading && !history.hasValue)
            const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (history.hasError)
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: () => ref.invalidate(allHistoryProvider),
                child: Text('历史记录加载失败，点击重试'.tl),
              ),
            )
          else
            buildComics(searchMode ? results : comics),
          SliverPadding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.bottom,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildComics(List<HistoryRecord> comics_) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(childCount: comics_.length, (
        context,
        i,
      ) {
        final comic = ComicItemBrief(
          title: comics_[i].title,
          author: comics_[i].subtitle,
          path: comics_[i].cover != ""
              ? comics_[i].cover
              : getJmCoverUrl(comics_[i].target),
          id: comics_[i].target,
          tags: const [],
        );
        return NormalComicTile(
          key: Key(comics_[i].target),
          comicType: ComicType.fromString(comics_[i].type.name),
          onLongTap: () {
            showDialog(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text("删除".tl),
                  content: Text("要删除这条历史记录吗".tl),
                  actions: [
                    TextButton(
                      onPressed: () => App.globalBack(),
                      child: Text("取消".tl),
                    ),
                    TextButton(
                      onPressed: () => _perform(
                        () => ref
                            .read(historyActionsProvider.notifier)
                            .remove(comics_[i].target),
                      ),
                      child: Text("删除".tl),
                    ),
                  ],
                );
              },
            );
          },
          description_: timeToString(comics_[i].time),
          coverPath: comic.path,
          name: comic.title,
          subTitle_: comic.author,
          badgeName: comics_[i].type.name,
          headers: {
            if (comics_[i].type == HistoryType.ehentai)
              "cookie": appComicSourceServices.ehentai.cookiesStr,
            if (comics_[i].type == HistoryType.ehentai ||
                comics_[i].type == HistoryType.hitomi)
              "User-Agent": webUA,
            if (comics_[i].type == HistoryType.hitomi)
              "Referer": "https://hitomi.la/",
          },
          onTap: () {
            toComicPageWithHistory(context, comics_[i]);
          },
        );
      }),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }
}

void toComicPageWithHistory(BuildContext context, HistoryRecord history) {
  var source = history.type.comicSource;
  if (source == null) {
    showToast(message: "Comic Source Not Found");
    return;
  }
  context.to(
    () => ComicPage(
      comicType: source.key,
      id: history.target,
      cover: history.cover,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/image_loader/cached_image.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'accounts_page.dart';
import 'package:pica_comic/pages/download_page.dart';
import 'package:pica_comic/pages/tools.dart';
import 'package:pica_comic/foundation/app.dart';
import 'history_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'image_favorites.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  final List<History> _recentHistoryList = [];
  int _historyCount = 0;
  int _favoriteCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final recent = await HistoryManager().getRecent();
    _historyCount = await HistoryManager().count();
    _favoriteCount = await ImageFavoriteManager.length;
    setState(() {
      _recentHistoryList.clear();
      _recentHistoryList.addAll(recent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constrains) {
          final width = constrains.maxWidth;
          bool shouldShowTwoPanel = width > 600;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                const SizedBox(
                  height: 12,
                ),
                buildHistory(context),
                if (shouldShowTwoPanel)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 12,
                            ),
                            buildAccount(width),
                            const SizedBox(
                              height: 12,
                            ),
                            buildDownload(context, width),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 12,
                            ),
                            buildImageFavorite(context, width),
                            const SizedBox(
                              height: 12,
                            ),
                            buildTools(width),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  const SizedBox(
                    height: 12,
                  ),
                  buildAccount(width),
                  const SizedBox(
                    height: 12,
                  ),
                  buildDownload(context, width),
                  const SizedBox(
                    height: 12,
                  ),
                  buildImageFavorite(context, width),
                  const SizedBox(
                    height: 12,
                  ),
                  buildTools(width),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildHistory(BuildContext context) {
    var history = _recentHistoryList;
    return InkWell(
      onTap: () => context.to(() => const HistoryPage()),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(12),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.zero,
          width: double.infinity,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: Text("${"历史记录".tl}($_historyCount)"),
                trailing: const Icon(Icons.chevron_right),
                mouseCursor: SystemMouseCursors.click,
              ),
              SizedBox(
                height: 128,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () =>
                          toComicPageWithHistory(context, history[index]),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 96,
                        height: 128,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedImage(
                          image: CachedImageProvider(
                            history[index].cover,
                            sourceKey: history[index].type.comicSource?.key,
                          ),
                          width: 96,
                          height: 128,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    );
                  },
                ),
              ).paddingHorizontal(8),
              const SizedBox(
                height: 12,
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget buildAccount(double width) {
    var accounts = findAccounts();

    Widget buildItem(String name) {
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(App.globalContext!).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          name,
          style: const TextStyle(fontSize: 12),
        ).paddingTop(4),
      );
    }

    return _MePageCard(
      icon: const Icon(Icons.switch_account),
      title: "账号管理".tl,
      description:
          Text("已登录 @a 个账号".tlParams({"a": accounts.length.toString()})),
      onTap: () => showPopUpWidget(App.globalContext!, const AccountsPage()),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: accounts.map((e) => buildItem(e)).toList(),
      ).paddingHorizontal(12).paddingBottom(12),
    );
  }

  Widget buildDownload(BuildContext context, double width) {
    return _MePageCard(
      icon: const Icon(Icons.download_for_offline),
      title: "已下载".tl,
      description: const _DownloadCountText(),
      onTap: () => context.to(() => const DownloadPage()),
    );
  }

  Widget buildImageFavorite(BuildContext context, double width) {
    return _MePageCard(
      icon: const Icon(Icons.image),
      title: "图片收藏".tl,
      description: Text(
          "@a 条图片收藏".tlParams({"a": '$_favoriteCount'})),
      onTap: () => context.to(() => const ImageFavoritesPage()),
    );
  }

  Widget buildTools(double width) {
    Widget buildItem(String name) {
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(App.globalContext!).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          name,
          style: const TextStyle(fontSize: 12),
        ).paddingTop(4),
      );
    }

    return _MePageCard(
      icon: const Icon(Icons.build_circle),
      title: "工具".tl,
      description: Text("使用工具发现更多漫画".tl),
      onTap: openTool,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          buildItem("EH订阅".tl),
          buildItem("图片搜索".tl),
          buildItem("打开链接".tl),
        ],
      ).paddingHorizontal(12).paddingBottom(12),
    );
  }

  List<String> findAccounts() {
    var result = <String>[];
    for (var source in ComicSource.sources) {
      if (source.isLogin) {
        result.add(source.name.tl);
      }
    }
    return result;
  }
}

class _MePageCard extends StatelessWidget {
  const _MePageCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.child,
  });

  final Widget icon;
  final String title;
  final Widget description;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: icon,
              title: Text(title),
              trailing: const Icon(Icons.chevron_right),
              mouseCursor: SystemMouseCursors.click,
            ),
            DefaultTextStyle(
              style:
                  Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              child: description,
            ).paddingHorizontal(16).paddingBottom(16).paddingTop(8),
            if (child != null) child!
          ],
        ),
      ),
    );
  }
}

class _DownloadCountText extends StatefulWidget {
  const _DownloadCountText();

  @override
  State<_DownloadCountText> createState() => _DownloadCountTextState();
}

class _DownloadCountTextState extends State<_DownloadCountText> {
  String _count = '...';

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await DownloadManager().getTotal();
    if (mounted) {
      setState(() {
        _count = count.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text("共 $_count 部漫画".tlParams({"a": _count}));
  }
}

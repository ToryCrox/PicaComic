import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/translations.dart';
import '../foundation/def.dart';
import '../foundation/app_settings_provider.dart';
import 'explore_content_inset.dart';
import 'explore_providers.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage>
    with TickerProviderStateMixin {
  late TabController controller;

  bool showFB = true;

  double location = 0;

  final _session = Object();
  late List<String> pages;

  @override
  void initState() {
    super.initState();
    pages = ref
        .read(appSettingsProvider)
        .value(AppSettingKeys.explorePages)
        .split(',');
    var all = ComicSource.sources
        .map((e) => e.explorePages)
        .expand((e) => e.map((e) => e.title))
        .toList();
    pages = pages.where((e) => all.contains(e)).toList();
    controller = TabController(length: pages.length, vsync: this);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// 仅刷新当前来源的探索页，不通过全局标签查找 Widget。
  void refresh() {
    if (pages.isEmpty) return;
    final title = pages[controller.index];
    for (final source in ComicSource.sources) {
      if (source.explorePages.any((page) => page.title == title)) {
        ref
            .read(
              exploreRefreshProvider(_session, source.key.name, title).notifier,
            )
            .refresh();
        return;
      }
    }
  }

  Widget buildFAB() => Material(
    color: Colors.transparent,
    child: FloatingActionButton(
      key: const Key("FAB"),
      onPressed: refresh,
      child: const Icon(Icons.refresh),
    ),
  );

  Tab buildTab(String i) {
    return Tab(text: i.tl, key: Key(i));
  }

  Widget buildBody(String i, double topInset) =>
      _SingleExplorePage(_session, i, topInset: topInset, key: Key(i));

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.paddingOf(context).top + 48;
    const contentInset = 0.0;
    final tabContent = SafeArea(
      top: true,
      bottom: false,
      child: FilledTabBar(
        tabs: pages.map((e) => buildTab(e)).toList(),
        controller: controller,
        showBottomBorder: true,
        glassSelected: false,
      ),
    );
    final tabBar = WindowsGlassHeader(
      fallback: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: tabContent,
      ),
      child: tabContent,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: headerHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notifications) {
                if (notifications.metrics.axis == Axis.horizontal) {
                  if (!showFB) {
                    setState(() {
                      showFB = true;
                    });
                  }
                  return true;
                }

                var current = notifications.metrics.pixels;

                if ((current > location && current != 0) && showFB) {
                  setState(() {
                    showFB = false;
                  });
                } else if ((current < location || current == 0) && !showFB) {
                  setState(() {
                    showFB = true;
                  });
                }

                location = current;
                return false;
              },
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: TabBarView(
                  controller: controller,
                  children: pages
                      .map((e) => buildBody(e, contentInset))
                      .toList(),
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: tabBar),
          Positioned(
            right: 16,
            bottom: 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              reverseDuration: const Duration(milliseconds: 150),
              child: showFB ? buildFAB() : const SizedBox(),
              transitionBuilder: (widget, animation) {
                var tween = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: const Offset(0, 0),
                );
                return SlideTransition(
                  position: tween.animate(animation),
                  child: widget,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个探索页按来源和父页面会话观察刷新信号。
class _SingleExplorePage extends ConsumerStatefulWidget {
  const _SingleExplorePage(
    this.session,
    this.title, {
    required this.topInset,
    super.key,
  });

  final Object session;
  final String title;
  final double topInset;

  @override
  ConsumerState<_SingleExplorePage> createState() => _SingleExplorePageState();
}

/// 滚动与自定义页面的 Widget 生命周期保持在当前页面。
class _SingleExplorePageState extends ConsumerState<_SingleExplorePage> {
  late final ExplorePageData data;
  late final ComicType comicSourceKey;

  @override
  void initState() {
    super.initState();
    for (final source in ComicSource.sources) {
      for (final page in source.explorePages) {
        if (page.title == widget.title) {
          data = page;
          comicSourceKey = source.key;
          return;
        }
      }
    }
    throw StateError('Explore Page ${widget.title} Not Found!');
  }

  /// 手动重试与浮动按钮走同一刷新入口。
  void refresh() => ref
      .read(
        exploreRefreshProvider(
          widget.session,
          comicSourceKey.name,
          widget.title,
        ).notifier,
      )
      .refresh();

  @override
  Widget build(BuildContext context) {
    final refreshProvider = exploreRefreshProvider(
      widget.session,
      comicSourceKey.name,
      widget.title,
    );
    final revision = ref.watch(refreshProvider);
    if (data.loadMultiPart != null) {
      final parts = ref.watch(
        explorePartsProvider(widget.session, comicSourceKey.name, data),
      );
      return parts.when(
        skipLoadingOnRefresh: false,
        skipLoadingOnReload: false,
        data: (parts) => SmoothCustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: widget.topInset)),
            for (final part in parts)
              ..._buildExplorePagePart(part, comicSourceKey),
          ],
        ),
        error: (error, _) => Padding(
          padding: EdgeInsets.only(top: widget.topInset),
          child: NetworkError(
            message: error.toString(),
            retry: refresh,
            withAppbar: false,
          ),
        ),
        loading: () => Padding(
          padding: EdgeInsets.only(top: widget.topInset),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (data.loadPage != null) {
      final pageKey =
          '${comicSourceKey.name}:${widget.title}:${identityHashCode(widget.session)}';
      ref.listen(refreshProvider, (_, _) {
        refreshComicListPage(
          context,
          ComicListPageConfig(
            pageKey: pageKey,
            loadPage: (ref, page) => data.loadPage!(ref, page),
            loadCache: data.loadCache,
            onError: (message) => showToast(message: message),
          ),
        );
      });
      return _ComicList(
        (ref, page) => data.loadPage!(ref, page),
        pageKey,
        comicSourceKey,
        cacheBuilder: data.loadCache,
        topInset: widget.topInset,
      );
    }
    if (data.loadMixed != null) {
      return _MixedExplorePage(
        data,
        comicSourceKey,
        ProviderScope.containerOf(context, listen: false),
        widget.session,
        revision,
        topInset: widget.topInset,
        key: ValueKey(revision),
      );
    }
    if (data.overridePageBuilder != null) {
      final customPage = Builder(
        builder: data.overridePageBuilder!,
        key: ValueKey(revision),
      );
      if (comicSourceKey == ComicType.hiperdex) {
        return ExploreContentInset(inset: widget.topInset, child: customPage);
      }
      return Padding(
        padding: EdgeInsets.only(top: widget.topInset),
        child: customPage,
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: widget.topInset),
      child: const Center(child: Text('Empty Page')),
    );
  }
}

class _ComicList extends ComicsPage<BaseComic> {
  const _ComicList(
    this.builder,
    this.tag,
    this.comicType, {
    this.cacheBuilder,
    required this.topInset,
  });

  final double topInset;

  @override
  double get contentTopInset => topInset;

  @override
  final String tag;

  final ComicListBuilder builder;

  final ComicListCacheBuilder? cacheBuilder;

  @override
  final ComicType comicType;

  @override
  Future<List<BaseComic>> getComicsCache() {
    return cacheBuilder?.call() ?? SynchronousFuture([]);
  }

  @override
  Future<Res<List<BaseComic>>> getComics(int i, Ref ref) {
    return builder(ref, i);
  }

  @override
  String? get title => null;
}

class _MixedExplorePage extends StatefulWidget {
  const _MixedExplorePage(
    this.data,
    this.comicType,
    this.container,
    this.session,
    this.revision, {
    required this.topInset,
    super.key,
  });

  final ExplorePageData data;

  final ComicType comicType;

  final ProviderContainer container;
  final Object session;
  final int revision;
  final double topInset;

  @override
  State<_MixedExplorePage> createState() => _MixedExplorePageState();
}

class _MixedExplorePageState
    extends MultiPageLoadingState<_MixedExplorePage, Object> {
  Iterable<Widget> buildSlivers(BuildContext context, List<Object> data) sync* {
    List<BaseComic> cache = [];
    for (var part in data) {
      if (part is ExplorePagePart) {
        if (cache.isNotEmpty) {
          yield SliverGridComics(comics: (cache), comicType: widget.comicType);
          yield const SliverToBoxAdapter(child: Divider());
          cache.clear();
        }
        yield* _buildExplorePagePart(part, widget.comicType);
        yield const SliverToBoxAdapter(child: Divider());
      } else {
        cache.addAll(part as List<BaseComic>);
      }
    }
    if (cache.isNotEmpty) {
      yield SliverGridComics(comics: (cache), comicType: widget.comicType);
    }
  }

  @override
  Widget buildContent(BuildContext context, List<Object> data) {
    return SmoothCustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: widget.topInset)),
        ...buildSlivers(context, data),
        if (haveNextPage) const ListLoadingIndicator().toSliver(),
      ],
    );
  }

  @override
  Future<Res<List<Object>>> loadData(int page) async {
    var res = await widget.container.read(
      exploreMixedProvider(
        widget.session,
        widget.data,
        widget.revision,
        page,
      ).future,
    );
    if (res.error) {
      return res;
    }
    for (var element in res.data) {
      if (element is! ExplorePagePart && element is! List<BaseComic>) {
        return const Res.error("function loadMixed return invalid data");
      }
    }
    return res;
  }
}

Iterable<Widget> _buildExplorePagePart(
  ExplorePagePart part,
  ComicType comicType,
) sync* {
  Widget buildTitle(ExplorePagePart part) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Text(
                part.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (part.viewMore != null)
                TextButton(
                  onPressed: () {
                    var context = App.mainNavigatorKey!.currentContext!;
                    if (part.viewMore!.startsWith("search:")) {
                      context.to(
                        () => SearchResultPage(
                          keyword: part.viewMore!.replaceFirst("search:", ""),
                          comicType: comicType,
                        ),
                      );
                    } else if (part.viewMore!.startsWith("category:")) {
                      var cp = part.viewMore!.replaceFirst("category:", "");
                      var c = cp.split('@').first;
                      String? p = cp.split('@').last;
                      if (p == c) {
                        p = null;
                      }
                      context.to(
                        () => CategoryComicsPage(
                          category: c,
                          comicType: comicType,
                          param: p,
                        ),
                      );
                    }
                  },
                  child: Text("查看更多".tl),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildComics(ExplorePagePart part) {
    return SliverGridComics(comics: part.comics, comicType: comicType);
  }

  yield buildTitle(part);
  yield buildComics(part);
}

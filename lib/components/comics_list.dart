part of 'components.dart';

/// 漫画列表页面
///
/// T为漫画信息模型
abstract class ComicsPage<T extends BaseComic> extends ConsumerWidget {
  const ComicsPage({super.key});

  /// 标题。
  String? get title;

  /// 是否居中标题。
  bool get centerTitle => true;

  /// 获取缓存数据。
  Future<List<T>> getComicsCache() => SynchronousFuture([]);

  /// 获取漫画，参数为页面序号，从 1 开始。
  Future<Res<List<T>>> getComics(int i);

  /// 漫画源标识符。
  ComicType get comicType;

  /// 显示一个刷新按钮，需要 Scaffold 启用。
  bool get withRefreshFloatingButton => false;

  /// 列表页 Provider 的稳定标识。
  String get tag;

  Widget? get tailing => null;

  Widget? get header => null;

  bool get showPageIndicator => true;

  /// 构建漫画卡片的附加菜单。
  List<ComicTileMenuOption>? buildAddonMenuOptions(ComicListPageLogic logic) =>
      null;

  /// 将当前页面的泛型加载器转换为列表 Provider 使用的基础类型加载器。
  ComicListPageConfig get pageConfig {
    return ComicListPageConfig(
      pageKey: tag,
      loadPage: (page) async {
        final result = await getComics(page);
        if (result.error) {
          return Res(
            null,
            errorMessage: result.errorMessage,
            subData: result.subData,
          );
        }
        return Res(result.data.cast<BaseComic>(), subData: result.subData);
      },
      loadCache: () async => (await getComicsCache()).cast<BaseComic>(),
      onError: (message) => showToast(message: message),
    );
  }

  /// 刷新页面。
  void refresh() {
    final context = App.globalContext;
    if (context != null) {
      refreshComicListPage(context, pageConfig);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(blockingKeywordRevisionProvider);
    final config = pageConfig;
    final provider = comicListPageLogicProvider(config);
    final pageState = ref.watch(provider);
    final logic = ref.read(provider.notifier);

    Widget? removeSliver(Widget? widget) {
      if (widget == null) return null;

      if (widget is SliverToBoxAdapter) {
        return widget.child;
      }

      if (widget is SliverPersistentHeader) {
        return SizedBox(
          height: widget.delegate.minExtent,
          child: widget.delegate.build(
            context,
            widget.delegate.minExtent,
            false,
          ),
        );
      }

      return widget;
    }

    final isPaged = appdata.settings[25] != "0";
    final currentPageComics = pageState.dividedComics[pageState.current];
    if (isPaged &&
        currentPageComics == null &&
        pageState.message == null &&
        !pageState.loadingData) {
      logic.ensurePageLoaded(pageState.current);
    }

    Widget body;
    if (pageState.loading || (isPaged && currentPageComics == null)) {
      body = Column(
        children: [
          if (title != null) const Appbar(title: Text("")),
          removeSliver(header) ?? const SizedBox(),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    } else if (pageState.message != null) {
      body = Column(
        children: [
          removeSliver(header) ?? const SizedBox(),
          Expanded(
            child: NetworkError(
              message: pageState.message ?? "Network Error",
              retry: logic.refresh,
              withAppbar: title != null,
            ),
          ),
        ],
      );
    } else if (!isPaged) {
      final loadedComics = pageState.comics ?? const <BaseComic>[];
      final comics = _filterComics(loadedComics);
      if (comics.isEmpty) {
        body = _buildEmptyPage(context);
      } else {
        body = SmoothCustomScrollView(
          slivers: [
            if (title != null) _buildAppbar(),
            if (header != null) header!,
            SliverGrid(
              delegate: SliverChildBuilderDelegate(childCount: comics.length, (
                context,
                i,
              ) {
                if (i == comics.length - 1) {
                  logic.loadNextPage();
                }
                return buildItem(context, comics[i], logic);
              }),
              gridDelegate: SliverGridDelegateWithComics(),
            ),
            if (pageState.current < (pageState.maxPage ?? 114514) &&
                pageState.loadingData)
              const SliverToBoxAdapter(child: ListLoadingIndicator())
            else
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      }
    } else {
      final comics = _filterComics(currentPageComics ?? const <BaseComic>[]);
      if (comics.isEmpty) {
        body = _buildEmptyPage(context);
      } else {
        body = SmoothCustomScrollView(
          slivers: [
            if (title != null) _buildAppbar(),
            if (header != null) header!,
            if (showPageIndicator &&
                appdata.settings[64] == "0" &&
                pageState.maxPage != 1)
              buildPageSelector(context, logic),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                childCount: comics.length,
                (context, i) => buildItem(context, comics[i], logic),
              ),
              gridDelegate: SliverGridDelegateWithComics(),
            ),
            if (showPageIndicator &&
                appdata.settings[64] == "0" &&
                pageState.maxPage != 1)
              buildPageSelector(context, logic),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
            ),
          ],
        );

        body = NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            final delta = notification.scrollDelta;
            if (delta == null) return false;
            if (delta > 0 && logic.value.showFloatingButton) {
              logic.setShowFloatingButton(false);
            } else if ((delta < 0 ||
                    notification.metrics.pixels ==
                        notification.metrics.minScrollExtent ||
                    notification.metrics.pixels ==
                        notification.metrics.maxScrollExtent) &&
                !logic.value.showFloatingButton) {
              logic.setShowFloatingButton(true);
            }
            return false;
          },
          child: body,
        );

        if (showPageIndicator && appdata.settings[64] == "1") {
          body = Stack(
            children: [
              Positioned.fill(child: body),
              Positioned(
                left: 0,
                right: 12,
                top: 0,
                bottom: 0,
                child: buildPageSelectorRight(context, logic),
              ),
            ],
          );
        }
      }
    }

    if (header != null && UiMode.m1(context)) {
      body = SafeArea(bottom: false, child: body);
    }

    if (withRefreshFloatingButton) {
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: logic.refresh,
          child: const Icon(Icons.refresh),
        ),
        body: body,
      );
    }
    return Material(child: body);
  }

  SliverAppBar _buildAppbar() {
    return SliverAppBar(
      title: Text(title!),
      actions: tailing != null ? [tailing!] : null,
    );
  }

  Widget _buildEmptyPage(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        if (title != null) _buildAppbar(),
        if (header != null) header!,
        SliverFillRemaining(
          hasScrollBody: false,
          child: buildEmptyView(context),
        ),
      ],
    );
  }

  List<T> _filterComics(List<BaseComic> comics) {
    if (!appdata.appSettings.fullyHideBlockedWorks) {
      return comics.cast<T>();
    }
    return [
      for (final comic in comics)
        if (isBlocked(comic) == null) comic as T,
    ];
  }

  Widget buildPageSelector(BuildContext context, ComicListPageLogic logic) {
    return SliverToBoxAdapter(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: SizedBox(
            width: 300,
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 16),
                FilledButton.tonal(
                  onPressed: () => previousPage(logic),
                  child: Text("上一页".tl),
                ),
                const Spacer(),
                ActionChip(
                  label: Text(
                    "${"页面".tl}: ${logic.value.current}/${logic.value.maxPage?.toString() ?? "?"}",
                  ),
                  onPressed: () => selectPage(logic),
                  elevation: 1,
                  side: BorderSide.none,
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => nextPage(logic),
                  child: Text("下一页".tl),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPageSelectorRight(
    BuildContext context,
    ComicListPageLogic logic,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedSlide(
        offset: logic.value.showFloatingButton
            ? const Offset(0, 0)
            : const Offset(1.5, 0),
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          elevation: 3,
          child: SizedBox(
            height: 156,
            width: 58,
            child: Column(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    onTap: () => previousPage(logic),
                    child: const SizedBox.expand(
                      child: Center(child: Icon(Icons.keyboard_arrow_left)),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: InkWell(
                    onTap: () => selectPage(logic),
                    child: SizedBox.expand(
                      child: Center(
                        child: Text(
                          "${logic.value.current}/${logic.value.maxPage?.toString() ?? "?"}",
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    onTap: () => nextPage(logic),
                    child: const SizedBox.expand(
                      child: Center(child: Icon(Icons.keyboard_arrow_right)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectPage(ComicListPageLogic logic) async {
    String result = "";
    await showDialog(
      context: App.globalContext!,
      builder: (dialogContext) {
        final controller = TextEditingController();
        return SimpleDialog(
          title: const Text("切换页面"),
          children: [
            const SizedBox(width: 300),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: TextField(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "页码".tl,
                  suffixText:
                      "${"输入范围: ".tl}1-${logic.value.maxPage?.toString() ?? "?"}",
                ),
                controller: controller,
                onSubmitted: (value) {
                  result = value;
                  App.globalBack();
                },
              ),
            ),
            Center(
              child: FilledButton(
                child: Text("提交".tl),
                onPressed: () {
                  result = controller.text;
                  App.globalBack();
                },
              ),
            ),
          ],
        );
      },
    );
    if (result.isNum) {
      final page = int.parse(result);
      final maxPage = logic.value.maxPage;
      if (maxPage == null || (page > 0 && page <= maxPage)) {
        logic.selectPage(page);
        return;
      }
    }
    if (result != "") {
      showToast(message: "输入的数字不正确".tl);
    }
  }

  void nextPage(ComicListPageLogic logic) {
    if (!logic.nextPage()) {
      showToast(message: "已经是最后一页了".tl);
    }
  }

  void previousPage(ComicListPageLogic logic) {
    if (!logic.previousPage()) {
      showToast(message: "已经是第一页了".tl);
    }
  }

  Widget buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 12),
          Text("无匹配结果".tl, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget buildItem(BuildContext context, T item, ComicListPageLogic logic) {
    return buildComicTile(
      context,
      item,
      comicType,
      addonMenuOptions: buildAddonMenuOptions(logic),
    );
  }
}

class SliverGridComicsController extends StateController {}

class SliverGridComics extends StatelessWidget {
  const SliverGridComics({
    super.key,
    required this.comics,
    required this.comicType,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final ComicType comicType;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<SliverGridComicsController>(
      init: SliverGridComicsController(),
      builder: (controller) {
        List<BaseComic> comics = [];
        if (appdata.appSettings.fullyHideBlockedWorks) {
          for (var comic in this.comics) {
            if (isBlocked(comic) == null) {
              comics.add(comic);
            }
          }
        } else {
          comics = this.comics;
        }
        return _SliverGridComics(
          comics: comics,
          comicType: comicType,
          onLastItemBuild: onLastItemBuild,
        );
      },
    );
  }
}

class _SliverGridComics extends StatelessWidget {
  const _SliverGridComics({
    required this.comics,
    required this.comicType,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final ComicType comicType;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        if (index == comics.length - 1) {
          onLastItemBuild?.call();
        }
        return buildComicTile(context, comics[index], comicType);
      }, childCount: comics.length),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';

part 'comic_list_page_logic.g.dart';

/// 漫画列表页的分页加载函数。
typedef ComicListPageLoader = Future<Res<List<BaseComic>>> Function(int page);

/// 漫画列表页的缓存加载函数。
typedef ComicListCacheLoader = Future<List<BaseComic>> Function();

/// 漫画列表页 Provider 的配置。
///
/// [pageKey] 必须能够唯一标识一个列表页实例。加载函数不会参与相等性
/// 判断，因此同一个 key 在页面生命周期内必须对应同一组加载逻辑。
@immutable
class ComicListPageConfig {
  const ComicListPageConfig({
    required this.pageKey,
    required this.loadPage,
    this.loadCache,
    this.onError,
  });

  /// 列表页的稳定唯一标识。
  final String pageKey;

  /// 加载指定页的数据，页码从 1 开始。
  final ComicListPageLoader loadPage;

  /// 可选的本地缓存加载函数。
  final ComicListCacheLoader? loadCache;

  /// 加载下一页失败时的提示回调。
  final void Function(String message)? onError;

  @override
  bool operator ==(Object other) {
    return other is ComicListPageConfig && other.pageKey == pageKey;
  }

  @override
  int get hashCode => pageKey.hashCode;
}

/// 漫画列表页状态。
@immutable
class ComicListPageState {
  const ComicListPageState({
    this.loading = true,
    this.comics,
    this.dividedComics = const {},
    this.message,
    this.maxPage,
    this.current = 1,
    this.loadingData = false,
    this.showFloatingButton = true,
  });

  /// 是否正在显示首屏加载状态。
  final bool loading;

  /// 连续浏览模式下的漫画数据。
  final List<BaseComic>? comics;

  /// 分页浏览模式下已加载的漫画数据。
  final Map<int, List<BaseComic>> dividedComics;

  /// 网络错误信息。
  final String? message;

  /// 最大页数，未知时为 null。
  final int? maxPage;

  /// 当前页码。
  final int current;

  /// 是否正在加载数据。
  final bool loadingData;

  /// 分页模式侧边翻页按钮是否显示。
  final bool showFloatingButton;

  /// 创建更新后的列表页状态。
  ComicListPageState copyWith({
    bool? loading,
    List<BaseComic>? comics,
    bool clearComics = false,
    Map<int, List<BaseComic>>? dividedComics,
    String? message,
    bool clearMessage = false,
    int? maxPage,
    bool clearMaxPage = false,
    int? current,
    bool? loadingData,
    bool? showFloatingButton,
  }) {
    return ComicListPageState(
      loading: loading ?? this.loading,
      comics: clearComics ? null : (comics ?? this.comics),
      dividedComics: dividedComics ?? this.dividedComics,
      message: clearMessage ? null : (message ?? this.message),
      maxPage: clearMaxPage ? null : (maxPage ?? this.maxPage),
      current: current ?? this.current,
      loadingData: loadingData ?? this.loadingData,
      showFloatingButton: showFloatingButton ?? this.showFloatingButton,
    );
  }
}

/// 漫画列表页的 Riverpod 逻辑控制器。
///
/// 每个 [ComicListPageConfig.pageKey] 对应一个独立的 autoDispose Provider。
@Riverpod(keepAlive: false, name: 'comicListPageLogicProvider')
class ComicListPageLogic extends _$ComicListPageLogic {
  late ComicListPageConfig _config;

  bool _loadingRequest = false;
  int _requestGeneration = 0;
  int _emptyPageCount = 0;

  @override
  ComicListPageState build(ComicListPageConfig config) {
    _config = config;
    Future<void>.microtask(() => _loadInitial(_requestGeneration));
    return const ComicListPageState();
  }

  /// 当前列表页状态，供 UI 层读取。
  ComicListPageState get value => state;

  /// 首次加载列表数据，缓存存在时先显示缓存，再请求网络数据。
  Future<void> _loadInitial(int generation) async {
    if (_loadingRequest) return;
    _loadingRequest = true;
    state = state.copyWith(loadingData: true);

    try {
      final cacheLoader = _config.loadCache;
      if (cacheLoader != null) {
        final cacheData = await cacheLoader();
        if (!_isCurrent(generation)) return;
        if (cacheData.isNotEmpty) {
          final cached = List<BaseComic>.unmodifiable(cacheData);
          state = state.copyWith(
            loading: false,
            comics: cached,
            dividedComics: {1: cached},
          );
        }
      }

      final result = await _config.loadPage(1);
      if (!_isCurrent(generation)) return;
      if (result.error) {
        state = state.copyWith(
          loading: false,
          loadingData: false,
          message: result.errorMessage,
        );
        return;
      }

      final data = List<BaseComic>.unmodifiable(result.data);
      final maxPage = _readMaxPage(result, data);
      state = state.copyWith(
        loading: false,
        loadingData: false,
        comics: data,
        dividedComics: {1: data},
        maxPage: maxPage,
        clearMessage: true,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        loading: false,
        loadingData: false,
        message: error.toString(),
      );
    } finally {
      if (_isCurrent(generation)) {
        _loadingRequest = false;
      }
    }
  }

  /// 确保分页模式的当前页已经加载。
  void ensurePageLoaded(int page) {
    if (state.dividedComics[page] != null || _loadingRequest) return;
    state = state.copyWith(
      loading: true,
      loadingData: true,
      current: page,
      clearMessage: true,
    );
    unawaited(_loadPage(page, _requestGeneration));
  }

  Future<void> _loadPage(int page, int generation) async {
    if (_loadingRequest) return;
    _loadingRequest = true;

    try {
      final result = await _config.loadPage(page);
      if (!_isCurrent(generation)) return;
      if (result.error) {
        state = state.copyWith(
          loading: false,
          loadingData: false,
          message: result.errorMessage,
        );
        return;
      }

      final data = List<BaseComic>.unmodifiable(result.data);
      final divided = Map<int, List<BaseComic>>.from(state.dividedComics);
      divided[page] = data;
      state = state.copyWith(
        loading: false,
        loadingData: false,
        dividedComics: divided,
        maxPage: _readMaxPage(result, data) ?? state.maxPage,
        clearMessage: true,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        loading: false,
        loadingData: false,
        message: error.toString(),
      );
    } finally {
      if (_isCurrent(generation)) {
        _loadingRequest = false;
      }
    }
  }

  /// 连续浏览模式加载下一页。
  void loadNextPage() {
    final maxPage = state.maxPage;
    if (maxPage != null && state.current >= maxPage) return;
    if (_loadingRequest) return;

    final page = state.current + 1;
    state = state.copyWith(loadingData: true);
    unawaited(_loadNextPage(page, _requestGeneration));
  }

  Future<void> _loadNextPage(int page, int generation) async {
    _loadingRequest = true;
    try {
      final result = await _config.loadPage(page);
      if (!_isCurrent(generation)) return;
      if (result.error) {
        _config.onError?.call(result.errorMessage ?? "Network Error");
        state = state.copyWith(loadingData: false);
        return;
      }

      final maxPage = _readMaxPage(result, result.data);
      if (result.data.isEmpty) {
        _emptyPageCount++;
        var inferredMaxPage = state.maxPage;
        if (_emptyPageCount > 3 && inferredMaxPage == null) {
          // 某些漫画源不会返回总页数，连续多个空页面时认为已经加载完毕。
          inferredMaxPage = state.current;
        }
        if (inferredMaxPage == null) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (!_isCurrent(generation)) return;
        state = state.copyWith(
          current: page,
          loadingData: false,
          maxPage: maxPage ?? inferredMaxPage,
        );
      } else {
        _emptyPageCount = 0;
        final comics = [...state.comics ?? const <BaseComic>[], ...result.data];
        state = state.copyWith(
          comics: List<BaseComic>.unmodifiable(comics),
          current: page,
          loadingData: false,
          maxPage: maxPage ?? state.maxPage,
        );
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(loadingData: false);
      _config.onError?.call(error.toString());
    } finally {
      if (_isCurrent(generation)) {
        _loadingRequest = false;
      }
    }
  }

  /// 切换到指定页，已加载的页面直接显示，否则发起请求。
  void selectPage(int page) {
    if (page < 1) return;
    if (state.dividedComics[page] != null) {
      state = state.copyWith(current: page, loading: false);
      return;
    }
    ensurePageLoaded(page);
  }

  /// 切换到下一页。
  bool nextPage() {
    if (state.maxPage != null && state.current >= state.maxPage!) {
      return false;
    }
    selectPage(state.current + 1);
    return true;
  }

  /// 切换到上一页。
  bool previousPage() {
    if (state.current <= 1) {
      return false;
    }
    selectPage(state.current - 1);
    return true;
  }

  /// 更新分页模式侧边按钮的显示状态。
  void setShowFloatingButton(bool value) {
    if (state.showFloatingButton == value) return;
    state = state.copyWith(showFloatingButton: value);
  }

  /// 刷新列表并从第 1 页重新开始。
  void refresh() {
    _requestGeneration++;
    _loadingRequest = false;
    _emptyPageCount = 0;
    state = const ComicListPageState();
    unawaited(_loadInitial(_requestGeneration));
  }

  int? _readMaxPage(Res<List<BaseComic>> result, List<BaseComic> data) {
    if (result.subData is int) return result.subData as int;
    if (data.isEmpty) return 1;
    return null;
  }

  bool _isCurrent(int generation) {
    return ref.mounted && generation == _requestGeneration;
  }
}

/// 屏蔽关键词变更版本号。
///
/// 漫画列表页监听该 Provider，从而在关键词设置更新后重新计算过滤结果，
/// 不再需要遍历所有列表控制器逐个调用 update。
@Riverpod(keepAlive: true)
class BlockingKeywordRevision extends _$BlockingKeywordRevision {
  @override
  int build() => 0;

  /// 通知所有监听者重新计算屏蔽结果。
  void bump() {
    state++;
  }
}

/// 从指定 Provider 容器刷新漫画列表页。
void refreshComicListPage(BuildContext context, ComicListPageConfig config) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(comicListPageLogicProvider(config).notifier).refresh();
}

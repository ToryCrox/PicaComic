import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';

part 'hitomi_home_page.g.dart';

/// Hitomi 首页状态。
class HitomiHomePageState {
  const HitomiHomePageState({
    this.loading = true,
    this.message,
    this.comics,
    this.hitomiComics = const [],
  });

  final bool loading;
  final String? message;
  final ComicList? comics;
  final List<HitomiComicBrief> hitomiComics;

  /// 创建更新后的首页状态。
  HitomiHomePageState copyWith({
    bool? loading,
    String? message,
    ComicList? comics,
    List<HitomiComicBrief>? hitomiComics,
    bool clearMessage = false,
    bool clearComics = false,
  }) {
    return HitomiHomePageState(
      loading: loading ?? this.loading,
      message: clearMessage ? null : (message ?? this.message),
      comics: clearComics ? null : (comics ?? this.comics),
      hitomiComics: hitomiComics ?? this.hitomiComics,
    );
  }
}

/// Hitomi 首页加载异常。
class _HitomiHomePageException implements Exception {
  const _HitomiHomePageException(this.message);

  final String message;
}

/// Hitomi 首页逻辑。
@Riverpod(keepAlive: false)
class HitomiHomePageLogic extends _$HitomiHomePageLogic {
  late String _url;
  bool _loadingRequest = false;
  int _generation = 0;

  @override
  HitomiHomePageState build(String url) {
    _url = url;
    final generation = ++_generation;
    Future<void>.microtask(() => _loadInitial(url, generation));
    return const HitomiHomePageState();
  }

  Future<void> _loadInitial(String url, int generation) async {
    if (_loadingRequest) return;
    _loadingRequest = true;
    try {
      final res = await HiNetwork().getComics(url);
      if (!_isCurrent(generation)) return;
      if (res.error) {
        throw _HitomiHomePageException(res.errorMessage ?? "Error");
      }

      final parsed = await _parseIds(res.data);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        loading: false,
        comics: res.data,
        hitomiComics: List.unmodifiable(parsed),
        clearMessage: true,
      );
    } catch (error) {
      if (!_isCurrent(generation)) return;
      state = state.copyWith(loading: false, message: _messageFromError(error));
    } finally {
      if (_isCurrent(generation)) {
        _loadingRequest = false;
      }
    }
  }

  /// 加载下一页漫画。
  Future<void> loadNextPage() async {
    final comics = state.comics;
    if (comics == null || _loadingRequest || comics.toLoad >= comics.total) {
      return;
    }

    final generation = _generation;
    _loadingRequest = true;
    try {
      final res = await HiNetwork().loadNextPage(comics);
      if (!_isCurrent(generation)) return;
      if (res.error) {
        showToast(message: res.errorMessage ?? "Error");
        return;
      }

      final parsed = await _parseIds(comics);
      if (!_isCurrent(generation)) return;
      state = state.copyWith(
        comics: comics,
        hitomiComics: List.unmodifiable([...state.hitomiComics, ...parsed]),
      );
    } catch (error) {
      if (_isCurrent(generation)) {
        showToast(message: _messageFromError(error));
      }
    } finally {
      if (_isCurrent(generation)) {
        _loadingRequest = false;
      }
    }
  }

  Future<List<HitomiComicBrief>> _parseIds(ComicList comics) async {
    var futures = <Future<Res<HitomiComicBrief>>>[];
    final result = <HitomiComicBrief>[];

    Future<void> wait() async {
      final responses = await Future.wait(futures);
      futures.clear();
      for (var r in responses) {
        if (r.error) {
          throw _HitomiHomePageException(r.errorMessage ?? "Error");
        }
        result.add(r.data);
      }
    }

    for (var id in comics.comicIds) {
      if (futures.length >= 5) {
        await wait();
      }
      futures.add(HiNetwork().getComicInfoBrief(id.toString()));
    }
    await wait();
    comics.comicIds.clear();
    return result;
  }

  /// 刷新首页数据。
  void refresh() {
    _generation++;
    _loadingRequest = false;
    state = const HitomiHomePageState();
    Future<void>.microtask(() => _loadInitial(_url, _generation));
  }

  bool _isCurrent(int generation) {
    return ref.mounted && generation == _generation;
  }

  String _messageFromError(Object error) {
    if (error is _HitomiHomePageException) return error.message;
    return error.toString();
  }
}

class HitomiHomePageComics extends ConsumerWidget {
  const HitomiHomePageComics(this.url, {Key? key}) : super(key: key);
  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hitomiHomePageLogicProvider(url));
    final logic = ref.read(hitomiHomePageLogicProvider(url).notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    } else if (state.message != null) {
      return NetworkError(
        message: state.message!,
        retry: logic.refresh,
        withAppbar: false,
      );
    } else {
      return CustomScrollView(
        slivers: [
          SliverGridComics(
            comics: state.hitomiComics,
            comicType: ComicType.hitomi,
            onLastItemBuild: () {
              logic.loadNextPage();
            },
          ),
          if (state.comics!.toLoad < state.comics!.total)
            const SliverToBoxAdapter(child: ListLoadingIndicator()),
        ],
      );
    }
  }
}

class HitomiHomePage extends StatefulWidget {
  const HitomiHomePage({super.key});

  @override
  State<HitomiHomePage> createState() => _HitomiHomePageState();
}

class _HitomiHomePageState extends State<HitomiHomePage> {
  var type = "index";
  var lang = "-all";

  @override
  Widget build(BuildContext context) {
    var url = "https://ltn.${HiNetwork().baseDomain}/$type$lang.nozomi";
    return Column(
      children: [
        Material(
          textStyle: Theme.of(context).textTheme.headlineMedium,
          child: SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 16),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text("hitomi"),
                ),
                const Spacer(),
                Material(
                  child: Select(
                    values: [
                      "最新".tl,
                      "热门 | 今天".tl,
                      "热门 | 一周".tl,
                      "热门 | 本月".tl,
                      "热门 | 一年".tl,
                    ],
                    initialValue: 0,
                    onChange: (i) => setState(() {
                      type = [
                        "index",
                        "popular/today",
                        "popular/week",
                        "popular/month",
                        "popular/year",
                      ][i];
                    }),
                  ),
                ),
                const SizedBox(width: 16),
                Material(
                  child: Select(
                    width: 100,
                    values: const ["All", "中文", "日本語", "English"],
                    initialValue: 0,
                    onChange: (i) => setState(() {
                      lang = ["-all", "-chinese", "-japanese", "-english"][i];
                    }),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
        const Divider(),
        Expanded(child: HitomiHomePageComics(url, key: Key(url))),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart';

import 'hiperdex_browse_page.dart';

/// 单一 HiperDEX 探索入口，展示最新和热门两部分。
class HiperdexExplorePage extends StatefulWidget {
  const HiperdexExplorePage({super.key});

  @override
  State<HiperdexExplorePage> createState() => _HiperdexExplorePageState();
}

class _HiperdexExplorePageState extends State<HiperdexExplorePage> {
  List<BaseComic>? _latest;
  List<BaseComic>? _trending;
  String? _latestError;
  String? _trendingError;
  String _period = 'week';
  int _trendingGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLatest());
    unawaited(_loadTrending());
  }

  /// 缓存先显示，随后在后台更新最新章节。
  Future<void> _loadLatest() async {
    final cache = await HiperdexNetwork.instance.latestCache(1);
    if (!mounted) return;
    if (cache.isNotEmpty) setState(() => _latest = cache);
    final result = await HiperdexNetwork.instance.getLatest(
      1,
      forceRefresh: true,
    );
    if (!mounted) return;
    setState(() {
      _latestError = result.errorMessage;
      if (result.success) _latest = result.data;
    });
  }

  /// 切换周期时忽略旧请求，防止按天结果覆盖按月榜单。
  Future<void> _loadTrending() async {
    final generation = ++_trendingGeneration;
    final period = _period;
    final cache = await HiperdexNetwork.instance.trendingCache(
      1,
      period: period,
    );
    if (!mounted || generation != _trendingGeneration) return;
    if (cache.isNotEmpty) setState(() => _trending = cache);
    final result = await HiperdexNetwork.instance.getTrending(
      1,
      period: period,
      forceRefresh: true,
    );
    if (!mounted || generation != _trendingGeneration) return;
    setState(() {
      _trendingError = result.errorMessage;
      if (result.success) _trending = result.data;
    });
  }

  void _changePeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _trending = null;
      _trendingError = null;
    });
    unawaited(_loadTrending());
  }

  void _viewMore(bool trending) => App.mainNavigatorKey!.currentContext!.to(
    () => HiperdexBrowsePage(trending: trending, period: _period),
  );

  Widget _header(String title, bool trending) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => _viewMore(trending),
                child: const Text('查看更多'),
              ),
            ],
          ),
          if (trending) buildHiperdexPeriodSelector(_period, _changePeriod),
        ],
      ),
    ),
  );

  Widget _section(List<BaseComic>? comics, String? error, VoidCallback retry) {
    if (comics != null) {
      if (comics.isEmpty) {
        return const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Text('暂无漫画')),
        );
      }
      return SliverGridComics(
        comics: comics.take(12).toList(),
        comicType: ComicType.hiperdex,
      );
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 220,
        child: error == null
            ? const Center(child: CircularProgressIndicator())
            : NetworkError(message: error, retry: retry, withAppbar: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SmoothCustomScrollView(
    slivers: [
      _header('最新更新', false),
      _section(_latest, _latestError, () => unawaited(_loadLatest())),
      _header('热门', true),
      _section(_trending, _trendingError, () => unawaited(_loadTrending())),
      const SliverToBoxAdapter(child: SizedBox(height: 80)),
    ],
  );
}

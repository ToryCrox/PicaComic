import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/network/comic_source_services.dart';

/// HiperDEX 最新／热门的完整分页列表。
class HiperdexBrowsePage extends StatefulWidget {
  const HiperdexBrowsePage({
    super.key,
    required this.trending,
    this.period = 'week',
  });

  final bool trending;
  final String period;

  @override
  State<HiperdexBrowsePage> createState() => _HiperdexBrowsePageState();
}

class _HiperdexBrowsePageState extends State<HiperdexBrowsePage> {
  late String _period = widget.period;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: Appbar(
      title: Text(widget.trending ? 'HiperDEX 热门' : 'HiperDEX 最新更新'),
    ),
    body: Column(
      children: [
        if (widget.trending)
          Padding(
            padding: const EdgeInsets.all(8),
            child: buildHiperdexPeriodSelector(
              _period,
              (period) => setState(() => _period = period),
            ),
          ),
        Expanded(
          child: _HiperdexComicList(trending: widget.trending, period: _period),
        ),
      ],
    ),
  );
}

/// 站点提供的天／周／月热门榜切换控件。
Widget buildHiperdexPeriodSelector(
  String period,
  ValueChanged<String> onChanged,
) => SegmentedButton<String>(
  segments: const [
    ButtonSegment(value: 'day', label: Text('按天')),
    ButtonSegment(value: 'week', label: Text('按周')),
    ButtonSegment(value: 'month', label: Text('按月')),
  ],
  selected: {period},
  showSelectedIcon: false,
  onSelectionChanged: (values) => onChanged(values.first),
);

/// 列表首屏先读缓存，分页和手动刷新请求最新数据。
class _HiperdexComicList extends ComicsPage<BaseComic> {
  const _HiperdexComicList({required this.trending, required this.period});

  final bool trending;
  final String period;

  @override
  ComicType get comicType => ComicType.hiperdex;

  @override
  String? get title => null;

  @override
  String get tag => 'hiperdex-browse-$trending-$period';

  @override
  bool get withRefreshFloatingButton => true;

  @override
  Future<List<BaseComic>> getComicsCache() => trending
      ? appComicSourceServices.hiperdex.trendingCache(1, period: period)
      : appComicSourceServices.hiperdex.latestCache(1);

  @override
  Future<Res<List<BaseComic>>> getComics(int page, Ref ref) => trending
      ? ref
            .read(hiperdexNetworkProvider)
            .getTrending(page, period: period, forceRefresh: true)
      : ref.read(hiperdexNetworkProvider).getLatest(page, forceRefresh: true);
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';

/// 漫画柜单一探索入口。
class ManhuaguiExplorePage extends ConsumerStatefulWidget {
  const ManhuaguiExplorePage({super.key});

  @override
  ConsumerState<ManhuaguiExplorePage> createState() =>
      _ManhuaguiExplorePageState();
}

/// 各分区复用同一分页列表，分类条件进入列表查询标识。
class _ManhuaguiExplorePageState extends ConsumerState<ManhuaguiExplorePage> {
  var _section = 0;
  var _sort = 'update';
  @override
  Widget build(BuildContext context) {
    const sections = ['最近更新', '连载漫画', '完结漫画'];
    final filters = <String, String>{
      if (_section == 1) 'status': 'lianzai',
      if (_section == 2) 'status': 'wanjie',
    };
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<int>(
            segments: [
              for (var i = 0; i < sections.length; i++)
                ButtonSegment(value: i, label: Text(sections[i].tl)),
            ],
            selected: {_section},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _section = selection.single),
          ),
        ),
        if (_section != 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<String>(
              value: _sort,
              isExpanded: true,
              items: [
                for (final entry in const {
                  'index': '最新发布',
                  'update': '最近更新',
                  'view': '人气最旺',
                  'rate': '评分最高',
                }.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value.tl),
                  ),
              ],
              onChanged: (value) => setState(() => _sort = value ?? 'update'),
            ),
          ),
        Expanded(
          child: ManhuaguiComics(
            section: _section,
            filters: filters,
            sort: _sort,
          ),
        ),
      ],
    );
  }
}

/// 复用项目漫画卡片、刷新、虚拟列表与分页状态。
class ManhuaguiComics extends ComicsPage<BaseComic> {
  const ManhuaguiComics({
    super.key,
    required this.section,
    required this.filters,
    required this.sort,
  });
  final int section;
  final Map<String, String> filters;
  final String sort;
  @override
  ComicType get comicType => ComicType.manhuagui;
  @override
  String? get title => null;
  @override
  String get tag => 'manhuagui-$section-$sort-${jsonEncode(filters)}';
  @override
  Future<List<BaseComic>> getComicsCache() => appComicSourceServices.manhuagui
      .listCache(section: section, filters: filters, sort: sort);
  @override
  Future<Res<List<BaseComic>>> getComics(int page, Ref ref) {
    final network = ref.read(manhuaguiNetworkProvider);
    return section == 0
        ? network.updates(page)
        : network.catalog(filters: filters, sort: sort, page: page);
  }
}

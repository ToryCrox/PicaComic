import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/tools/translations.dart';

import 'manhuagui_explore_page.dart';

/// 从网站获取可用分类，分类失败可单独重试。
final manhuaguiFiltersProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(manhuaguiNetworkProvider).filters(),
);

/// 与网站筛选名称对应的首页分类模块。
const manhuaguiFilterLabels = {
  'area': '地区',
  'genre': '剧情',
  'age': '受众',
  'year': '年份',
  'letter': '字母',
  'status': '进度',
};

/// 漫画柜分类独立放在首页的分类 Tab 下。
class ManhuaguiCategoryPage extends ConsumerWidget {
  const ManhuaguiCategoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(manhuaguiFiltersProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => NetworkError(
          message: '$error',
          withAppbar: false,
          retry: () => ref.invalidate(manhuaguiFiltersProvider),
        ),
        data: (result) {
          if (result.error) {
            return NetworkError(
              message: result.errorMessageWithoutNull,
              withAppbar: false,
              retry: () => ref.invalidate(manhuaguiFiltersProvider),
            );
          }
          return ListView(
            children: [
              for (final group in result.data.entries)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manhuaguiFilterLabels[group.key]!.tl,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (final entry in group.value.entries)
                            FilledButton.tonal(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ManhuaguiCatalogPage(
                                    initialFilters: {group.key: entry.key},
                                  ),
                                ),
                              ),
                              child: Text(entry.value.tl),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
}

/// 分类结果允许组合筛选、排序及自动分页。
class ManhuaguiCatalogPage extends ConsumerStatefulWidget {
  const ManhuaguiCatalogPage({super.key, required this.initialFilters});
  final Map<String, String> initialFilters;

  @override
  ConsumerState<ManhuaguiCatalogPage> createState() =>
      _ManhuaguiCatalogPageState();
}

/// 筛选草稿属于当前分类页面，不影响探索中的连载、完结列表。
class _ManhuaguiCatalogPageState extends ConsumerState<ManhuaguiCatalogPage> {
  late final _filters = Map<String, String>.of(widget.initialFilters);
  var _sort = 'update';

  /// 保留完整筛选能力，默认折叠避免挤占结果列表。
  Widget _controls() => ref
      .watch(manhuaguiFiltersProvider)
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(manhuaguiFiltersProvider),
          child: Text('重新加载分类'.tl),
        ),
        data: (result) {
          if (result.error) {
            return TextButton(
              onPressed: () => ref.invalidate(manhuaguiFiltersProvider),
              child: Text('重新加载分类'.tl),
            );
          }
          return ExpansionTile(
            title: Text('分类筛选'.tl),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final group in result.data.entries)
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: _filters[group.key] ?? '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: manhuaguiFilterLabels[group.key]!.tl,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final entry in group.value.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value.tl),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _filters[group.key] = value ?? ''),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('漫画柜'.tl)),
    body: Column(
      children: [
        _controls(),
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
                DropdownMenuItem(value: entry.key, child: Text(entry.value.tl)),
            ],
            onChanged: (value) => setState(() => _sort = value ?? 'update'),
          ),
        ),
        Expanded(
          child: ManhuaguiComics(
            section: 3,
            filters: Map.of(_filters),
            sort: _sort,
          ),
        ),
      ],
    ),
  );
}

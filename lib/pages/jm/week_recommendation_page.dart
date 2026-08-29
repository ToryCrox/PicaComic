import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/tools/translations.dart';

import 'week_recommendation_logic.dart';

export 'week_recommendation_logic.dart';

/// JM 每周推荐页面。
class JmWeekRecommendationPage extends ConsumerWidget {
  const JmWeekRecommendationPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState = ref.watch(jmWeekRecommendationProvider);
    final logic = ref.read(jmWeekRecommendationProvider.notifier);
    final selectorKey = GlobalKey();
    const titleLength = 190;

    return Scaffold(
      appBar: Appbar(
        title: Text("每周必看".tl),
        actions: [
          pageState.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
            data: (data) => _RecommendationSelector(
              key: selectorKey,
              data: data,
              titleLength: titleLength,
              onSelect: logic.select,
            ),
          ),
        ],
      ),
      body: pageState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            NetworkError(message: _errorMessage(error), retry: logic.refresh),
        data: (data) => WeekRecommendationList(
          data.currentId,
          key: ValueKey(data.currentId),
        ),
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is JmWeekRecommendationException) return error.message;
    return "未知错误".tl;
  }
}

/// 每周推荐分类选择器。
class _RecommendationSelector extends StatelessWidget {
  const _RecommendationSelector({
    required this.data,
    required this.titleLength,
    required this.onSelect,
    super.key,
  });

  final JmWeekRecommendationState data;
  final int titleLength;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.all(5),
      width: MediaQuery.of(context).size.width > 250 + titleLength
          ? 250
          : MediaQuery.of(context).size.width - titleLength,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.currentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_drop_down_sharp),
            iconSize: 16,
            onPressed: () => _showCategories(context),
          ),
        ],
      ),
    );
  }

  void _showCategories(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    var offset = renderObject.localToGlobal(Offset.zero);
    offset = Offset(offset.dx + 246, offset.dy + 53);
    showMenu(
      constraints: BoxConstraints(
        maxHeight: 300,
        minWidth:
            (MediaQuery.of(context).size.width > 250
                ? 250
                : MediaQuery.of(context).size.width) -
            16,
      ),
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        MediaQuery.of(context).size.width - offset.dx,
        MediaQuery.of(context).size.height - offset.dy,
      ),
      items: [
        for (final item in data.recommendations.entries)
          PopupMenuItem(
            value: item.key,
            child: Text(item.value),
            onTap: () => onSelect(item.key),
          ),
      ],
    );
  }
}

/// JM 每周推荐的三个分类列表。
class WeekRecommendationList extends ConsumerWidget {
  const WeekRecommendationList(this.id, {Key? key}) : super(key: key);

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabStates = [
      for (final type in WeekRecommendationType.values)
        ref.watch(jmWeekRecommendationComicsProvider((id, type))),
    ];
    final initialIndex = _initialRecommendationTabIndex(tabStates);

    return DefaultTabController(
      key: ValueKey('$id-$initialIndex'),
      initialIndex: initialIndex,
      length: WeekRecommendationType.values.length,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: "韩漫".tl),
              Tab(text: "日漫".tl),
              Tab(text: "其它".tl),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final type in WeekRecommendationType.values)
                  _RecommendationTab(id: id, type: type),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 选择第一个有内容的推荐分类作为默认页。
int _initialRecommendationTabIndex(
  List<AsyncValue<List<JmComicBrief>>> states,
) {
  // 等待所有分类完成首轮请求，避免某个分类较慢时提前切换默认页。
  if (states.any((state) => state.isLoading)) return 0;

  for (var index = 0; index < states.length; index++) {
    if (states[index].value?.isNotEmpty ?? false) return index;
  }
  return 0;
}

/// 单个 JM 每周推荐分类列表。
class _RecommendationTab extends ConsumerWidget {
  const _RecommendationTab({required this.id, required this.type});

  final String id;
  final WeekRecommendationType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = jmWeekRecommendationComicsProvider((id, type));
    final pageState = ref.watch(provider);
    return pageState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => NetworkError(
        message: _errorMessage(error),
        retry: () => ref.invalidate(provider),
      ),
      data: (comics) {
        if (comics.isEmpty) {
          return Center(
            child: Text(
              "本期暂无漫画".tl,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
        return CustomScrollView(
          slivers: [SliverGridComics(comics: comics, comicType: ComicType.jm)],
        );
      },
    );
  }

  String _errorMessage(Object error) {
    if (error is JmWeekRecommendationException) return error.message;
    return "未知错误".tl;
  }
}

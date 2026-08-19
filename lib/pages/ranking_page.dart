import "package:flutter/material.dart";
import "package:pica_comic/comic_source/comic_source.dart";
import "package:pica_comic/components/components.dart";
import "package:pica_comic/foundation/app.dart";
import "package:pica_comic/network/res.dart";
import "package:pica_comic/tools/translations.dart";
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/foundation/def.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({required this.comicType, super.key});

  final ComicType comicType;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  late final CategoryComicsData data;
  late final Map<String, String> options;
  late String optionValue;

  void findData() {
    final source = ComicSource.find(widget.comicType);
    if (source != null) {
      data = source.categoryComicsData!;
      options = data.rankingData!.options;
      optionValue = options.keys.first;
      return;
    }
    throw "${widget.comicType} Not found";
  }

  @override
  void initState() {
    findData();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("排行榜".tl)),
      body: Column(
        children: [
          Expanded(
            child: _CustomCategoryComicsList(
              key: ValueKey("RankingPage with $optionValue"),
              loader: data.rankingData!.load,
              optionValue: optionValue,
              header: buildOptions(),
              fieldComicType: widget.comicType,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOptionItem(String text, String value, BuildContext context) {
    return OptionChip(
      text: text,
      isSelected: value == optionValue,
      onTap: () {
        if (value == optionValue) return;
        setState(() {
          optionValue = value;
        });
      },
    );
  }

  Widget buildOptions() {
    List<Widget> children = [];
    children.add(
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var option in options.entries)
            buildOptionItem(option.value.tl, option.key, context),
        ],
      ),
    );
    return SliverToBoxAdapter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...children, const Divider()],
      ).paddingLeft(8).paddingRight(8),
    );
  }
}

class _CustomCategoryComicsList extends ComicsPage<BaseComic> {
  const _CustomCategoryComicsList({
    super.key,
    required this.loader,
    required this.optionValue,
    required this.header,
    required this.fieldComicType,
  });

  final Future<Res<List<BaseComic>>> Function(String option, int page) loader;

  final String optionValue;

  final ComicType fieldComicType;

  @override
  ComicType get comicType => fieldComicType;

  @override
  final Widget header;

  @override
  Future<Res<List<BaseComic>>> getComics(int i) async {
    return await loader(optionValue, i);
  }

  @override
  String get tag => "${fieldComicType.name} RankingPage with $optionValue";

  @override
  String? get title => null;
}

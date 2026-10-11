import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/disk_cache.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart';
import 'package:pica_comic/network/image_config.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/hiperdex/hiperdex_explore_page.dart';

/// HiperDEX 漫画源配置。
final hiperdex = ComicSource.named(
  name: 'HiperDEX',
  key: ComicType.hiperdex,
  filePath: 'built-in',
  url: HiperdexNetwork.baseUrl,
  comicTileBuilderOverride: (context, comic, options) =>
      _HiperdexComicTile(comic as HiperdexComic, addonMenuOptions: options),
  explorePages: [
    ExplorePageData.named(
      title: 'HiperDEX',
      type: ExplorePageType.override,
      overridePageBuilder: (_) => const HiperdexExplorePage(),
    ),
  ],
  searchPageData: SearchPageData.named(
    customOptionsBuilder: (context, initialValues, onChanged) =>
        _HiperdexSearchOptions(
          initialValues: initialValues,
          onChanged: onChanged,
        ),
    loadPage: (keyword, page, options) {
      final filters = _decodeOptions(options);
      return HiperdexNetwork.instance.search(
        keyword: keyword,
        page: page,
        sort: filters['sort'] ?? 'relevance',
        type: filters['type'],
        status: filters['status'],
        contentRating: filters['contentRating'],
        genre: filters['genre'],
        year: filters['year'],
        forceRefresh: true,
      );
    },
    loadCache: (keyword, options) {
      final filters = _decodeOptions(options);
      return HiperdexNetwork.instance.searchCache(
        keyword: keyword,
        sort: filters['sort'] ?? 'relevance',
        type: filters['type'],
        status: filters['status'],
        contentRating: filters['contentRating'],
        genre: filters['genre'],
        year: filters['year'],
      );
    },
  ),
  loadComicInfoCache: (id) =>
      DiskCache.readModel('hiperdex-info-v2-$id', ComicInfoData.fromMap),
  loadComicInfo: (id) async {
    final result = await HiperdexNetwork.instance.getSeries(
      id,
      forceRefresh: true,
    );
    if (result.error) return Res.fromErrorRes(result);
    final series = result.data;
    final chapters = <String, String>{};
    final rawChapters = series['_chapters'];
    if (rawChapters is List) {
      for (final rawChapter in rawChapters) {
        if (rawChapter is! Map) continue;
        final number = rawChapter['number']?.toString() ?? '';
        if (number.isEmpty) continue;
        final chapterId = rawChapter['id']?.toString() ?? '';
        final key = chapterId.isEmpty ? number : '$number|$chapterId';
        final title = rawChapter['title']?.toString() ?? '';
        chapters[key] = title.isEmpty
            ? 'Chapter $number'
            : 'Chapter $number — $title';
      }
    }

    final tags = <String, List<String>>{};
    void addTag(String key, dynamic value) {
      if (value == null) return;
      final values = value is List ? value : [value];
      final strings = values
          .map((item) {
            if (item is Map) {
              return (item['name'] ?? item['genre'] ?? item['slug'] ?? '')
                  .toString();
            }
            return item.toString();
          })
          .where((item) => item.isNotEmpty)
          .toList();
      if (strings.isNotEmpty) tags[key] = strings;
    }

    addTag('Type', series['type']);
    addTag('Status', series['status']);
    addTag('Year', series['year']);
    addTag('Rating', series['contentRating']);
    addTag('Genres', series['genres']);
    addTag('Author', series['authors']);
    addTag('Artist', series['artists']);
    final score = num.tryParse(series['score']?.toString() ?? '');
    final views = int.tryParse(series['views']?.toString() ?? '');
    if (score != null && score > 0) {
      addTag('评分', '${score.toStringAsFixed(1)} / 5');
    }
    if (views != null) {
      addTag('浏览次数', NumberFormat.decimalPattern().format(views));
    }

    final info = ComicInfoData(
      title: series['title']?.toString() ?? '',
      subTitle: [
        series['type'],
        series['status'],
        if (score != null && score > 0) '评分 ${score.toStringAsFixed(1)} / 5',
        if (views != null) '浏览 ${NumberFormat.decimalPattern().format(views)}',
      ].whereType<Object>().join(' · '),
      cover: _absoluteUrl(series['coverUrl']?.toString() ?? ''),
      description: series['synopsis']?.toString(),
      tags: tags,
      chapters: chapters,
      sourceKey: ComicType.hiperdex.name,
      comicId: id,
    );
    await DiskCache.writeModel('hiperdex-info-v2-$id', info.toMap());
    return Res(info);
  },
  loadComicPages: (id, chapterId) async {
    if (chapterId == null) {
      return const Res<List<String>>.error('Chapter ID is required');
    }
    return HiperdexNetwork.instance.getChapterPages(id, chapterId);
  },
  getImageLoadingConfig: (url, comicId, epId) => ImageConfig(
    url: url,
    headers: HiperdexNetwork.imageHeaders,
  ),
  getThumbnailLoadingConfig: (url) => ImageConfig(
    url: url,
    headers: HiperdexNetwork.imageHeaders,
  ),
);

/// 复用通用漫画卡片，并保持 HiperDEX 的历史、收藏和菜单来源标识。
class _HiperdexComicTile extends CustomComicTile {
  const _HiperdexComicTile(super.comic, {super.addonMenuOptions});

  @override
  ComicType get comicType => ComicType.hiperdex;

  HiperdexComic get _data => comic as HiperdexComic;

  @override
  String get description {
    final credits = [
      if (_data.authors.isNotEmpty) '作者：${_data.authors.join('、')}',
      if (_data.artists.isNotEmpty) '画师：${_data.artists.join('、')}',
    ];
    return credits.isEmpty ? comic.description : credits.join(' · ');
  }

  @override
  Widget? buildSubDescription(BuildContext context) {
    final items = [
      if (_data.score != null && _data.score! > 0)
        '评分 ${_data.score!.toStringAsFixed(1)} / 5',
      if (_data.views != null)
        '浏览 ${NumberFormat.decimalPattern().format(_data.views)}',
      if (_data.latestChapter != null) '第 ${_data.latestChapter} 章',
    ];
    if (items.isEmpty) return null;
    return Text(
      items.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 合并旧探索页设置，保留原位置和用户启用状态。
void migrateHiperdexExplorePages() {
  final pages = appdata.appSettings.explorePages;
  const oldTitles = {'HiperDEX 最新更新', 'HiperDEX 热门'};
  // 仅迁移明确带来源前缀的旧配置，避免影响其他漫画源同名页面。
  if (!pages.any(
    (title) => oldTitles.contains(title) && title.startsWith('HiperDEX '),
  )) {
    return;
  }
  final migrated = <String>[];
  for (final title in pages) {
    final next = title == 'HiperDEX 最新更新' || title == 'HiperDEX 热门'
        ? 'HiperDEX'
        : title;
    if (!migrated.contains(next)) migrated.add(next);
  }
  appdata.appSettings.explorePages = migrated;
  appdata.updateSettings();
}

String _absoluteUrl(String url) {
  if (url.isEmpty || url.startsWith('http')) return url;
  return '${HiperdexNetwork.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
}

Map<String, String> _decodeOptions(List<String> options) {
  if (options.isEmpty) return {};
  try {
    final decoded = jsonDecode(options.first);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value.toString()));
    }
  } catch (_) {
    // Ignore invalid or old search-option state.
  }
  return {};
}

class _HiperdexSearchOptions extends StatefulWidget {
  const _HiperdexSearchOptions({
    required this.initialValues,
    required this.onChanged,
  });

  final List<String> initialValues;
  final void Function(List<String>) onChanged;

  @override
  State<_HiperdexSearchOptions> createState() => _HiperdexSearchOptionsState();
}

class _HiperdexSearchOptionsState extends State<_HiperdexSearchOptions> {
  late final Map<String, String> _filters;
  late final TextEditingController _yearController;
  late final Future<Res<List<String>>> _genresFuture;

  @override
  void initState() {
    super.initState();
    _filters = Map.of(_decodeOptions(widget.initialValues));
    _filters.putIfAbsent('sort', () => 'relevance');
    _yearController = TextEditingController(text: _filters['year'] ?? '');
    _genresFuture = HiperdexNetwork.instance.getGenres();
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _setFilter(String key, String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        _filters.remove(key);
      } else {
        _filters[key] = value;
      }
    });
    widget.onChanged([jsonEncode(_filters)]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown('排序', 'sort', const {
          'relevance': '相关度',
          'popular': '人气',
          'score': '评分',
          'recent': '最近更新',
          'newest': '最新上架',
          'oldest': '最早上架',
          'alphabetical': 'A-Z',
        }),
        _dropdown('类型', 'type', const {
          '': '全部',
          'manga': 'Manga',
          'manhwa': 'Manhwa',
          'manhua': 'Manhua',
          'novel': 'Novel',
          'webtoon': 'Webtoon',
          'one_shot': 'One Shot',
        }),
        _dropdown('状态', 'status', const {
          '': '全部',
          'ongoing': '连载中',
          'completed': '已完结',
          'hiatus': '暂停',
          'cancelled': '已取消',
        }),
        _dropdown('内容分级', 'contentRating', const {
          '': '全部',
          'safe': 'Safe',
          'suggestive': 'Suggestive',
          'erotica': 'Erotica',
          'pornographic': 'Pornographic',
        }),
        FutureBuilder<Res<List<String>>>(
          future: _genresFuture,
          builder: (context, snapshot) {
            final genres = snapshot.data?.dataOrNull ?? const <String>[];
            if (genres.isEmpty) return const SizedBox.shrink();
            return _dropdown('题材', 'genre', {
              '': '全部',
              for (final genre in genres) genre: genre,
            });
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: _yearController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '年份',
              hintText: '例如 2026',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => _setFilter('year', value.trim()),
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String label, String key, Map<String, String> choices) {
    final value = _filters[key];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: choices.containsKey(value) ? value : choices.keys.first,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final entry in choices.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => _setFilter(key, value),
      ),
    );
  }
}

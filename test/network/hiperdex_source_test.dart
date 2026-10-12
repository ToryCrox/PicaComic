import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/built_in/hiperdex.dart';
import 'package:pica_comic/network/hiperdex_network/hiperdex_main_network.dart';
import 'package:pica_comic/network/res.dart';

class _FakeHiperdexNetwork extends HiperdexNetwork {
  @override
  Future<Res<List<String>>> getGenres() async => Res(['Fantasy']);
}

/// 覆盖站点不同列表响应字段和筛选初始状态的回归场景。
void main() {
  test('最新章节响应保留漫画 ID、封面、评分和最新章节', () {
    final comic = HiperdexComic.fromMap({
      'seriesSlug': 'sample-series',
      'seriesTitle': 'Sample Series',
      'seriesCoverUrl': 'https://example.com/cover.webp',
      'seriesStatus': 'ongoing',
      'score': 4.5,
      'chapters': [
        {'id': 123, 'number': 12.5},
      ],
    });
    expect(comic.id, 'sample-series');
    expect(comic.cover, 'https://example.com/cover.webp');
    expect(comic.score, 4.5);
    expect(comic.latestChapter, '12.5');
  });

  test('目录元数据经过磁盘序列化后仍保留作者、画师和浏览次数', () {
    final comic = HiperdexComic.fromMap({
      'slug': 'sample-series',
      'title': 'Sample Series',
      'type': 'manga',
      'status': 'completed',
      'year': 2023,
      'score': 4.8387,
      'views': 6152850,
      'genres': ['Fantasy'],
      'contentRating': 'suggestive',
      'authors': ['Writer'],
      'artists': ['Artist'],
    });
    final restored = HiperdexComic.fromMap(
      jsonDecode(jsonEncode(comic.toJson())) as Map<String, dynamic>,
    );
    expect(restored.authors, ['Writer']);
    expect(restored.artists, ['Artist']);
    expect(restored.views, 6152850);
    expect(restored.score, 4.8387);
    expect(restored.tags, containsAll(['Fantasy', 'suggestive']));
    expect(restored.subTitle, contains('2023'));
  });

  for (final options in <List<String>>[
    const [],
    const ['invalid JSON'],
    const ['{"sort":"unsupported"}'],
  ]) {
    testWidgets('空或损坏筛选设置可以正常显示和修改：$options', (tester) async {
      List<String>? updated;
      final network = _FakeHiperdexNetwork();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [hiperdexNetworkProvider.overrideWithValue(network)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) =>
                    hiperdex.searchPageData!.customOptionsBuilder!(
                      context,
                      options,
                      (values) => updated = values,
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('相关度'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('评分').last);
      await tester.pumpAndSettle();
      expect(jsonDecode(updated!.single)['sort'], 'score');
      expect(tester.takeException(), isNull);
    });
  }
}

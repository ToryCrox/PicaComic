import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/download/download_providers.dart';

void main() {
  late String originalSortSetting;

  setUp(() {
    originalSortSetting = appdata.settings[26];
    appdata.settings[26] = '00';
  });

  tearDown(() {
    appdata.settings[26] = originalSortSetting;
  });

  test('无筛选列表复用全局排序结果和摘要', () async {
    final comics = [
      _buildComic(id: 'first', time: 1, size: 512),
      _buildComic(id: 'third', time: 3, size: 512),
      _buildComic(id: 'second', time: 2, size: 512),
    ];
    final container = ProviderContainer(
      overrides: [
        allDownloadedComicsProvider.overrideWith(
          () => _FakeAllDownloadedComics(comics),
        ),
      ],
    );
    addTearDown(container.dispose);

    final sorted = await container.read(sortedDownloadedComicsProvider.future);
    final sortedAgain = await container.read(
      sortedDownloadedComicsProvider.future,
    );
    final pageComics = await container.read(
      filteredComicsProvider('test-page').future,
    );
    final summary = await container.read(
      downloadedComicsSummaryProvider('test-page').future,
    );

    expect(sorted.map((comic) => comic.id), ['third', 'second', 'first']);
    expect(identical(sorted, sortedAgain), isTrue);
    expect(identical(sorted, pageComics), isTrue);
    expect(summary, '(3, 1.50GB)');
  });
}

LocalDownloadedItem _buildComic({
  required String id,
  required int time,
  required double size,
}) {
  final comic = LocalDownloadedItem(
    comicSize: size,
    downloadedEps: const [],
    id: id,
    name: id,
    subTitle: '',
    tags: const [],
    repositoryName: 'test',
  );
  comic.time = DateTime.fromMillisecondsSinceEpoch(time);
  return comic;
}

class _FakeAllDownloadedComics extends AllDownloadedComics {
  _FakeAllDownloadedComics(this.comics);

  final List<DownloadedItem> comics;

  @override
  Future<List<DownloadedItem>> build() async => comics;
}

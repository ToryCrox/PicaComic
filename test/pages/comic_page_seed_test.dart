import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/network/picacg_network/picacg_download_model.dart';
import 'package:pica_comic/pages/comic_page/comic_page_seed.dart';

void main() {
  group('ComicPageSeed', () {
    test('从下载记录提取展示字段', () {
      final item = DownloadedComic(
        const ComicItem(
          id: '100',
          title: '测试漫画',
          author: '作者A',
          tags: ['标签1', '标签2'],
        ),
        ['第1话', '第2话'],
        12.5,
        [0, 1],
      );

      final seed = ComicPageSeed.fromDownloadedItem(item, heroTag: 'tag-1');

      expect(seed.title, '测试漫画');
      expect(seed.subTitle, '作者A');
      expect(seed.heroTag, 'tag-1');
      expect(seed.eps, ['第1话', '第2话']);
      expect(seed.downloadedEps, [0, 1]);
      expect(seed.tags, ['标签1', '标签2']);
      expect(seed.isDownloaded, isTrue);
      // 未绑定下载管理器时取不到封面路径，退化即可，不应抛异常。
      expect(seed.coverPath, isNull);
      expect(seed.cover, isNull);
      expect(seed.download, same(item));
      expect(seed.hasDetailSource, isTrue);
    });

    test('只带卡片信息时也能提供首帧内容', () {
      const seed = ComicPageSeed(
        title: '标题',
        cover: 'https://example.com/cover.jpg',
        heroTag: 'hero',
        pagesCount: 42,
      );

      expect(seed.isEmpty, isFalse);
      expect(seed.hasDetailSource, isFalse);
      expect(seed.pagesCount, 42);
    });

    test('空种子视为无内容', () {
      expect(const ComicPageSeed().isEmpty, isTrue);
    });
  });
}

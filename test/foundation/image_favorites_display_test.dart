import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/image_favorites.dart';
import 'package:pica_comic/foundation/image_favorites_display.dart';

/// 创建可自由组合来源和章节元数据的收藏。
ImageFavorite favorite(
  String id, {
  String source = 'test',
  int ep = 1,
  int page = 1,
  Map<String, dynamic> other = const {},
}) => ImageFavorite(
  sourceKey: source,
  comicId: id,
  title: '同名漫画',
  ep: ep,
  page: page,
  imagePath: '',
  otherInfo: other,
);

void main() {
  test('作品最近收藏优先，作品内按章节及数字页码排列，不改变输入', () {
    final a3 = favorite('a', ep: 2, page: 3);
    final b = favorite('b');
    final a10 = favorite('a', page: 10);
    final a2 = favorite('a', page: 2);
    final input = [a3, b, a10, a2];
    expect(sortImageFavorites(input), [a2, a10, a3, b]);
    expect(input, [a3, b, a10, a2]);
    expect(sortImageFavorites(input, reversed: true), [b, a3, a10, a2]);
    final b2 = favorite('b', page: 2);
    expect(sortImageFavorites([...input, b2]), [b, b2, a2, a10, a3]);
  });

  test('同名作品按来源和漫画 ID 分组，并使用最近收藏记录作为入口', () {
    final a = favorite('same', source: 'jm');
    final b = favorite('same', source: 'picacg');
    final c = favorite('different', source: 'jm');
    final latestA = favorite('same', source: 'jm', page: 2);
    expect(groupImageFavorites([a, b, c, latestA]), [latestA, c, b]);
    expect(sortImageFavorites([a, b, c, latestA]), [a, latestA, c, b]);
    expect(groupImageFavorites([]), isEmpty);
    expect(sortImageFavorites([]), isEmpty);
  });

  test('新章节名优先，旧 JM、哔咔和自定义目录均能读取章节名', () {
    expect(
      favorite(
        'a',
        other: {
          'hasEp': true,
          'chapterName': ' 最新章节\n名称 ',
          'eps': {'1': '旧名'},
        },
      ).chapterName,
      '最新章节 名称',
    );
    expect(
      favorite(
        'a',
        source: 'jm',
        ep: 2,
        other: {
          'eps': ['100', '200'],
          'jmEpNames': ['第一话', '第二话'],
        },
      ).chapterName,
      '第二话',
    );
    expect(
      favorite(
        'a',
        source: 'picacg',
        other: {
          'eps': ['第一话'],
        },
      ).chapterName,
      '第一话',
    );
    expect(
      favorite(
        'a',
        other: {
          'eps': {'100': '第一话'},
        },
      ).chapterName,
      '第一话',
    );
    expect(
      favorite(
        'a',
        source: 'jm',
        other: {
          'eps': ['100'],
        },
      ).chapterName,
      isNull,
    );
  });

  test('明确无章节的来源不生成章节，标记覆盖旧目录', () {
    for (final source in ['ehentai', 'hitomi', 'htmanga', 'nhentai']) {
      expect(
        favorite(
          'a',
          source: source,
          ep: 2,
          other: {
            'eps': ['unexpected'],
          },
        ).hasChapters,
        isFalse,
      );
    }
    expect(favorite('a', source: 'jm').hasChapters, isTrue);
    expect(
      favorite(
        'a',
        other: {
          'hasEp': false,
          'eps': ['one'],
        },
      ).hasChapters,
      isFalse,
    );
    expect(favorite('a', other: {'hasEp': true}).hasChapters, isTrue);
    expect(favorite('a', ep: 2).hasChapters, isTrue);
    expect(favorite('a').hasChapters, isFalse);
  });

  test('损坏的章节元数据与越界索引安全回退', () {
    for (final ep in [-1, 0, 3]) {
      expect(
        favorite(
          'a',
          ep: ep,
          other: {
            'chapterName': 123,
            'eps': {'1': '第一话'},
            'jmEpNames': [null],
            'chapterStep': 1.0,
          },
        ).chapterName,
        isNull,
      );
    }
    expect(
      favorite(
        'a',
        other: {'eps': 123, 'jmEpNames': true, 'chapterStep': 'invalid'},
      ).chapterStep,
      1,
    );
    expect(
      favorite(
        'a',
        other: {
          'eps': {'1': 123},
        },
      ).chapterName,
      isNull,
    );
  });

  test('HiperDEX 反向目录保持章节阅读顺序和章内页码顺序', () {
    final other = <String, dynamic>{
      'eps': {'3|c': '第三话', '2|b': '第二话', '1|a': '第一话'},
    };
    final newest = favorite('a', source: 'hiperdex', other: other);
    final firstPage2 = favorite(
      'a',
      source: 'hiperdex',
      ep: 3,
      page: 2,
      other: other,
    );
    final firstPage1 = favorite('a', source: 'hiperdex', ep: 3, other: other);
    expect(newest.chapterStep, -1);
    expect(sortImageFavorites([firstPage2, firstPage1, newest]), [
      firstPage1,
      firstPage2,
      newest,
    ]);
    expect(
      favorite(
        'a',
        source: 'hiperdex',
        other: {
          'eps': {'1|a': '第一话', '2|b': '第二话'},
        },
      ).chapterStep,
      1,
    );
    expect(
      favorite(
        'a',
        source: 'hiperdex',
        other: {'chapterStep': 1, ...other},
      ).chapterStep,
      1,
    );
    expect(
      favorite(
        'a',
        source: 'hiperdex',
        other: {
          'eps': {'invalid': '未知'},
        },
      ).chapterStep,
      -1,
    );
  });
}

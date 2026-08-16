import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:pica_comic/pages/download/translation_result_replacer.dart';

void main() {
  group('TranslationResultReplacer', () {
    late Directory temporaryDirectory;
    late Directory comicDirectory;
    late TranslationResultReplacer replacer;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'pica-comic-translation-result-',
      );
      comicDirectory = Directory(path.join(temporaryDirectory.path, 'comic'));
      await comicDirectory.create();
      replacer = TranslationResultReplacer();
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('按同级目录匹配多个章节，允许译图后缀变化', () async {
      final chapterOne = Directory(path.join(comicDirectory.path, '1'));
      final chapterTwo = Directory(path.join(comicDirectory.path, '2'));
      await chapterOne.create();
      await chapterTwo.create();
      await _writeImage(path.join(chapterOne.path, '1.webp'), '原图一');
      await _writeImage(path.join(chapterTwo.path, '1.jpg'), '原图二');
      await _writeImage(path.join(chapterOne.path, 'result', '1.png'), '译图一');
      await _writeImage(path.join(chapterTwo.path, 'result', '1.png'), '译图二');

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );

      expect(plan.resultDirectories, hasLength(2));
      expect(plan.pairs, hasLength(2));
      expect(plan.unmatched, isEmpty);
      expect(
        plan.pairs.map((pair) => pair.destinationPath),
        containsAll(<String>[
          path.join(chapterOne.path, '1.png'),
          path.join(chapterTwo.path, '1.png'),
        ]),
      );

      final summary = await replacer.apply(plan);
      expect(summary.successCount, 2);
      expect(summary.failureCount, 0);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await File(path.join(chapterOne.path, '1.webp')).exists(),
        isFalse,
      );
      expect(await File(path.join(chapterTwo.path, '1.jpg')).exists(), isFalse);
      expect(
        await File(path.join(chapterOne.path, '1.png')).readAsString(),
        '译图一',
      );
      expect(
        await File(path.join(chapterTwo.path, '1.png')).readAsString(),
        '译图二',
      );
      expect(
        await Directory(path.join(chapterOne.path, 'result')).exists(),
        isFalse,
      );
      expect(
        await Directory(path.join(chapterTwo.path, 'result')).exists(),
        isFalse,
      );
    });

    test('按漫画目录名扫描自定义结果目录并匹配镜像路径', () async {
      final sourceChapter = Directory(
        path.join(comicDirectory.path, '1', 'translated'),
      );
      await sourceChapter.create(recursive: true);
      await _writeImage(path.join(sourceChapter.path, '1.webp'), '原图');

      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      final translationChapter = Directory(
        path.join(
          translationRoot.path,
          path.basename(comicDirectory.path),
          '1',
          'translated',
        ),
      );
      await _writeImage(path.join(translationChapter.path, '1.png'), '译图');
      await File(
        path.join(comicDirectory.path, 'manga_translator_work', 'data.tmp'),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );

      expect(plan.pairs, hasLength(1));
      expect(
        plan.pairs.single.originalPath,
        path.join(sourceChapter.path, '1.webp'),
      );
      expect(
        plan.pairs.single.translatedPath,
        path.join(translationChapter.path, '1.png'),
      );

      final summary = await replacer.apply(plan);
      expect(summary.successCount, 1);
      expect(
        await File(path.join(sourceChapter.path, '1.png')).readAsString(),
        '译图',
      );
      expect(
        await File(path.join(translationChapter.path, '1.png')).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(comicDirectory.path, 'manga_translator_work'),
        ).exists(),
        isFalse,
      );
    });

    test('自定义结果目录根层图片可以直接匹配原漫画根层图片', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      final translationComic = Directory(
        path.join(translationRoot.path, path.basename(comicDirectory.path)),
      );
      await _writeImage(path.join(translationComic.path, '1.png'), '译图');

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );

      expect(plan.pairs, hasLength(1));
      expect(
        plan.pairs.single.destinationPath,
        path.join(comicDirectory.path, '1.png'),
      );
    });

    test('同时扫描旧 result 与自定义结果目录', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图一');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图一',
      );
      final customSourceChapter = Directory(
        path.join(comicDirectory.path, '2'),
      );
      await customSourceChapter.create();
      await _writeImage(path.join(customSourceChapter.path, '2.webp'), '原图二');

      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      final translationChapter = Directory(
        path.join(
          translationRoot.path,
          path.basename(comicDirectory.path),
          '2',
        ),
      );
      await _writeImage(path.join(translationChapter.path, '2.jpg'), '译图二');

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );

      expect(plan.pairs, hasLength(2));
      expect(plan.pairs.map((pair) => pair.baseName), containsAll(['1', '2']));
    });

    test('只使用与原漫画同名的自定义结果目录', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      await _writeImage(
        path.join(translationRoot.path, 'another-comic', '1.png'),
        '错误译图',
      );

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );

      expect(plan.pairs, isEmpty);
    });

    test('批量扫描返回可替换译图摘要', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图',
      );
      final otherComic = Directory(
        path.join(temporaryDirectory.path, 'other-comic'),
      );
      await otherComic.create();

      final result = await replacer.scanAvailability([
        comicDirectory.path,
        otherComic.path,
      ]);

      expect(result.keys, contains(comicDirectory.path));
      expect(result[comicDirectory.path]?.pairCount, 1);
      expect(result[otherComic.path], isNull);
    });

    test('预览计划按图片文件名的自然顺序排列', () async {
      for (final name in ['1', '2', '10']) {
        await _writeImage(path.join(comicDirectory.path, '$name.webp'), '原图');
        await _writeImage(
          path.join(comicDirectory.path, 'result', '$name.png'),
          '译图',
        );
      }

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );

      expect(plan.pairs.map((pair) => pair.baseName), ['1', '2', '10']);
    });

    test('存在未匹配图片时保留 result 与中间目录', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图',
      );
      await _writeImage(
        path.join(comicDirectory.path, 'result', 'extra.png'),
        '多余译图',
      );
      await File(
        path.join(comicDirectory.path, 'inpainted', 'data.tmp'),
      ).create(recursive: true);
      await File(
        path.join(comicDirectory.path, 'mask', 'data.tmp'),
      ).create(recursive: true);
      await File(
        path.join(comicDirectory.path, 'manga_translator_work', 'data.tmp'),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );
      final summary = await replacer.apply(plan);

      expect(plan.pairs, hasLength(1));
      expect(plan.unmatched, hasLength(1));
      expect(summary.successCount, 1);
      expect(summary.intermediateDirectoriesCleaned, isFalse);
      expect(
        await File(path.join(comicDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(
        await File(
          path.join(comicDirectory.path, 'result', 'extra.png'),
        ).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'inpainted')).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'mask')).exists(),
        isTrue,
      );
    });

    test('未匹配原图不阻止清理中间目录', () async {
      await _writeImage(path.join(comicDirectory.path, '0.webp'), '待替换原图');
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '无需翻译原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '0.png'),
        '译图',
      );
      await File(
        path.join(comicDirectory.path, 'inpainted', 'data.tmp'),
      ).create(recursive: true);
      await File(
        path.join(comicDirectory.path, 'mask', 'data.tmp'),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );
      final summary = await replacer.apply(plan);

      expect(plan.pairs, hasLength(1));
      expect(plan.unmatched, hasLength(1));
      expect(plan.unmatched.single.isOriginal, isTrue);
      expect(summary.successCount, 1);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await Directory(path.join(comicDirectory.path, 'result')).exists(),
        isFalse,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'inpainted')).exists(),
        isFalse,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'mask')).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(comicDirectory.path, 'manga_translator_work'),
        ).exists(),
        isFalse,
      );
    });

    test('忽略中间目录内嵌套的 result，避免误覆盖', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'inpainted', 'result', '1.png'),
        '不应使用的译图',
      );
      await _writeImage(
        path.join(
          comicDirectory.path,
          'manga_translator_work',
          'result',
          '1.png',
        ),
        '不应使用的工作文件',
      );

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );

      expect(plan.pairs, isEmpty);
      expect(
        await replacer.hasReplacementCandidate(comicDirectory.path),
        isFalse,
      );
    });
  });
}

Future<void> _writeImage(String filePath, String contents) async {
  await File(filePath).create(recursive: true);
  await File(filePath).writeAsString(contents);
}

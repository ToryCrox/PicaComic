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
    });

    test('忽略中间目录内嵌套的 result，避免误覆盖', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'inpainted', 'result', '1.png'),
        '不应使用的译图',
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

import 'dart:convert';
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

    test('自定义结果目录优先，不扫描旧 result', () async {
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

      expect(plan.pairs, hasLength(1));
      expect(plan.pairs.single.baseName, '2');
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

    test('自定义结果目录为空时默认不回退旧 result，右键可扫描旧 result', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '旧译图',
      );
      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      await Directory(
        path.join(translationRoot.path, path.basename(comicDirectory.path)),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );
      expect(plan.pairs, isEmpty);

      final rightClickPlan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
        scanLegacyResultDirectories: true,
      );
      expect(rightClickPlan.pairs, hasLength(1));
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

    test('替换完成后递归删除 result 中的其它文件', () async {
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
        isFalse,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'result')).exists(),
        isFalse,
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

    test('应用时删除跳过项目并清理整个翻译结果目录', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图一');
      await _writeImage(path.join(comicDirectory.path, '2.webp'), '原图二');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图一',
      );
      await _writeImage(
        path.join(comicDirectory.path, 'result', '2.png'),
        '译图二',
      );

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );
      final skippedPair = plan.pairs.firstWhere((pair) => pair.baseName == '1');
      final activePlan = TranslationReplacementPlan(
        comicDirectory: plan.comicDirectory,
        resultDirectories: plan.resultDirectories,
        pairs: plan.pairs.where((pair) => pair != skippedPair).toList(),
        unmatched: plan.unmatched,
      );

      final summary = await replacer.apply(
        activePlan,
        skippedPairs: [skippedPair],
      );

      expect(summary.successCount, 1);
      expect(
        await File(path.join(comicDirectory.path, '1.webp')).exists(),
        isTrue,
      );
      expect(
        await File(path.join(comicDirectory.path, 'result', '1.png')).exists(),
        isFalse,
      );
      expect(
        await File(path.join(comicDirectory.path, '2.webp')).exists(),
        isFalse,
      );
      expect(
        await File(path.join(comicDirectory.path, '2.png')).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'result')).exists(),
        isFalse,
      );
    });

    test('Manga Translator 无文本页面默认跳过，并支持混合替换', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图一');
      await _writeImage(path.join(comicDirectory.path, '2.webp'), '原图二');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图一',
      );
      await _writeImage(
        path.join(comicDirectory.path, 'result', '2.png'),
        '译图二',
      );
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '1',
        regions: const [],
      );
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '2',
        regions: const [
          {'text': '可翻译文本'},
        ],
      );

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );
      final skippedPair = plan.pairs.firstWhere((pair) => pair.baseName == '1');
      final activePlan = TranslationReplacementPlan(
        comicDirectory: plan.comicDirectory,
        resultDirectories: plan.resultDirectories,
        pairs: plan.pairs
            .where((pair) => pair != skippedPair)
            .toList(growable: false),
        unmatched: plan.unmatched,
      );

      expect(skippedPair.defaultSkipped, isTrue);
      expect(skippedPair.defaultSkipReason, '未检测到可翻译文本，已默认跳过');
      expect(plan.defaultSkippedOriginalPaths, {skippedPair.originalPath});
      expect(
        plan.pairs.firstWhere((pair) => pair.baseName == '2').defaultSkipped,
        isFalse,
      );

      final summary = await replacer.apply(
        activePlan,
        skippedPairs: [skippedPair],
      );

      expect(summary.successCount, 1);
      expect(summary.failureCount, 0);
      expect(
        await File(path.join(comicDirectory.path, '1.webp')).exists(),
        isTrue,
      );
      expect(
        await File(path.join(comicDirectory.path, '2.webp')).exists(),
        isFalse,
      );
      expect(
        await File(path.join(comicDirectory.path, '2.png')).readAsString(),
        '译图二',
      );
      expect(
        await File(path.join(comicDirectory.path, 'result', '1.png')).exists(),
        isFalse,
      );
      expect(
        await Directory(
          path.join(comicDirectory.path, 'manga_translator_work'),
        ).exists(),
        isFalse,
      );
    });

    test('Manga Translator 有文本、存在去字图或元数据异常时不默认跳过', () async {
      for (final name in ['1', '2', '3', '4']) {
        await _writeImage(
          path.join(comicDirectory.path, '$name.webp'),
          '原图$name',
        );
        await _writeImage(
          path.join(comicDirectory.path, 'result', '$name.png'),
          '译图$name',
        );
      }
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '1',
        regions: const [
          {'text': '有文本'},
        ],
      );
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '2',
        regions: const [],
        createInpainted: true,
      );
      final malformedMetadata = File(
        path.join(
          comicDirectory.path,
          'manga_translator_work',
          'json',
          '3_translations.json',
        ),
      );
      await malformedMetadata.create(recursive: true);
      await malformedMetadata.writeAsString('{');

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );

      expect(plan.pairs, hasLength(4));
      expect(plan.pairs.every((pair) => !pair.defaultSkipped), isTrue);
    });

    test('Manga Translator 检测到拒译内容时保护整本漫画', () async {
      for (final name in ['1', '2', '3']) {
        await _writeImage(
          path.join(comicDirectory.path, '$name.webp'),
          '原图$name',
        );
        await _writeImage(
          path.join(comicDirectory.path, 'result', '$name.png'),
          '译图$name',
        );
      }
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '1',
        regions: const [
          {'translation': '无法翻译︓内容涉及限制内容'},
        ],
      );
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '2',
        regions: const [
          {'translation_raw': '我不能翻译该内容'},
        ],
      );
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '3',
        regions: const [
          {'translation': '正常翻译内容'},
        ],
      );
      await File(
        path.join(comicDirectory.path, 'manga_translator_work', 'data.tmp'),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );

      expect(plan.hasUntranslatableContent, isTrue);
      expect(plan.untranslatableOriginalPaths, hasLength(2));
      expect(
        plan.pairs
            .firstWhere((pair) => pair.baseName == '1')
            .hasUntranslatableContent,
        isTrue,
      );
      expect(
        plan.pairs
            .firstWhere((pair) => pair.baseName == '2')
            .hasUntranslatableContent,
        isTrue,
      );
      expect(
        plan.pairs
            .firstWhere((pair) => pair.baseName == '3')
            .hasUntranslatableContent,
        isFalse,
      );

      final summary = await replacer.apply(plan);

      expect(summary.protectedByUntranslatableContent, isTrue);
      expect(summary.protectedPairCount, 3);
      expect(summary.successCount, 0);
      expect(summary.failureCount, 0);
      expect(summary.intermediateDirectoriesCleaned, isFalse);
      for (final name in ['1', '2', '3']) {
        expect(
          await File(path.join(comicDirectory.path, '$name.webp')).exists(),
          isTrue,
        );
        expect(
          await File(
            path.join(comicDirectory.path, 'result', '$name.png'),
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            path.join(
              comicDirectory.path,
              'manga_translator_work',
              'json',
              '${name}_translations.json',
            ),
          ).exists(),
          isTrue,
        );
      }
      expect(
        await Directory(
          path.join(comicDirectory.path, 'manga_translator_work'),
        ).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'result')).exists(),
        isTrue,
      );
    });

    test('全部跳过时清理译图和翻译中间目录但不替换原图', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图',
      );
      await File(
        path.join(comicDirectory.path, 'manga_translator_work', 'data.tmp'),
      ).create(recursive: true);

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
      );
      final summary = await replacer.apply(
        TranslationReplacementPlan(
          comicDirectory: plan.comicDirectory,
          resultDirectories: plan.resultDirectories,
          pairs: const [],
          unmatched: plan.unmatched,
        ),
        skippedPairs: plan.pairs,
      );

      expect(summary.successCount, 0);
      expect(summary.failureCount, 0);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await File(path.join(comicDirectory.path, '1.webp')).exists(),
        isTrue,
      );
      expect(
        await File(path.join(comicDirectory.path, '1.png')).exists(),
        isFalse,
      );
      expect(
        await Directory(path.join(comicDirectory.path, 'result')).exists(),
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

    test('批量扫描保留选中数量并排除无结果漫画', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图',
      );
      final emptyComic = Directory(
        path.join(temporaryDirectory.path, 'empty-comic'),
      );
      await emptyComic.create();

      final batch = await replacer.prepareBatch([
        comicDirectory.path,
        emptyComic.path,
      ], includeDimensions: false);

      expect(batch.selectedCount, 2);
      expect(batch.plans, hasLength(1));
      expect(batch.noResultCount, 1);
      expect(batch.pairCount, 1);
    });

    test('批量替换单目录失败时继续处理其它目录', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图一');
      await _writeImage(
        path.join(comicDirectory.path, 'result', '1.png'),
        '译图一',
      );
      final failedComic = Directory(
        path.join(temporaryDirectory.path, 'failed-comic'),
      );
      await _writeImage(path.join(failedComic.path, '2.webp'), '原图二');
      await _writeImage(path.join(failedComic.path, 'result', '2.png'), '译图二');

      final batchPlan = await replacer.prepareBatch([
        comicDirectory.path,
        failedComic.path,
      ], includeDimensions: false);
      await File(path.join(failedComic.path, 'result', '2.png')).delete();
      final summary = await replacer.applyBatch(batchPlan);

      expect(summary.items, hasLength(2));
      expect(summary.successCount, 1);
      expect(summary.failureCount, 1);
      expect(
        await File(path.join(comicDirectory.path, '1.png')).readAsString(),
        '译图一',
      );
      expect(
        await File(path.join(failedComic.path, 'result', '2.png')).exists(),
        isFalse,
      );
    });

    test('拒译结果清理适配外部目录并保留其它映射', () async {
      await _writeImage(path.join(comicDirectory.path, '1.webp'), '原图');
      await _writeMangaTranslatorMetadata(
        comicDirectory,
        '1',
        regions: const [
          {'translation': '无法翻译该内容'},
        ],
        createInpainted: true,
      );
      final translationRoot = Directory(
        path.join(temporaryDirectory.path, 'translation-output'),
      );
      final externalComic = Directory(
        path.join(translationRoot.path, path.basename(comicDirectory.path)),
      );
      await _writeImage(path.join(externalComic.path, '1.png'), '拒译译图');
      await _writeImage(path.join(externalComic.path, 'normal.png'), '保留译图');
      await File(
        path.join(externalComic.path, 'translation_map.json'),
      ).writeAsString(jsonEncode({'1.png': '拒译', 'normal.png': '保留'}));

      final plan = await replacer.prepare(
        comicDirectory.path,
        includeDimensions: false,
        translationResultRootDirectory: translationRoot.path,
      );
      final summary = await replacer.removeUntranslatableResults(plan);

      expect(summary.deletedPairCount, 1);
      expect(
        await File(path.join(comicDirectory.path, '1.webp')).exists(),
        isTrue,
      );
      expect(
        await File(path.join(externalComic.path, '1.png')).exists(),
        isFalse,
      );
      expect(
        await File(
          path.join(
            comicDirectory.path,
            'manga_translator_work',
            'json',
            '1_translations.json',
          ),
        ).exists(),
        isFalse,
      );
      final map =
          jsonDecode(
                await File(
                  path.join(externalComic.path, 'translation_map.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(map, {'normal.png': '保留'});
    });
  });
}

Future<void> _writeImage(String filePath, String contents) async {
  await File(filePath).create(recursive: true);
  await File(filePath).writeAsString(contents);
}

Future<void> _writeMangaTranslatorMetadata(
  Directory comicDirectory,
  String baseName, {
  required List<Object?> regions,
  bool createInpainted = false,
}) async {
  final workDirectory = path.join(comicDirectory.path, 'manga_translator_work');
  final metadataFile = File(
    path.join(workDirectory, 'json', '${baseName}_translations.json'),
  );
  await metadataFile.create(recursive: true);
  await metadataFile.writeAsString(
    jsonEncode({
      '$baseName.webp': {'regions': regions},
    }),
  );
  if (createInpainted) {
    await _writeImage(
      path.join(workDirectory, 'inpainted', '${baseName}_inpainted.png'),
      '去字图',
    );
  }
}

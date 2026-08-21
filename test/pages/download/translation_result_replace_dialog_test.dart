import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/pages/download/translation_result_replace_dialog.dart';
import 'package:pica_comic/pages/download/translation_result_replace_notifier.dart';
import 'package:pica_comic/pages/download/translation_result_replacer.dart';

void main() {
  testWidgets('加载后显示分组预览和图片对比入口', (tester) async {
    const plan = TranslationReplacementPlan(
      comicDirectory: r'C:\comic',
      resultDirectories: {r'C:\comic\result'},
      pairs: [
        TranslationReplacementPair(
          originalPath: r'C:\comic\1.webp',
          translatedPath: r'C:\comic\result\1.png',
          originalSize: 1024,
          translatedSize: 2048,
        ),
      ],
      unmatched: [],
    );
    const batchPlan = TranslationReplacementBatchPlan(
      selectedCount: 1,
      plans: [plan],
    );
    final request = TranslationResultReplaceRequest(
      replacer: TranslationResultReplacer(),
      onLoad: () async => batchPlan,
      onRefresh: () async => batchPlan,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: TranslationResultReplaceDialog(
            comics: const [],
            translationResultRootDirectory: '',
            onComplete: _noop,
            request: request,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('翻译结果预览（1 个目录）'), findsOneWidget);
    expect(find.text('原图'), findsOneWidget);
    expect(find.text('翻译后'), findsOneWidget);
    expect(find.text('总页数'), findsOneWidget);
    expect(find.text('已翻译'), findsOneWidget);
    expect(find.text('文件大小'), findsOneWidget);
    expect(find.text('替换原图（1）'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.text('comic'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('原图'), findsNothing);

    await tester.tap(find.text('comic'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('原图'), findsOneWidget);
  });
}

void _noop() {}

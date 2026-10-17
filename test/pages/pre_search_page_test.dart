import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/pages/pre_search_page.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);

  testWidgets('显示漫画 ID 建议再清空输入后保留筛选，卸载时安全释放输入资源', (tester) async {
    final previous = ComicSource.sources;
    ComicSource.sources = [
      ComicSource.named(
        name: '测试来源',
        key: ComicType.picacg,
        filePath: '',
        idMatcher: RegExp(r'^\d+$'),
        searchPageData: SearchPageData.named(
          searchOptions: [
            SearchOptions(LinkedHashMap.of({'a': '选项一', 'b': '选项二'}), '排序'),
          ],
        ),
      ),
    ];
    addTearDown(() => ComicSource.sources = previous);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PreSearchPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('选项二'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField)).controller!;
    await tester.enterText(find.byType(TextField), '123');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();
    expect(input.text, isEmpty);
    final selected = tester.widget<OptionChip>(
      find.widgetWithText(OptionChip, '选项二'),
    );
    expect(selected.isSelected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(() => input.addListener(() {}), throwsFlutterError);
  });
}

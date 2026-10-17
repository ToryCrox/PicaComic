import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/user_library_events.dart';
import 'package:pica_comic/pages/settings/settings_page.dart';
import 'package:pica_comic/tools/translations.dart';

/// 隔离用户文件与 WebDAV，保留生产代码的列表通知。
class _MemoryAppdata extends Appdata {
  @override
  Future<void> writeData([bool sync = true]) async =>
      notifyUserLibraryChanged();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);

  testWidgets('添加弹窗保存后更新屏蔽词列表，删除后仍能再次添加', (tester) async {
    final previous = appdata;
    final data = _MemoryAppdata()..blockingKeyword = ['原词'];
    appdata = data;
    addTearDown(() => appdata = previous);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BlockingKeywordPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新词');
    await tester.tap(find.text('提交'.tl));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.text('新词'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, '原词'),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('原词'), findsNothing);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '原词');
    await tester.tap(find.text('提交'.tl));
    await tester.pumpAndSettle();
    expect(data.blockingKeyword, ['新词', '原词']);
    expect(find.text('原词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}

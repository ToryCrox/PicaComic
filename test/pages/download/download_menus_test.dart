import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/download/components/download_menus.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  test('多选右键菜单使用当前选中漫画', () {
    final first = _buildComic('first');
    final second = _buildComic('second');

    final targets = resolveDownloadMenuTargets(first, [first, second]);

    expect(targets, [first, second]);
  });

  test('非多选右键菜单使用右键漫画', () {
    final comic = _buildComic('comic');

    final targets = resolveDownloadMenuTargets(comic, const []);

    expect(targets, [comic]);
  });

  testWidgets('删除对话框默认删除文件', (tester) async {
    final context = await _pumpContext(tester);

    final resultFuture = showDeleteDownloadDialog(context, count: 2);
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(await resultFuture, isTrue);
  });

  testWidgets('删除对话框取消勾选时保留文件', (tester) async {
    final context = await _pumpContext(tester);

    final resultFuture = showDeleteDownloadDialog(context, count: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(await resultFuture, isFalse);
  });

  testWidgets('取消删除对话框不返回删除选项', (tester) async {
    final context = await _pumpContext(tester);

    final resultFuture = showDeleteDownloadDialog(context, count: 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(await resultFuture, isNull);
  });
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

LocalDownloadedItem _buildComic(String id) {
  return LocalDownloadedItem(
    comicSize: 1,
    downloadedEps: const [],
    id: id,
    name: id,
    subTitle: '',
    tags: const [],
    repositoryName: 'test',
  );
}

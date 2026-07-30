import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_model.dart';
import 'package:pica_comic/pages/download/components/download_tile.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  late List<String> originalSettings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  setUp(() {
    originalSettings = List<String>.from(appdata.settings);
    appdata.settings[44] = '0,1.0';
    appdata.settings[50] = 'cn';
    appdata.settings[72] = '0';
    appdata.settings[73] = '0';
  });

  tearDown(() {
    appdata.settings = originalSettings;
  });

  test('作者与文件大小合并为单行元信息', () {
    final tile = _buildTile();

    expect(tile.subTitle, isEmpty);
    expect(tile.description, 'KuruFapJikan · 7.73MB');
    expect(tile.descriptionMaxLines, 1);
  });

  testWidgets('宽卡片显示紧凑文字按钮和完整元信息', (tester) async {
    await _pumpTile(tester, width: 700);

    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('标记'), findsOneWidget);
    expect(find.text('KuruFapJikan · 7.73MB'), findsOneWidget);
    final firstTagTop = tester
        .getTopLeft(find.text('student council member'))
        .dy;
    final lastTagTop = tester.getTopLeft(find.text('ichika amasawa')).dy;
    final lastTagBottom = tester.getBottomRight(find.text('ichika amasawa')).dy;
    final buttonTop = tester.getTopLeft(find.byIcon(Icons.menu_book)).dy;
    expect(lastTagTop, greaterThan(firstTagTop));
    expect(lastTagBottom, lessThanOrEqualTo(buttonTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄卡片切换为图标按钮且不发生布局溢出', (tester) async {
    await _pumpTile(tester, width: 400);

    expect(find.text('阅读'), findsNothing);
    expect(find.text('目录'), findsNothing);
    expect(find.text('标签'), findsNothing);
    expect(find.text('标记'), findsNothing);
    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(find.byIcon(Icons.label_outline), findsOneWidget);
    expect(find.text('KuruFapJikan · 7.73MB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpTile(WidgetTester tester, {required double width}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: App.navigatorKey,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 164, child: _buildTile()),
        ),
      ),
    ),
  );
  await tester.pump();
}

DownloadedComicTile _buildTile() {
  final item = LocalDownloadedItem(
    comicSize: 7.73,
    downloadedEps: const [],
    id: 'local-test',
    name: 'Test Comic',
    subTitle: 'KuruFapJikan',
    tags: const [
      'student council member',
      'advanced nurturing school',
      'classroom of the elite',
      'ichika amasawa',
    ],
    repositoryName: 'test',
  );
  return DownloadedComicTile(
    id: item.id,
    size: '7.73',
    imagePath: File('images/app_icon.png'),
    author: item.subTitle,
    name: item.name,
    onTap: () {},
    onLongTap: () {},
    onSecondaryTap: (_) {},
    type: 'local',
    tag: item.tags,
    onRead: () {},
    onOpenFolder: () {},
    onManageTags: () {},
    isDragDisabled: true,
    downloadedItem: item,
  );
}

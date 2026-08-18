import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/pages/local_image_viewer_page.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  late List<String> originalSettings;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppTranslation.init();
  });

  setUp(() {
    originalSettings = List<String>.from(appdata.settings);
    appdata.settings[50] = 'cn';
  });

  tearDown(() {
    appdata.settings = originalSettings;
  });

  testWidgets('本地图片查看器支持按钮、方向键切换和关闭', (tester) async {
    final missingPrefix = File(
      '${Directory.systemTemp.path}/pica-comic-viewer-${DateTime.now().microsecondsSinceEpoch}',
    ).path;
    final imagePaths = List<String>.generate(
      3,
      (index) => '$missingPrefix-${index + 1}.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () => LocalImageViewerPage.open<void>(
                  context,
                  imagePath: imagePaths.first,
                  gallery: [
                    LocalImageViewerItem(
                      imagePath: imagePaths[0],
                      title: 'P1',
                      subtitle: '1/3',
                    ),
                    LocalImageViewerItem(
                      imagePath: imagePaths[1],
                      title: 'P2',
                      subtitle: '2/3',
                    ),
                    LocalImageViewerItem(
                      imagePath: imagePaths[2],
                      title: 'P3',
                      subtitle: '3/3',
                    ),
                  ],
                ),
                child: const Text('打开'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.text('P1'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('P1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('P2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('P3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('P2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('P1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('打开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地图片查看器支持底部扩展控件并随图集切换', (tester) async {
    final missingPrefix = File(
      '${Directory.systemTemp.path}/pica-comic-viewer-bottom-${DateTime.now().microsecondsSinceEpoch}',
    ).path;
    final imagePaths = List<String>.generate(
      2,
      (index) => '$missingPrefix-${index + 1}.png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () => LocalImageViewerPage.open<void>(
                  context,
                  imagePath: imagePaths.first,
                  gallery: [
                    LocalImageViewerItem(imagePath: imagePaths[0], title: 'P1'),
                    LocalImageViewerItem(imagePath: imagePaths[1], title: 'P2'),
                  ],
                  bottomBuilder: (_, item, _) => Text('扩展 ${item.title}'),
                ),
                child: const Text('打开扩展查看器'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开扩展查看器'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('扩展 P1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('扩展 P2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

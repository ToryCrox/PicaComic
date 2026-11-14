import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_chapter_group.dart';
import 'package:pica_comic/components/grouped_chapters.dart';
import 'package:pica_comic/tools/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppTranslation.init);

  testWidgets('章节悬停时背景产生轻微变化，移出后恢复', (tester) async {
    const boundaryKey = Key('chapter-surface');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: GroupedChapters(
              chapters: const {'one': '第一章'},
              groups: const [
                ComicChapterGroup(
                  id: 'group',
                  title: '目录',
                  chapterIds: ['one'],
                ),
              ],
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ink = find
        .ancestor(of: find.text('第一章'), matching: find.byType(InkWell))
        .first;
    final rect = tester.getRect(ink);
    final sample = Offset(rect.left + 10, rect.center.dy);
    Future<List<int>> pixel() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      );
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final index = (sample.dy.floor() * image!.width + sample.dx.floor()) * 4;
      final color = bytes!.buffer.asUint8List().sublist(index, index + 4);
      image.dispose();
      return color;
    }

    final before = await pixel();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(sample);
    await tester.pumpAndSettle();
    final hovered = await pixel();
    expect(hovered, isNot(equals(before)));
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(await pixel(), equals(before));
    await mouse.removePointer();
  });
}

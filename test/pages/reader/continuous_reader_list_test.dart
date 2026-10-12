import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/scrollable_list/src/scrollable_positioned_list.dart';

void main() {
  testWidgets('图片尺寸更新保持正在进行的滚动和阅读锚点', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var height = 100.0;
    Widget view() => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: ScrollablePositionedList.builder(
            scrollController: scroll,
            itemCount: 3,
            itemKeyBuilder: (i) => 'image-$i',
            maintainVisibleContentPosition: true,
            itemBuilder: (_, i) => SizedBox(
              key: ValueKey('moving-$i'),
              height: i == 0 ? height : 500,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view());
    await tester.pump();
    final motion = scroll.animateTo(
      300,
      duration: const Duration(seconds: 1),
      curve: Curves.linear,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final pixels = scroll.offset;
    final before = tester.getTopLeft(find.byKey(const ValueKey('moving-1'))).dy;
    height = 350;
    await tester.pumpWidget(view());
    await tester.pump();
    expect(scroll.position.isScrollingNotifier.value, isTrue);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('moving-1'))).dy,
      closeTo(before, 1),
    );
    await tester.pump(const Duration(seconds: 1));
    await motion;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('moving-1'))).dy,
      closeTo(before - (scroll.offset - pixels), 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('头部插入和尾部追加保持部分可见长图位置', (tester) async {
    final scroll = ScrollController();
    final controller = ItemScrollController();
    addTearDown(scroll.dispose);
    var ids = ['long', 'next'];
    Widget view() {
      final snapshot = List<String>.of(ids);
      return MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 400,
            child: ScrollablePositionedList.builder(
              scrollController: scroll,
              itemScrollController: controller,
              itemCount: snapshot.length,
              itemKeyBuilder: (i) => snapshot[i],
              maintainVisibleContentPosition: true,
              itemBuilder: (_, i) => SizedBox(
                key: ValueKey('image-${snapshot[i]}'),
                height: snapshot[i] == 'long' ? 1500 : 300,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(view());
    await tester.pump();
    scroll.jumpTo(700.25);
    await tester.pump();
    final before = tester
        .getTopLeft(find.byKey(const ValueKey('image-long')))
        .dy;
    expect(before, lessThan(0));
    ids = ['previous-1', 'previous-2', ...ids];
    await tester.pumpWidget(view());
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('image-long'))).dy,
      closeTo(before, 1),
    );
    ids = [...ids, 'chapter-3'];
    await tester.pumpWidget(view());
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('image-long'))).dy,
      closeTo(before, 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('上方图片异步高度变化不移动当前阅读图片', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var height = 100.0;
    Widget view() => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: ScrollablePositionedList.builder(
            scrollController: scroll,
            itemCount: 3,
            itemKeyBuilder: (i) => 'image-$i',
            maintainVisibleContentPosition: true,
            itemBuilder: (_, i) => SizedBox(
              key: ValueKey('picture-$i'),
              height: i == 0 ? height : 500,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view());
    await tester.pump();
    scroll.jumpTo(180);
    await tester.pump();
    final before = tester
        .getTopLeft(find.byKey(const ValueKey('picture-1')))
        .dy;
    height = 350;
    await tester.pumpWidget(view());
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('picture-1'))).dy,
      closeTo(before, 1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

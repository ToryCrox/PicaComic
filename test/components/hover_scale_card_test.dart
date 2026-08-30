import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/components/hover_scale_card.dart';

void main() {
  testWidgets('桌面悬浮时使用轻量缩放并在移出后恢复', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: HoverScaleCard(
                key: Key('card'),
                scale: 1.02,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card'))));
    await tester.pumpAndSettle();

    AnimatedScale animatedScale() {
      return tester.widget<AnimatedScale>(
        find.descendant(
          of: find.byKey(const Key('card')),
          matching: find.byType(AnimatedScale),
        ),
      );
    }

    expect(animatedScale().scale, 1.02);
    expect(animatedScale().duration, const Duration(milliseconds: 160));

    await mouse.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(animatedScale().scale, 1);
    await mouse.removePointer();
  });

  testWidgets('禁用悬浮反馈时不缩放卡片', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: HoverScaleCard(
                key: Key('card'),
                enabled: false,
                scale: 1.02,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card'))));
    await tester.pumpAndSettle();

    final animatedScale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(const Key('card')),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(animatedScale.scale, 1);
    await mouse.removePointer();
  });

  testWidgets('卡片的启用态和禁用态使用对应鼠标指针', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HoverScaleCard(
                key: Key('enabled-card'),
                child: SizedBox(width: 100, height: 60),
              ),
              HoverScaleCard(
                key: Key('disabled-card'),
                enabled: false,
                child: SizedBox(width: 100, height: 60),
              ),
            ],
          ),
        ),
      ),
    );

    final enabledRegion = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byKey(const Key('enabled-card')),
        matching: find.byType(MouseRegion),
      ),
    );
    final disabledRegion = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byKey(const Key('disabled-card')),
        matching: find.byType(MouseRegion),
      ),
    );

    expect(enabledRegion.cursor, same(appClickableMouseCursor));
    expect(disabledRegion.cursor, same(SystemMouseCursors.basic));
  });

  testWidgets('导航项使用共享指针，禁用按钮使用普通箭头', (tester) async {
    final observer = NaviObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: '首页',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
            ),
          ],
          paneActions: const [],
          pageBuilder: (_) => const SizedBox.shrink(),
          observer: observer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigationRegion = tester.widget<MouseRegion>(
      find
          .descendant(
            of: find.byKey(const ValueKey(0)),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(navigationRegion.cursor, same(appClickableMouseCursor));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Button.filled(
            disabled: true,
            onPressed: () {},
            child: const Text('禁用'),
          ),
        ),
      ),
    );
    await tester.pump();

    final disabledButtonRegion = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byType(Button),
        matching: find.byType(MouseRegion),
      ),
    );
    expect(disabledButtonRegion.cursor, same(SystemMouseCursors.basic));
  });

  testWidgets('系统要求减少动画时保留悬浮状态但不缩放', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 120,
                child: HoverScaleCard(
                  key: Key('card'),
                  scale: 1.02,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('card'))));
    await tester.pumpAndSettle();

    final animatedScale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byKey(const Key('card')),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(animatedScale.scale, 1);
    await mouse.removePointer();
  });
}

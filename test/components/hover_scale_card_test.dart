import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/components.dart';

void main() {
  testWidgets('窄屏推入返回路由与切换宽屏时，导航留白随布局派生且无构建期写入', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    final observer = NaviObserver();
    const rootKey = Key('root-padding');
    await tester.pumpWidget(
      MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: '首页',
              icon: Icons.home,
              activeIcon: Icons.home,
            ),
          ],
          paneActions: const [],
          observer: observer,
          pageBuilder: (_) => Navigator(
            key: navigator,
            observers: [observer],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) =>
                  const NaviPaddingWidget(key: rootKey, child: Text('首页')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    EdgeInsetsGeometry padding() => tester
        .widget<Padding>(
          find
              .descendant(
                of: find.byKey(rootKey, skipOffstage: false),
                matching: find.byType(Padding, skipOffstage: false),
                skipOffstage: false,
              )
              .first,
        )
        .padding;
    expect(padding(), EdgeInsets.zero);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('详情')),
    );
    await tester.pumpAndSettle();
    expect(padding(), const EdgeInsets.only(top: 48, bottom: 58));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(padding(), EdgeInsets.zero);
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(padding(), const EdgeInsets.only(top: 48, bottom: 58));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(padding(), EdgeInsets.zero);
    expect(tester.takeException(), isNull);
  });
}

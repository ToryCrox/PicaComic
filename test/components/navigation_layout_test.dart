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

  testWidgets('窄屏导航显示标签并可切换页面，放大文字时不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final observer = NaviObserver();
    var selected = 0;
    final labels = ['我的', '收藏', '探索', '分类', '下载', '本地'];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: NaviPane(
          paneItems: [
            for (final label in labels)
              PaneItemEntry(
                label: label,
                icon: Icons.book_outlined,
                activeIcon: Icons.book,
              ),
          ],
          paneActions: const [],
          observer: observer,
          onPageChange: (index) => selected = index,
          pageBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in labels) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('下载').last);
    await tester.pumpAndSettle();
    expect(selected, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏适应短窗口和放大字体，仍可滚动使用工具入口', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var actionCalled = false;
    var selected = 0;
    final observer = NaviObserver();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: NaviPane(
          paneItems: [
            for (final label in ['我的', '收藏', '探索', '分类', '下载', '本地'])
              PaneItemEntry(
                label: label,
                icon: Icons.book_outlined,
                activeIcon: Icons.book,
              ),
          ],
          paneActions: [
            PaneActionEntry(label: '搜索', icon: Icons.search, onTap: () {}),
            PaneActionEntry(label: '主题设置', icon: Icons.palette, onTap: () {}),
            PaneActionEntry(
              label: '设置',
              icon: Icons.settings,
              onTap: () => actionCalled = true,
            ),
          ],
          observer: observer,
          onPageChange: (index) => selected = index,
          pageBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('探索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('探索'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    await tester.ensureVisible(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    expect(actionCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠侧栏显示提示并能切换导航项', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: '首页',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
            ),
            PaneItemEntry(
              label: '收藏',
              icon: Icons.bookmark_outline,
              activeIcon: Icons.bookmark,
            ),
          ],
          paneActions: [
            PaneActionEntry(label: '设置', icon: Icons.settings, onTap: () {}),
          ],
          observer: NaviObserver(),
          onPageChange: (index) => selected = index,
          pageBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧边导航栏只显示图标，宽度收窄且没有展开按钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: '首页',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
            ),
            PaneItemEntry(
              label: '收藏',
              icon: Icons.bookmark_outline,
              activeIcon: Icons.bookmark,
            ),
          ],
          paneActions: [
            PaneActionEntry(label: '设置', icon: Icons.settings, onTap: () {}),
          ],
          observer: NaviObserver(),
          onPageChange: (index) => selected = index,
          pageBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 只显示图标：侧栏宽度 64，名称放在 Tooltip 里。
    final rail = find.byType(NavigationRail);
    expect(tester.getSize(rail).width, 64);
    expect(find.byTooltip('首页'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    // 没有展开/收起按钮。
    expect(find.byType(IconButton), findsNothing);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}

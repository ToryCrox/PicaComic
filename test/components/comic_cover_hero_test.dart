import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/comic_cover_hero.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app_page_route.dart';
import 'package:pica_comic/foundation/def.dart';

/// 提供同一漫画的重复卡片，模拟推荐列表中的重复条目。
class _TestTile extends ComicTile {
  const _TestTile(this.color);
  final Color color;

  @override
  String get title => '漫画';
  @override
  String get subTitle => '';
  @override
  String get description => '';
  @override
  String get comicID => 'same';
  @override
  ComicType get comicType => ComicType.jm;
  @override
  bool get showDownload => false;
  @override
  bool get showRead => false;
  @override
  bool get showFavorite => false;
  @override
  Widget get image => ColoredBox(key: ValueKey(color), color: color);

  @override
  void onTapWithRef(WidgetRef ref) {
    Navigator.of(ref.context).push(
      AppPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: Hero(
              tag: comicCoverHeroTag(ComicType.jm, 'same'),
              flightShuttleBuilder: comicCoverFlightShuttle,
              child: const SizedBox(
                width: 100,
                height: 140,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('重复漫画只让点击的封面参与往返 Hero，加载中仍显示原封面', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: 180, child: _TestTile(Colors.red)),
                SizedBox(height: 180, child: _TestTile(Colors.blue)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(_TestTile).last);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey<Color>(Colors.blue)), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsWidgets);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const ValueKey<Color>(Colors.blue)), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(_TestTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

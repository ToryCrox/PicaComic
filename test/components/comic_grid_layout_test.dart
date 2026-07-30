import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';

void main() {
  late String originalSetting;

  setUp(() {
    originalSetting = appdata.settings[44];
  });

  tearDown(() {
    appdata.settings[44] = originalSetting;
  });

  test('相同漫画网格配置不触发重新布局', () {
    appdata.settings[44] = '0,1.0';

    final previous = SliverGridDelegateWithComics();
    final current = SliverGridDelegateWithComics();

    expect(current.shouldRelayout(previous), isFalse);
  });

  test('显示模式或缩放变化时触发重新布局', () {
    appdata.settings[44] = '0,1.0';
    final detailed = SliverGridDelegateWithComics();

    appdata.settings[44] = '1,1.0';
    final brief = SliverGridDelegateWithComics();
    expect(brief.shouldRelayout(detailed), isTrue);

    final scaled = SliverGridDelegateWithComics(true, '1.1');
    expect(scaled.shouldRelayout(brief), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/tools/tags_translation.dart';

void main() {
  group('标签翻译分隔符解析', () {
    test('标题中的无空格竖线不会触发越界', () {
      expect('标题A|标题B'.translateTagsToCN, '标题A|标题B');
    });

    test('标签中的不规则竖线不会触发越界', () {
      expect('artist:foo|bar'.translateTagsToCN, 'artist:foo|bar');
    });
  });
}

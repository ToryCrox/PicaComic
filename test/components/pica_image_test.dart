import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/components.dart';

void main() {
  test('漫画缩略图按实际物理宽度分档解码', () {
    expect(PicaImage.calculateThumbnailCacheWidth(150, 2), 320);
    expect(PicaImage.calculateThumbnailCacheWidth(192, 1), 192);
  });

  test('漫画缩略图解码宽度限制在合理范围', () {
    expect(PicaImage.calculateThumbnailCacheWidth(1, 1), 64);
    expect(PicaImage.calculateThumbnailCacheWidth(800, 2), 1024);
  });
}

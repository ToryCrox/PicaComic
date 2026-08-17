import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/tools/image_size_getter.dart';

void main() {
  test('ImageSizeUtils 可以读取并复用图片尺寸缓存', () async {
    final file = File('images/app_icon.png');
    final first = await ImageSizeUtils.parseImageSize(file.path);
    final batch = await ImageSizeUtils.parseImageSizes([file.path]);

    expect(first, isNotNull);
    expect(first!.width, greaterThan(0));
    expect(first.height, greaterThan(0));
    expect(first.fileSize, await file.length());
    expect(batch[file.path], isNotNull);
    expect(batch[file.path]!.width, first.width);
    expect(batch[file.path]!.height, first.height);
  });
}

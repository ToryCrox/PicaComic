import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';

/// 显式设置 PICA_MANHUAGUI_LIVE=1 后验证真实站点，日常测试不依赖外网。
void main() {
  test(
    '真实站点搜索、分类、详情、图片和两种评论排序',
    () async {
      final client = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );
      addTearDown(() => client.close(force: true));
      final network = ManhuaguiNetwork(client, cacheEnabled: false);
      final info = await network.info('4125');
      expect(info.errorMessage, isNull);
      expect(info.data.chapterGroups.length, 3);
      final chapters = info.data.chapterGroups[1].chapterIds
          .map(
            (id) => int.parse(
              RegExp(r'\d+').firstMatch(info.data.chapters![id]!)![0]!,
            ),
          )
          .toList();
      expect(chapters, orderedEquals([...chapters]..sort()));
      final search = await network.search('源君物语', 1);
      expect(search.errorMessage, isNull);
      expect(search.data.map((comic) => comic.id), contains('4125'));
      final catalog = await network.catalog(
        filters: {'area': 'japan', 'status': 'lianzai'},
        page: 2,
      );
      expect(catalog.errorMessage, isNull);
      expect(catalog.data, isNotEmpty);
      final updates = await network.updates(1);
      expect(updates.errorMessage, isNull);
      expect(updates.data, isNotEmpty);
      final filters = await network.filters();
      expect(filters.errorMessage, isNull);
      expect(filters.data.length, 6);
      final pages = await network.pages('4125', '502360');
      expect(pages.errorMessage, isNull);
      expect(pages.data.length, 219);
      final image = await client.get<List<int>>(
        pages.data.first,
        options: Options(
          responseType: ResponseType.bytes,
          headers: ManhuaguiNetwork.imageHeaders,
        ),
      );
      expect(image.statusCode, 200);
      expect(image.data!.length, greaterThan(1024));
      final latest = await network.comments(
        '4125',
        1,
        ManhuaguiCommentSort.latest,
      );
      final hot = await network.comments('4125', 1, ManhuaguiCommentSort.hot);
      expect(latest.errorMessage, isNull);
      expect(hot.errorMessage, isNull);
      expect(latest.data, isNotEmpty);
      expect(hot.data, isNotEmpty);
      expect(latest.data.first.comment.id, isNot(hot.data.first.comment.id));
    },
    skip: Platform.environment['PICA_MANHUAGUI_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

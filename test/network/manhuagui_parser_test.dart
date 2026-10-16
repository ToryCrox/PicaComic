import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_parser.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_network.dart';
import 'package:pica_comic/network/manhuagui/manhuagui_decoder.dart';
import 'package:pica_comic/pages/manhuagui/manhuagui_reading_data.dart';

String fixture(String name) =>
    File('test/fixtures/manhuagui/$name.html').readAsStringSync();

void main() {
  test('普通目录兼容自定义组名，解包兼容未压缩字典', () {
    final info = ManhuaguiParser.info(
      '''<div class="book-title"><h1>样例</h1></div>
      <h4>特别收录</h4><div><ul><li><a href="/comic/1/2.html" title="特别篇">特别篇</a></li></ul></div>''',
      '1',
    );
    expect(info.chapterGroups.single.title, '特别收录');
    expect(info.chapterGroups.single.chapterIds, ['2']);
    expect(
      ManhuaguiDecoder.unpack(
        "eval(function(){}('0.1',10,2,'SMH|imgData'.split('|'),0,{}))",
      ),
      'SMH.imgData',
    );
    expect(() => ManhuaguiDecoder.decompress('!'), throwsFormatException);
  });
  test('示例压缩目录保留所有分组及隐藏区间', () {
    final info = ManhuaguiParser.info(fixture('detail'), '4125');
    expect(info.chapterGroups.map((e) => e.title), ['单行本', '单话', '番外篇']);
    expect(info.chapterGroups.first.chapterIds.length, 16);
    expect(
      info.chapters!.values,
      containsAll(['第01卷', '第16卷', '第01回', '第358话', '番外篇']),
    );
    expect(info.chapterGroups[1].chapterIds.length, greaterThan(300));
    final titles = info.chapterGroups[1].chapterIds
        .map((id) => info.chapters![id]!)
        .toList();
    final numbers = titles
        .map((title) => int.parse(RegExp(r'\d+').firstMatch(title)![0]!))
        .toList();
    expect(numbers.first, 1);
    expect(numbers.last, 358);
    expect(numbers, orderedEquals([...numbers]..sort()));
    for (final boundary in [85, 86, 175, 176, 268, 269, 356, 357, 358]) {
      expect(numbers, contains(boundary));
    }
    final reading = ManhuaguiReadingData(info);
    final keys = info.chapters!.keys.toList();
    int episode(int number) =>
        keys.indexOf(
          info.chapterGroups[1].chapterIds[numbers.indexOf(number)],
        ) +
        1;
    for (final pair in [(85, 86), (175, 176), (268, 269), (357, 358)]) {
      expect(reading.adjacentEpisode(episode(pair.$1), 1), episode(pair.$2));
      expect(reading.adjacentEpisode(episode(pair.$2), -1), episode(pair.$1));
    }
    expect(reading.adjacentEpisode(episode(358), 1), isNull);
    expect(ComicInfoData.fromMap(info.toMap()), info);
  });

  test('真实阅读脚本解包出全部签名图片', () {
    final urls = ManhuaguiParser.pages(fixture('chapter'));
    expect(urls.length, 219);
    expect(Uri.parse(urls.first).host, 'i.hamreus.com');
    expect(Uri.parse(urls.first).queryParameters.keys, containsAll(['e', 'm']));
    expect(urls.toSet().length, 219);
  });

  test('列表和搜索使用各自结构与总页数', () {
    final catalog = ManhuaguiParser.comics(fixture('catalog'));
    expect(catalog.data.length, 42);
    expect(catalog.subData, greaterThan(1));
    final search = ManhuaguiParser.comics(fixture('search'), search: true);
    expect(search.data.single.id, '4125');
  });

  test('分类组合与排序分页不丢条件', () {
    expect(
      ManhuaguiNetwork.catalogPath(
        {'area': 'japan', 'genre': 'rexue', 'status': 'lianzai'},
        'rate',
        2,
      ),
      '/list/japan_rexue_lianzai/rate_p2.html',
    );
  });

  test('评论保留服务端顺序和引用链，异常不能成为空结果', () {
    final comments = ManhuaguiParser.comments({
      'commentIds': ['3,2,1'],
      'comments': {
        '1': {'user_name': '甲', 'content': '原文'},
        '2': {'user_name': '乙', 'content': '中间回复'},
        '3': {'user_name': '丙', 'content': '%u4F60%u597D<br>世界'},
      },
      'total': 31,
    });
    expect(comments.subData, 2);
    expect(comments.data.single.quotes.map((e) => e.userName), ['甲', '乙']);
    expect(comments.data.single.comment.content, '你好\n世界');
    expect(
      () => ManhuaguiParser.comments({'status': 0}),
      throwsFormatException,
    );
    expect(() => ManhuaguiParser.pages('invalid'), throwsFormatException);
  });
}

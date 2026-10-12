import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/continuous_reader_data.dart';
import 'package:pica_comic/pages/reader/reading_data.dart';

void main() {
  test('章节图片保留章内页码，分隔条不计入页数', () async {
    final data = _data((episode) async* {
      yield Res(['$episode-a', '$episode-b']);
    });
    await data.load(2);
    await data.load(3);
    final images = data.items.where((item) => item.isImage).toList();
    expect(images.map((item) => item.episode), [2, 2, 3, 3]);
    expect(images.map((item) => item.page), [0, 1, 0, 1]);
    expect(
      data.items.where((item) => item.kind == ReaderItemKind.header).length,
      2,
    );
    expect(images.map((item) => item.identity).toSet().length, 4);
  });

  test('同章请求合并，后台加载串行且手动请求优先', () async {
    final streams = <int, StreamController<Res<List<String>>>>{};
    final started = <int>[];
    final data = _data((episode) {
      started.add(episode);
      return (streams[episode] = StreamController<Res<List<String>>>()).stream;
    });
    final first = data.load(1);
    expect(identical(first, data.load(1)), isTrue);
    final third = data.load(3);
    final second = data.load(2, priority: true);
    expect(started, [1]);
    streams[1]!.add(const Res(['a']));
    await streams[1]!.close();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2]);
    streams[2]!.add(const Res(['b']));
    await streams[2]!.close();
    await second;
    await Future<void>.delayed(Duration.zero);
    expect(started, [1, 2, 3]);
    streams[3]!.add(const Res(['c']));
    await streams[3]!.close();
    await third;
  });

  test('缓存与网络替换同章，刷新失败保留有效缓存', () async {
    final data = _data((episode) async* {
      yield const Res(['cached']);
      yield const Res(['fresh', 'second']);
      yield const Res.error('offline');
    });
    await data.load(1);
    expect(data.chapters[1]!.urls, ['fresh', 'second']);
    expect(data.chapters[1]!.error, isNull);
    expect(data.items.where((item) => item.isImage).length, 2);
    expect(
      data.items.where((item) => item.kind == ReaderItemKind.header).length,
      1,
    );
  });

  test('头部插入等待滚动结束，下一章可以直接追加', () async {
    var idle = false;
    final data = ContinuousReaderData(
      episodeCount: 4,
      loadEpisode: (ep) async* {
        yield Res(['$ep']);
      },
      onChanged: () {},
      canPrepend: () => idle,
    );
    data.seed(2, ['2']);
    await data.load(1);
    await data.load(3);
    expect(data.firstEpisode, 2);
    expect(data.lastEpisode, 3);
    idle = true;
    data.flushPrepend();
    expect(data.firstEpisode, 1);
    expect(data.items.where((item) => item.isImage).map((item) => item.url), [
      '1',
      '2',
      '3',
    ]);
  });

  test('退出会话后忽略网络返回并完成等待中的请求', () async {
    final stream = StreamController<Res<List<String>>>();
    var changes = 0;
    final data = ContinuousReaderData(
      episodeCount: 3,
      loadEpisode: (_) => stream.stream,
      onChanged: () => changes++,
      canPrepend: () => true,
    );
    final pending = data.load(1);
    final queued = data.load(2);
    data.dispose();
    final previous = changes;
    await Future.wait([pending, queued]);
    stream.add(const Res(['late']));
    await stream.close();
    expect(changes, previous);
    expect(data.chapters, isEmpty);
  });

  test('空章节和失败章节阻止自动越过，重试和跳过独立处理', () async {
    var retry = false;
    final data = _data((episode) async* {
      if (episode == 1 && !retry) {
        yield const Res.error('offline');
      } else if (episode == 2) {
        yield const Res([]);
      } else {
        yield Res(['$episode']);
      }
    });
    await data.load(1);
    expect(data.canLoadNext, isFalse);
    expect(data.items.any((item) => item.kind == ReaderItemKind.error), isTrue);
    retry = true;
    await data.load(1, retry: true);
    expect(data.canLoadNext, isTrue);
    await data.load(2);
    expect(data.canLoadNext, isFalse);
    await data.skip(2, 1);
    expect(data.lastEpisode, 3);
    expect(data.canLoadNext, isTrue);
    await data.load(0);
    await data.load(5);
    expect(data.chapters.keys, [1, 2, 3]);
  });

  test('本地图片保存和分享直接使用目标文件，不依赖当前目录或网络', () async {
    final reading = LocalReadingData(
      'C:/books/b',
      'b',
      allDirPaths: ['C:/books/a', 'C:/books/b'],
    );
    final result = await reading
        .loadImage(1, 4, 'file://C:/books/a/5.png')
        .single;
    expect(result.finished, isTrue);
    expect(result.getFile().path.replaceAll('\\', '/'), 'C:/books/a/5.png');
    expect(reading.dirPath, 'C:/books/b');
  });

  test('本地目录初始章节和目标图片归属不随预加载改变', () {
    final data = LocalReadingData(
      '/books/b',
      'b',
      allDirPaths: ['/books/a', '/books/b', '/books/c'],
    );
    expect(data.initialEpisode, 2);
    expect(data.directoryForEpisode(1), '/books/a');
    expect(data.idForEpisode(3), '/books/c');
    expect(data.titleForEpisode(1), 'a');
    expect(data.dirPath, '/books/b');
    data.goTo(2);
    expect(data.dirPath, '/books/c');
    expect(data.directoryForEpisode(1), '/books/a');
  });
}

/// 创建完全独立于网络和持久化存储的章节加载会话。
ContinuousReaderData _data(Stream<Res<List<String>>> Function(int) load) =>
    ContinuousReaderData(
      episodeCount: 4,
      loadEpisode: load,
      onChanged: () {},
      canPrepend: () => true,
    );

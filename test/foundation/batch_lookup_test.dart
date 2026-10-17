import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/batch_lookup.dart';

void main() {
  test('同一微任务合并查询，查无记录也会缓存', () async {
    final calls = <List<String>>[];
    final lookup = BatchLookup<String, int>((keys) async {
      calls.add(keys);
      return {'a': 1};
    });
    final first = lookup.get('a');
    final duplicate = lookup.get('a');
    final missing = lookup.get('b');
    expect(identical(first, duplicate), isTrue);
    expect(await first, 1);
    expect(await missing, isNull);
    expect(await lookup.get('b'), isNull);
    expect(calls, [
      ['a', 'b'],
    ]);
  });

  test('查询失败后可以重试', () async {
    var attempts = 0;
    final lookup = BatchLookup<String, int>((keys) async {
      if (attempts++ == 0) throw StateError('磁盘暂不可用');
      return {'a': 2};
    });
    await expectLater(lookup.get('a'), throwsStateError);
    expect(await lookup.get('a'), 2);
    expect(attempts, 2);
  });

  test('保存或删除后，旧查询不能覆盖新快照', () async {
    final response = Completer<Map<String, int>>();
    final lookup = BatchLookup<String, int>((_) => response.future);
    final pending = lookup.get('a');
    await Future<void>.delayed(Duration.zero);
    lookup.set('a', 80);
    response.complete({'a': 12});
    expect(await pending, 80);
    lookup.set('a', null);
    expect(await lookup.get('a'), isNull);
  });

  test('清空后旧查询必须重读，不能恢复已删除记录', () async {
    final response = Completer<Map<String, int>>();
    var calls = 0;
    final lookup = BatchLookup<String, int>((_) {
      calls++;
      return calls == 1 ? response.future : Future.value({});
    });
    final pending = lookup.get('a');
    await Future<void>.delayed(Duration.zero);
    lookup.clear();
    response.complete({'a': 1});
    expect(await pending, isNull);
    expect(calls, 2);
  });

  test('缓存有界并优先保留最近使用的记录', () async {
    var calls = 0;
    final lookup = BatchLookup<String, int>((keys) async {
      calls++;
      return {for (final key in keys) key: 1};
    }, capacity: 2);
    await lookup.get('a');
    await lookup.get('b');
    await lookup.get('a');
    await lookup.get('c');
    await lookup.get('a');
    expect(calls, 3);
    await lookup.get('b');
    expect(calls, 4);
  });
}

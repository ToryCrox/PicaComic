import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('历史数据库从版本1升级，保留旧记录并能保存稳定章节 ID', () async {
    final root = await Directory.systemTemp.createTemp('manhuagui-history-');
    App.dataPath = root.path;
    sqfliteFfiInit();
    final legacy = await databaseFactoryFfi.openDatabase(
      '${root.path}/history.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
        CREATE TABLE history (target TEXT PRIMARY KEY, title TEXT, subtitle TEXT, cover TEXT,
          time INTEGER, type INTEGER, ep INTEGER, page INTEGER, readEpisode TEXT, max_page INTEGER)
      '''),
      ),
    );
    await legacy.insert('history', {
      'target': 'legacy',
      'title': '旧漫画',
      'subtitle': '',
      'cover': '',
      'time': 1,
      'type': 0,
      'ep': 2,
      'page': 3,
      'readEpisode': '1,2',
      'max_page': 10,
    });
    await legacy.close();
    final manager = HistoryManager();
    await manager.init();
    addTearDown(() async {
      await (await manager.db).close();
      await root.delete(recursive: true);
    });
    final old = await manager.findSync('legacy');
    expect(old!.ep, 2);
    expect(old.page, 3);
    expect(old.readEpisode, {1, 2});
    expect(old.chapterId, isNull);
    old.chapterId = '20';
    old.readChapterIds.add('20');
    await manager.saveReadHistory(old);
    final row = (await (await manager.db).query('history')).single;
    expect(HistoryRecord.fromRow(row).chapterId, '20');
    expect(HistoryRecord.fromRow(row).readChapterIds, {'20'});
    expect(await (await manager.db).getVersion(), 2);
  });
}

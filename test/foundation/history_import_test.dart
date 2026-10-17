import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首次保存同时迁移旧 JSON，无锁重入且保存完整进度', () async {
    final directory = await Directory.systemTemp.createTemp('history-import-');
    App.dataPath = directory.path;
    final legacy = File('${directory.path}/history.json');
    final previous = History(
      HistoryType.jmComic,
      DateTime(2025),
      '旧历史',
      '',
      '',
      66,
      3,
      'legacy',
      {65, 66},
    );
    await legacy.writeAsString(jsonEncode([previous.toRecord().toMap()]));
    final current = History(
      HistoryType.jmComic,
      DateTime(2026),
      '新历史',
      '',
      '',
      80,
      7,
      'current',
      {80},
    );
    final repository = HistoryManager();
    try {
      await repository
          .saveReadHistory(current)
          .timeout(const Duration(seconds: 5));
      expect((await repository.findRecord('legacy'))?.ep, 66);
      expect((await repository.findRecord('current'))?.page, 7);
      expect(await legacy.exists(), isFalse);
    } finally {
      await (await repository.db).close();
      await directory.delete(recursive: true);
    }
  });
}

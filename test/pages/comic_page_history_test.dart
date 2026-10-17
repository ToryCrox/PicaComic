import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/def.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/history_providers.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page/comic_page_adapter.dart';
import 'package:pica_comic/pages/comic_page/comic_page_logic.dart';
import 'package:pica_comic/pages/jm/jm_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;
  final provider = comicPageLogicProvider((ComicType.jm, 'history-comic'));

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pica_history_test');
    App.dataPath = directory.path;
    await HistoryManager().init();
    ComicPageAdapterRegistry.register(_HistoryTestAdapter());
  });

  tearDownAll(() async {
    await (await HistoryManager().db).close();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await (await HistoryManager().db).insert(
      kTableHistory,
      _history().toRecord().toRow(),
    );
    container = ProviderContainer(
      overrides: [
        downloadManagerProvider.overrideWith(_HistoryTestDownloadManager.new),
      ],
    );
    container.listen(provider, (_, _) {});
    await container.pump();
    await container.read(historyEntryProvider('history-comic').future);
  });

  tearDown(() async {
    container.dispose();
    HistoryManager().clearCache();
    await (await HistoryManager().db).delete(kTableHistory);
  });

  test('首次保存第80话后详情页自动更新，无需再次进入阅读器', () async {
    final history = _history();
    final logic = container.read(provider.notifier);
    logic.updateHistory(history);
    final previous = container.read(provider);

    history.ep = 80;
    history.page = 1;
    history.addReadEpisode(80);
    await HistoryManager().saveReadHistory(history);
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    await container.read(historyEntryProvider('history-comic').future);

    final updated = container.read(provider);
    expect(updated.history?.ep, 80);
    expect(updated.history?.page, 1);
    expect(updated.history?.readEpisode, contains(80));
    expect(previous.history?.ep, 12);
    expect(previous.history?.readEpisode, isNot(contains(80)));

    // 阅读器继续翻页时不能原地改写详情页已发布的状态。
    history.ep = 81;
    history.addReadEpisode(81);
    expect(updated.history?.ep, 80);
    expect(updated.history?.readEpisode, isNot(contains(81)));
  });

  test('保存入口立即捕获快照，后续原地修改不影响待保存数据', () async {
    final history = _history(ep: 10);
    final first = HistoryManager().saveReadHistory(history);
    history.ep = 20;
    final second = HistoryManager().saveReadHistory(history);
    history.ep = 30;
    await Future.wait([first, second]);
    final record = await HistoryManager().findRecord(history.target);
    expect(record!.ep, 20);
    expect(history.ep, 30);
    expect(() => record.readEpisode.add(99), throwsUnsupportedError);
  });

  test('删除和清空后详情与单条查询同步归零', () async {
    await HistoryManager().remove('history-comic');
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(
      await container.read(historyEntryProvider('history-comic').future),
      isNull,
    );
    expect(container.read(provider).history, isNull);
    await HistoryManager().saveReadHistory(_history());
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(
      await container.read(historyEntryProvider('history-comic').future),
      isNotNull,
    );
    await HistoryManager().clearHistory();
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(
      await container.read(historyEntryProvider('history-comic').future),
      isNull,
    );
    expect(container.read(provider).history, isNull);
  });

  test('旧 JSON 导入实际写入并刷新查询，不覆盖已有阅读进度', () async {
    await HistoryManager().readDataFromJson([
      _history(target: 'imported', ep: 66).toRecord().toMap(),
      _history(ep: 99).toRecord().toMap(),
    ]);
    expect((await HistoryManager().findRecord('imported'))?.ep, 66);
    expect((await HistoryManager().findRecord('history-comic'))?.ep, 12);
    await container.pump();
    expect((await container.read(allHistoryProvider.future)).length, 2);
  });

  test('其他漫画退出时不会覆盖当前详情页的历史', () {
    final logic = container.read(provider.notifier);
    logic.updateHistory(_history());
    logic.updateHistory(_history(target: 'another-comic', ep: 80));
    expect(container.read(provider).history?.target, 'history-comic');
    expect(container.read(provider).history?.ep, 12);
  });

  test('连续保存章节后详情页始终显示最新章节', () async {
    final history = _history();
    for (final ep in [80, 81, 42]) {
      history.ep = ep;
      history.addReadEpisode(ep);
      await HistoryManager().saveReadHistory(history);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      await container.read(historyEntryProvider('history-comic').future);
      expect(container.read(provider).history?.ep, ep);
    }
    expect(
      container.read(provider).history?.readEpisode,
      containsAll([80, 81, 42]),
    );
  });
}

/// 创建测试漫画的历史记录。
History _history({String target = 'history-comic', int ep = 12}) => History(
  HistoryType.jmComic,
  DateTime(2026),
  '测试漫画',
  '',
  '',
  ep,
  1,
  target,
  {ep},
);

/// 避免历史同步测试访问网络和下载数据库。
class _HistoryTestAdapter extends JmAdapter {
  @override
  String downloadId(String id, DownloadManager manager) => '';

  @override
  Future<JmComicInfo?> loadCachedData(String id) async => null;

  @override
  Future<Res<JmComicInfo>> loadData(String id) async => const Res.error('Exit');
}

/// 仅提供详情页初始化需要的下载状态。
class _HistoryTestDownloadManager extends DownloadManager {
  @override
  DownloadQueueSnapshot build() => const DownloadQueueSnapshot(
    tasks: [],
    runningTaskIds: {},
    waitingTaskIds: {},
    isDownloading: false,
    hasError: false,
  );
}

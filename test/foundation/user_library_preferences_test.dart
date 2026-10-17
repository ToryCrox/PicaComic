import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/comic_list_page_logic.dart';
import 'package:pica_comic/foundation/user_library_events.dart';
import 'package:pica_comic/foundation/user_library_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟独立数据保存失败，不访问用户目录或 WebDAV。
class _Appdata extends Appdata {
  bool fail = false;

  @override
  Future<void> writeData([bool sync = true]) async {
    if (fail) throw StateError('保存失败');
    notifyUserLibraryChanged();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Appdata previous;
  late _Appdata data;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previous = appdata;
    data = _Appdata();
    appdata = data;
  });

  tearDown(() => appdata = previous);

  test('旧网络保存入口自动通知搜索历史和标签收藏，保持存储格式', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final original = container.read(userLibraryProvider);
    data.searchHistory.add('关键词');
    data.favoriteTags.add('picacg:标签');
    await data.writeHistory();
    await container.pump();
    final state = container.read(userLibraryProvider);
    expect(state.searchHistory, ['关键词']);
    expect(state.favoriteTags, ['picacg:标签']);
    expect(container.read(blockingKeywordRevisionProvider), 0);
    expect(original.searchHistory, isEmpty);
    expect(() => state.searchHistory.clear(), throwsUnsupportedError);
    final stored = await SharedPreferences.getInstance();
    expect(stored.getStringList('search'), ['关键词']);
    expect(stored.getStringList('favoriteTags'), ['picacg:标签']);
    await container
        .read(userLibraryPreferencesActionsProvider.notifier)
        .removeSearchHistory();
    await container.pump();
    expect(container.read(userLibraryProvider).searchHistory, isEmpty);
    expect(container.read(userLibraryProvider).favoriteTags, ['picacg:标签']);
  });

  test('屏蔽词删除失败回滚，成功后同步快照并支持重新添加', () async {
    data.blockingKeyword = ['甲', '乙'];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(userLibraryProvider);
    final actions = container.read(
      userLibraryPreferencesActionsProvider.notifier,
    );
    data.fail = true;
    await expectLater(actions.removeBlockedWord('甲'), throwsStateError);
    expect(data.blockingKeyword, ['甲', '乙']);
    expect(container.read(userLibraryProvider).blockingKeywords, ['甲', '乙']);
    expect(
      container.read(userLibraryPreferencesActionsProvider).hasError,
      isTrue,
    );
    data.fail = false;
    await actions.removeBlockedWord('甲');
    await container.pump();
    expect(container.read(userLibraryProvider).blockingKeywords, ['乙']);
    expect(container.read(blockingKeywordRevisionProvider), 1);
    await actions.addBlockedWords(['甲', '甲']);
    await container.pump();
    expect(container.read(userLibraryProvider).blockingKeywords, ['乙', '甲']);
    expect(container.read(blockingKeywordRevisionProvider), 2);
  });
}

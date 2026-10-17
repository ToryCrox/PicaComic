import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/repository_change.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/favorites/local_favorites_providers.dart';

/// 收藏界面使用内存仓库，测试不访问文件和网络。
class _Repository extends Fake implements LocalFavoritesManager {
  final events =
      StreamController<RepositoryChange<FavoriteIdentity>>.broadcast();
  final members = <FavoriteIdentity>{};
  bool failWrite = false;
  @override
  Stream<RepositoryChange<FavoriteIdentity>> get changes => events.stream;
  @override
  Future<List<String>> get folderNames async => ['测试夹'];
  @override
  Future<List<String>> find(String target, FavoriteType type) async =>
      members.contains((type: type.key, target: target)) ? ['测试夹'] : [];
  @override
  Future<void> setMembership(
    List<String> folders,
    FavoriteItem item, {
    required bool adding,
  }) async {
    if (failWrite) throw StateError('写入失败');
    if (adding) {
      members.add(item.identity);
    } else {
      members.remove(item.identity);
    }
    events.add(
      RepositoryChange(keys: {item.identity}, folders: folders.toSet()),
    );
  }
}

/// 创建面板测试作品。
FavoriteItem _item() => FavoriteItem(
  target: 'a',
  name: '作品',
  coverPath: '',
  author: '',
  type: const FavoriteType(0),
  tags: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    AppTranslation.translations = {};
  });
  late _Repository repository;
  late ProviderContainer container;
  setUp(() {
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        localFavoritesRepositoryProvider.overrideWithValue(repository),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await repository.events.close();
  });

  /// 打开真实收藏面板，同时在页面观察同一作品的收藏标记。
  Future<void> openPanel(
    WidgetTester tester,
    void Function(bool) callback,
  ) async {
    final item = _item();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final membership = ref.watch(
                  favoriteMembershipProvider(item.identity),
                );
                return Column(
                  children: [
                    Text('归属:${membership.asData?.value.length ?? 0}'),
                    TextButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: SizedBox(
                            width: 400,
                            height: 400,
                            child: FavoriteComicWidget(
                              havePlatformFavorite: false,
                              needLoadFolderData: false,
                              localFavoriteItem: item,
                              setFavorite: callback,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('打开'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('面板添加成功后自动更新其他界面的归属状态', (tester) async {
    bool? favorite;
    await openPanel(tester, (value) => favorite = value);
    await tester.tap(find.text('测试夹'));
    await tester.pump();
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(favorite, isTrue);
    expect(find.text('归属:1'), findsOneWidget);
    expect(find.byType(FavoriteComicWidget), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('持久化失败时保留面板和原收藏状态', (tester) async {
    repository.failWrite = true;
    bool? favorite;
    await openPanel(tester, (value) => favorite = value);
    await tester.tap(find.text('测试夹'));
    await tester.pump();
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(favorite, isNull);
    expect(repository.members, isEmpty);
    expect(find.byType(FavoriteComicWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('网络收藏夹请求不随重建重复，关闭后迟到结果不写界面', (tester) async {
    final response = Completer<Res<Map<String, String>>>();
    var calls = 0;
    Widget page() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: FavoriteComicWidget(
              havePlatformFavorite: true,
              needLoadFolderData: true,
              localFavoriteItem: _item(),
              setFavorite: (_) {},
              foldersLoader: () {
                calls++;
                return response.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(page());
    await tester.pump();
    await tester.pumpWidget(page());
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    response.complete(const Res({'folder': '网络夹'}));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

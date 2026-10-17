import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/comic_source/built_in/ht_manga.dart';
import 'package:pica_comic/comic_source/built_in/jm.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/htmanga_network/htmanga_main_network.dart';
import 'package:pica_comic/network/jm_network/jm_crypto.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/favorites/network_favorites_providers.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 模拟收藏夹请求先返回登录过期，续期后返回真实协议格式的响应。
class _ExpiredSessionAdapter implements HttpClientAdapter {
  int requests = 0;
  bool alwaysUnauthorized = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    if (requests == 1 || alwaysUnauthorized) {
      return ResponseBody.fromString(jsonEncode({'errorMsg': '請先登入會員'}), 401);
    }
    final time = options.headers['tokenparam'].toString().split(',').first;
    final plaintext = jsonEncode({
      'folder_list': [
        {'FID': '1', 'name': '续期后的收藏夹'},
      ],
    });
    return ResponseBody.fromString(
      jsonEncode({'data': _encrypt(plaintext, '$time$jmResponseSecret')}),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 只注入本地响应适配器，不初始化真实网络后端。
class _ClientManager extends NetworkClientManager {
  _ClientManager(this.adapter);
  final _ExpiredSessionAdapter adapter;

  @override
  NetworkClientManager build() {
    apiDio = Dio()..httpClientAdapter = adapter;
    ref.onDispose(() => apiDio.close(force: true));
    return this;
  }
}

/// 保留 JM 的真实收藏夹与 401 重试链，仅替换登录请求。
class _JmClient extends JmNetwork {
  int logins = 0;
  bool failLogin = false;
  List<String>? credentials;

  @override
  Future<Res<bool>> login(String account, String pwd) async {
    logins++;
    credentials = [account, pwd];
    return failLogin ? const Res.error('登录失败') : const Res(true);
  }
}

/// 绅士漫画的自动登录必须调用当前实例。
class _HtClient extends HtmangaNetwork {
  int logins = 0;
  @override
  Future<Res<bool>> login(
    String account,
    String pwd, [
    bool saveData = true,
  ]) async {
    logins++;
    return const Res(true);
  }
}

/// 哔咔续期仍需更新令牌与用户资料。
class _PicaClient extends PicacgNetwork {
  bool failProfile = false;
  int logins = 0;
  @override
  Future<Res<String>> login(String email, String password) async {
    logins++;
    return const Res('new-token');
  }

  @override
  Future<Res<Profile>> getProfile([bool log = true]) async => failProfile
      ? const Res.error('资料加载失败')
      : const Res(Profile(name: '续期用户'));
}

/// 注册表不加载用户文件，但保留真实漫画源收藏回调。
class _Registry extends ComicSourceRegistry {
  @override
  Future<List<ComicSource>> build() async => ComicSource.sources;
}

/// 构造 JM 协议响应，以覆盖解密后的实际收藏夹读取。
String _encrypt(String plaintext, String secret) {
  final key = md5.convert(utf8.encode(secret)).toString();
  final bytes = utf8.encode(plaintext);
  final padded = Uint8List((bytes.length + 15) ~/ 16 * 16)
    ..setRange(0, bytes.length, bytes);
  final output = Uint8List(padded.length);
  final cipher = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(utf8.encode(key)));
  for (var offset = 0; offset < padded.length; offset += 16) {
    cipher.processBlock(padded, offset, output, offset);
  }
  return base64Encode(output);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<ComicSource> previousSources;
  late List<Map<String, dynamic>> previousData;
  late ProviderContainer container;
  late _ExpiredSessionAdapter adapter;
  late _JmClient jmClient;
  late _HtClient htClient;
  late _PicaClient picaClient;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('source-relogin-');
    App.dataPath = directory.path;
    App.cachePath = directory.path;
  });
  tearDownAll(() async {
    final cache = await databaseFactoryFfi.openDatabase('${directory.path}/cache.db');
    await cache.close();
    await directory.delete(recursive: true);
  });
  setUp(() {
    previousSources = ComicSource.sources;
    previousData = [jm, htManga, picacg].map((e) => e.data).toList();
    ComicSource.sources = [jm, htManga, picacg];
    for (final source in ComicSource.sources) {
      source.data = {
        'account': <String>['test-account', 'test-password'],
      };
    }
    adapter = _ExpiredSessionAdapter();
    jmClient = _JmClient();
    htClient = _HtClient();
    picaClient = _PicaClient();
    container = ProviderContainer(
      overrides: [
        networkClientManagerProvider.overrideWith(
          () => _ClientManager(adapter),
        ),
        jmNetworkProvider.overrideWith(() => jmClient),
        htMangaNetworkProvider.overrideWith(() => htClient),
        picacgNetworkProvider.overrideWith(() => picaClient),
        comicSourceRegistryProvider.overrideWith(_Registry.new),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    for (var i = 0; i < 3; i++) {
      [jm, htManga, picacg][i].data = previousData[i];
    }
    ComicSource.sources = previousSources;
  });

  test('JM 收藏页 401 后通过当前客户端续期并成功加载收藏夹', () async {
    final provider = networkFavoriteFoldersProvider((
      sourceKey: 'jm',
      comicId: null as String?,
    ));
    container.listen(provider, (_, __) {});
    final folders = await container.read(provider.future);
    expect(folders.folders, {'1': '续期后的收藏夹'});
    expect(jmClient.logins, 1);
    expect(jmClient.credentials, ['test-account', 'test-password']);
    expect(adapter.requests, 2);
  });

  test('JM 续期失败保留普通错误，不触发 Provider 自依赖', () async {
    jmClient.failLogin = true;
    final result = await container.read(jmNetworkProvider).getFolders();
    expect(result.errorMessage, '請先登入會員');
    expect(jmClient.logins, 1);
    expect(adapter.requests, 1);
  });

  test('JM 续期后仍返回 401 时只重试一次', () async {
    adapter.alwaysUnauthorized = true;
    final result = await container.read(jmNetworkProvider).getFolders();
    expect(result.errorMessage, '請先登入會員');
    expect(jmClient.logins, 1);
    expect(adapter.requests, 2);
  });

  test('JM 没有已保存账号时不发起自动登录', () async {
    jm.data.clear();
    final result = await container.read(jmNetworkProvider).loginFromAppdata();
    expect(result.error, isTrue);
    expect(jmClient.logins, 0);
  });

  test('绅士漫画续期调用当前实例并保留账号名称', () async {
    final result = await container
        .read(htMangaNetworkProvider)
        .loginFromAppdata();
    expect(result.success, isTrue);
    expect(htClient.logins, 1);
    expect(htManga.data['name'], 'test-account');
  });

  test('哔咔续期更新令牌和用户资料，不重新读取自身 Provider', () async {
    final result = await container
        .read(picacgNetworkProvider)
        .loginFromAppdata();
    expect(result.success, isTrue);
    expect(picaClient.logins, 1);
    expect(picacg.data['token'], 'new-token');
    expect(picaClient.user?.name, '续期用户');
    expect((picacg.data['user'] as Map)['name'], '续期用户');
  });

  test('哔咔资料加载失败清除新令牌并返回原始错误', () async {
    picaClient.failProfile = true;
    final result = await container
        .read(picacgNetworkProvider)
        .loginWithAccount('test-account', 'test-password');
    expect(result.errorMessage, '资料加载失败');
    expect(picacg.data['token'], isNull);
  });
}

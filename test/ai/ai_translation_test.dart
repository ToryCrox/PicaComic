import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/ai/ai_client.dart';
import 'package:pica_comic/ai/ai_models.dart';
import 'package:pica_comic/ai/ai_result_cache.dart';
import 'package:pica_comic/ai/ai_settings_store.dart';
import 'package:pica_comic/ai/ai_translation_service.dart';
import 'package:pica_comic/ai/bracket_text_protector.dart';

void main() {
  group('方括号保护', () {
    test('半角方括号信息不发送原文并按顺序恢复', () {
      const title = '[しゃる] 一獲千女【片想いしていた同級生編】 [AI Generated]';
      final protection = BracketTextProtection.protect(title);

      expect(protection.protectedText, contains('⟪PICA_BRACKET_0000⟫'));
      expect(protection.protectedText, contains('⟪PICA_BRACKET_0001⟫'));
      expect(protection.protectedText, contains('【片想いしていた同級生編】'));
      expect(
        protection.restore(
          '⟪PICA_BRACKET_0000⟫ 一获千女【暗恋同学篇】 ⟪PICA_BRACKET_0001⟫',
        ),
        '[しゃる] 一获千女【暗恋同学篇】 [AI Generated]',
      );
    });

    test('缺失或乱序占位符时拒绝写入译文', () {
      final protection = BracketTextProtection.protect(
        '[BBStaff] パ〇活 [AI Generated]',
      );
      expect(
        () => protection.restore('⟪PICA_BRACKET_0001⟫ 翻译 ⟪PICA_BRACKET_0000⟫'),
        throwsA(isA<AiRequestException>()),
      );
    });
  });

  group('OpenAI 协议适配', () {
    final config = AiProviderConfig(
      id: 'provider',
      name: '测试服务',
      protocol: AiProtocolType.openAiChatCompletions,
      baseUrl: 'https://example.com/v1',
      apiKey: 'key',
      model: 'model',
    );

    test('Chat Completions 读取 choices.message.content', () async {
      final adapter = OpenAiChatCompletionsAdapter();
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter({
          'choices': [
            {
              'message': {'content': '译文'},
            },
          ],
        });

      final result = await adapter.complete(
        dio,
        config,
        const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
      );
      expect(result, '译文');
    });

    test('Responses 优先读取 output_text', () async {
      final adapter = OpenAiResponsesAdapter();
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter({'output_text': '译文'});

      final result = await adapter.complete(
        dio,
        config.copyWith(protocol: AiProtocolType.openAiResponses),
        const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
      );
      expect(result, '译文');
    });

    test('临时网络错误按配置重试', () async {
      final adapter = _RetryAdapter();
      final client = AiClient(adapters: [adapter], retryDelay: (_) async {});

      final result = await client.complete(
        config,
        const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
      );
      expect(result, '译文');
      expect(adapter.calls, 2);
    });

    test('缺少服务地址时拒绝发起请求', () async {
      final client = AiClient();
      await expectLater(
        client.complete(
          config.copyWith(baseUrl: ''),
          const AiCompletionInput(systemPrompt: 'system', userPrompt: 'user'),
        ),
        throwsA(isA<AiConfigurationException>()),
      );
    });
  });

  group('漫画翻译缓存与去重', () {
    test('原文变化失效，并发相同请求只调用一次 AI', () async {
      final cache = _MemoryResultCache();
      final clientAdapter = _TranslationAdapter();
      final service = AiTranslationService(
        settings: _ReadySettings(),
        client: AiClient(adapters: [clientAdapter]),
        cache: cache,
      );
      const resource = AiComicResource(
        sourceKey: 'picacg',
        downloadId: 'comic-id',
        targetLanguage: 'zh-CN',
      );

      final results = await Future.wait([
        service.translateComicMetadata(
          resource: resource,
          title: '原始标题',
          introduction: '原始简介',
        ),
        service.translateComicMetadata(
          resource: resource,
          title: '原始标题',
          introduction: '原始简介',
        ),
      ]);
      expect(clientAdapter.calls, 1);
      for (final result in results) {
        expect(result.title, '译名');
        expect(result.introduction, '译介');
      }

      final hit = await service.cachedComicTitle(
        resource: resource,
        title: '原始标题',
      );
      final changed = await service.cachedComicTitle(
        resource: resource,
        title: '已变化标题',
      );
      expect(hit, '译名');
      expect(changed, isNull);

      await service.clearComicCache();
      expect(
        await service.cachedComicTitle(resource: resource, title: '原始标题'),
        isNull,
      );
    });

    test('缺失分段标记时不写入缓存', () async {
      final service = AiTranslationService(
        settings: _ReadySettings(),
        client: AiClient(adapters: [_MalformedAdapter()]),
        cache: _MemoryResultCache(),
      );
      const resource = AiComicResource(
        sourceKey: 'picacg',
        downloadId: 'comic-id',
        targetLanguage: 'zh-CN',
      );

      await expectLater(
        service.translateComicMetadata(
          resource: resource,
          title: '原始标题',
          introduction: '原始简介',
        ),
        throwsA(isA<AiRequestException>()),
      );
      expect(
        await service.cachedComicTitle(resource: resource, title: '原始标题'),
        isNull,
      );
    });
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final Object body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RetryAdapter implements AiProtocolAdapter {
  var calls = 0;

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    calls++;
    if (calls == 1) {
      final requestOptions = RequestOptions(path: '/');
      throw DioException(
        requestOptions: requestOptions,
        response: Response(statusCode: 429, requestOptions: requestOptions),
      );
    }
    return '译文';
  }
}

class _TranslationAdapter implements AiProtocolAdapter {
  var calls = 0;

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    calls++;
    return '⟪PICA_COMIC_TITLE⟫译名\n⟪PICA_COMIC_INTRODUCTION⟫译介';
  }
}

class _MalformedAdapter extends _TranslationAdapter {
  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async => '⟪PICA_COMIC_TITLE⟫译名';
}

class _ReadySettings extends AiSettingsStore {
  final _provider = const AiProviderConfig(
    id: 'provider',
    name: '测试服务',
    protocol: AiProtocolType.openAiChatCompletions,
    baseUrl: 'https://example.com/v1',
    apiKey: '',
    model: 'model',
  );

  @override
  bool get initialized => true;

  @override
  ({AiProviderConfig provider, AiPromptPreset prompt}) requireActivePrompt(
    String sceneId,
  ) => (provider: _provider, prompt: AiDefaultPrompts.comicMetadata);
}

class _MemoryResultCache extends AiResultCache {
  final _items = HashMap<String, String>();

  String _key(String sceneId, String resourceKey, String sourceText) =>
      '$sceneId\u0000$resourceKey\u0000${AiResultCache.hashSource(sourceText)}';

  @override
  Future<AiCachedResult?> get({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
  }) async {
    final value = _items[_key(sceneId, resourceKey, sourceText)];
    return value == null ? null : AiCachedResult(value);
  }

  @override
  Future<void> put({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required String resultText,
  }) async {
    _items[_key(sceneId, resourceKey, sourceText)] = resultText;
  }

  @override
  Future<int> clearScene(String sceneId) async {
    final keys = _items.keys
        .where((key) => key.startsWith('$sceneId\u0000'))
        .toList();
    for (final key in keys) {
      _items.remove(key);
    }
    return keys.length;
  }
}

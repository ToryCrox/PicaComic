import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/log.dart';

import 'ai_client.dart';
import 'ai_models.dart';
import 'ai_result_cache.dart';
import 'ai_settings_store.dart';
import 'bracket_text_protector.dart';

/// 用于隔离不同漫画源同名下载 ID 的缓存键。
class AiComicResource {
  final String sourceKey;
  final String downloadId;
  final String targetLanguage;

  const AiComicResource({
    required this.sourceKey,
    required this.downloadId,
    required this.targetLanguage,
  });

  String fieldKey(String field) =>
      'comic:$sourceKey:$downloadId:$targetLanguage:$field';
}

/// 漫画信息译文。空字符串表示对应字段没有可展示的译文。
class ComicMetadataTranslation {
  final String title;
  final String introduction;

  const ComicMetadataTranslation({this.title = '', this.introduction = ''});

  bool get hasValue => title.isNotEmpty || introduction.isNotEmpty;
}

/// 漫画信息 AI 翻译服务。
class AiTranslationService extends ChangeNotifier {
  final AiSettingsStore settings;
  final AiClient client;
  final AiResultCache cache;

  final Map<String, ComicMetadataTranslation> _memory = {};
  final Map<String, Future<ComicMetadataTranslation>> _inFlight = {};

  AiTranslationService({
    required this.settings,
    required this.client,
    AiResultCache? cache,
  }) : cache = cache ?? AiResultCache();

  Future<void> ensureSceneReady() async {
    if (!settings.initialized) await settings.init();
    settings.requireActivePrompt(AiPromptScenes.comicMetadataTranslation);
  }

  /// 仅读取缓存，不会发起 AI 请求。
  Future<ComicMetadataTranslation> cachedComicMetadata({
    required AiComicResource resource,
    required String title,
    String? introduction,
  }) async {
    final titleResult = await _cachedField(resource, 'title', title);
    final introductionResult = introduction == null || introduction.isEmpty
        ? ''
        : await _cachedField(resource, 'introduction', introduction);
    final result = ComicMetadataTranslation(
      title: titleResult ?? '',
      introduction: introductionResult ?? '',
    );
    if (result.hasValue) _updateMemory(resource, title, introduction, result);
    return result;
  }

  /// 获取下载页使用的标题译文，不触发新的 AI 请求。
  Future<String?> cachedComicTitle({
    required AiComicResource resource,
    required String title,
  }) async {
    final key = _memoryKey(resource, title, null);
    final inMemory = _memory[key]?.title;
    if (inMemory?.isNotEmpty == true) return inMemory;
    final cached = await _cachedField(resource, 'title', title);
    if (cached?.isNotEmpty == true) {
      _updateMemory(
        resource,
        title,
        null,
        ComicMetadataTranslation(title: cached!),
      );
    }
    return cached;
  }

  /// 将当前详情页仍缺失的标题、简介合并为一次请求；已有字段直接复用缓存。
  Future<ComicMetadataTranslation> translateComicMetadata({
    required AiComicResource resource,
    required String title,
    String? introduction,
  }) async {
    final cached = await cachedComicMetadata(
      resource: resource,
      title: title,
      introduction: introduction,
    );
    final needTitle = title.trim().isNotEmpty && cached.title.isEmpty;
    final needIntroduction =
        introduction != null &&
        introduction.trim().isNotEmpty &&
        cached.introduction.isEmpty;
    if (!needTitle && !needIntroduction) return cached;

    final sourceText = _buildSourceText(
      title: needTitle ? title : null,
      introduction: needIntroduction ? introduction : null,
    );
    final flightKey =
        '${resource.fieldKey('metadata')}|${AiResultCache.hashSource(sourceText)}';
    final existing = _inFlight[flightKey];
    if (existing != null) return existing;

    late final Future<ComicMetadataTranslation> request;
    request =
        _requestAndCache(
          resource: resource,
          title: title,
          introduction: introduction,
          cached: cached,
          needTitle: needTitle,
          needIntroduction: needIntroduction,
          sourceText: sourceText,
        ).whenComplete(() {
          if (identical(_inFlight[flightKey], request)) {
            _inFlight.remove(flightKey);
          }
        });
    _inFlight[flightKey] = request;
    return request;
  }

  Future<void> clearComicCache() async {
    await cache.clearScene(AiPromptScenes.comicMetadataTranslation);
    _memory.clear();
    notifyListeners();
  }

  Future<ComicMetadataTranslation> _requestAndCache({
    required AiComicResource resource,
    required String title,
    required String? introduction,
    required ComicMetadataTranslation cached,
    required bool needTitle,
    required bool needIntroduction,
    required String sourceText,
  }) async {
    await ensureSceneReady();
    final protection = BracketTextProtection.protect(sourceText);
    final resolved = settings.requireActivePrompt(
      AiPromptScenes.comicMetadataTranslation,
    );
    final translated = await client.complete(
      resolved.provider,
      AiCompletionInput(
        systemPrompt:
            '${AiTemplateRenderer.render(resolved.prompt.systemPrompt, {'text': protection.protectedText, 'target_language': resource.targetLanguage})}\n\n输入中的 ⟪PICA_BRACKET_0000⟫ 占位符必须原样保留。',
        userPrompt: AiTemplateRenderer.render(resolved.prompt.userTemplate, {
          'text': protection.protectedText,
          'target_language': resource.targetLanguage,
        }),
      ),
    );
    final restored = protection.restore(_stripCodeFence(translated));
    final fields = _restoreMetadata(restored, needTitle, needIntroduction);
    final translatedTitle = fields.title ?? cached.title;
    final translatedIntroduction = fields.introduction ?? cached.introduction;
    if (fields.title != null) {
      await _storeField(
        sceneId: AiPromptScenes.comicMetadataTranslation,
        resourceKey: resource.fieldKey('title'),
        sourceText: title,
        resultText: fields.title!,
      );
    }
    if (fields.introduction != null && introduction != null) {
      await _storeField(
        sceneId: AiPromptScenes.comicMetadataTranslation,
        resourceKey: resource.fieldKey('introduction'),
        sourceText: introduction,
        resultText: fields.introduction!,
      );
    }
    final result = ComicMetadataTranslation(
      title: translatedTitle,
      introduction: translatedIntroduction,
    );
    _updateMemory(resource, title, introduction, result);
    return result;
  }

  /// 缓存故障不应掩盖已经获得的有效译文。
  Future<void> _storeField({
    required String sceneId,
    required String resourceKey,
    required String sourceText,
    required String resultText,
  }) async {
    try {
      await cache.put(
        sceneId: sceneId,
        resourceKey: resourceKey,
        sourceText: sourceText,
        resultText: resultText,
      );
    } catch (error, stackTrace) {
      Log.w('写入 AI 翻译缓存失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<String?> _cachedField(
    AiComicResource resource,
    String field,
    String sourceText,
  ) async {
    try {
      return (await cache.get(
        sceneId: AiPromptScenes.comicMetadataTranslation,
        resourceKey: resource.fieldKey(field),
        sourceText: sourceText,
      ))?.resultText;
    } catch (error, stackTrace) {
      Log.w('读取 AI 翻译缓存失败', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  void _updateMemory(
    AiComicResource resource,
    String title,
    String? introduction,
    ComicMetadataTranslation translation,
  ) {
    final key = _memoryKey(resource, title, introduction);
    if (_memory[key]?.title == translation.title &&
        _memory[key]?.introduction == translation.introduction) {
      return;
    }
    _memory[key] = translation;
    _memory[_memoryKey(resource, title, null)] = translation;
    notifyListeners();
  }

  String _memoryKey(
    AiComicResource resource,
    String title,
    String? introduction,
  ) =>
      '${resource.fieldKey('memory')}|${AiResultCache.hashSource('$title\u0000${introduction ?? ''}')}';

  String _buildSourceText({String? title, String? introduction}) {
    final lines = <String>[];
    if (title != null) lines.add('⟪PICA_COMIC_TITLE⟫$title');
    if (introduction != null) {
      lines.add('⟪PICA_COMIC_INTRODUCTION⟫$introduction');
    }
    return lines.join('\n');
  }

  ({String? title, String? introduction}) _restoreMetadata(
    String translated,
    bool expectsTitle,
    bool expectsIntroduction,
  ) {
    const titleMarker = '⟪PICA_COMIC_TITLE⟫';
    const introductionMarker = '⟪PICA_COMIC_INTRODUCTION⟫';
    final expected = <String>[
      if (expectsTitle) titleMarker,
      if (expectsIntroduction) introductionMarker,
    ];
    final found = RegExp(
      r'⟪PICA_COMIC_(?:TITLE|INTRODUCTION)⟫',
    ).allMatches(translated).map((match) => match.group(0)!).toList();
    if (!_sameSequence(found, expected)) {
      throw const AiRequestException('AI 未能完整保留漫画信息分段标记，请重新翻译');
    }
    String? extract(String marker, String? nextMarker) {
      final start = translated.indexOf(marker) + marker.length;
      final end = nextMarker == null
          ? translated.length
          : translated.indexOf(nextMarker);
      return translated.substring(start, end).trim();
    }

    return (
      title: expectsTitle
          ? extract(
              titleMarker,
              expectsIntroduction ? introductionMarker : null,
            )
          : null,
      introduction: expectsIntroduction
          ? extract(introductionMarker, null)
          : null,
    );
  }

  String _stripCodeFence(String value) {
    final trimmed = value.trim();
    final match = RegExp(
      r'^```(?:text)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1) ?? trimmed;
  }

  bool _sameSequence(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

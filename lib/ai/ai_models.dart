import 'dart:convert';

import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

/// AI 服务支持的 OpenAI 协议。
enum AiProtocolType {
  openAiChatCompletions('openai_chat_completions', 'OpenAI Chat Completions'),
  openAiResponses('openai_responses', 'OpenAI Responses');

  final String value;
  final String label;

  const AiProtocolType(this.value, this.label);

  static AiProtocolType fromValue(String? value) =>
      AiProtocolType.values.where((item) => item.value == value).firstOrNull ??
      AiProtocolType.openAiChatCompletions;
}

/// 单个 AI 服务的本机配置。
class AiProviderConfig {
  final String id;
  final String name;
  final AiProtocolType protocol;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String? reasoningEffort;
  final int maxRetries;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoningEffort,
    this.maxRetries = 3,
  });

  AiProviderConfig copyWith({
    String? id,
    String? name,
    AiProtocolType? protocol,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? reasoningEffort,
    int? maxRetries,
    bool clearReasoningEffort = false,
  }) => AiProviderConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    reasoningEffort: clearReasoningEffort
        ? null
        : reasoningEffort ?? this.reasoningEffort,
    maxRetries: (maxRetries ?? this.maxRetries).clamp(0, 10).toInt(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'protocol': protocol.value,
    'base_url': baseUrl,
    'api_key': apiKey,
    'model': model,
    'reasoning_effort': reasoningEffort,
    'max_retries': maxRetries,
  };

  Map<String, dynamic> toJson() => toMap();

  factory AiProviderConfig.fromMap(Map<String, dynamic> map) =>
      AiProviderConfig(
        id: map.optString('id'),
        name: map.optString('name'),
        protocol: AiProtocolType.fromValue(map.optStringOrNull('protocol')),
        baseUrl: map.optString('base_url'),
        apiKey: map.optString('api_key'),
        model: map.optString('model'),
        reasoningEffort: map.optStringOrNull('reasoning_effort'),
        maxRetries: map.optInt('max_retries', 3).clamp(0, 10).toInt(),
      );

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) =>
      AiProviderConfig.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProviderConfig &&
          id == other.id &&
          name == other.name &&
          protocol == other.protocol &&
          baseUrl == other.baseUrl &&
          apiKey == other.apiKey &&
          model == other.model &&
          reasoningEffort == other.reasoningEffort &&
          maxRetries == other.maxRetries;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    protocol,
    baseUrl,
    apiKey,
    model,
    reasoningEffort,
    maxRetries,
  );

  @override
  String toString() => 'AiProviderConfig${jsonEncode(toMap())}';
}

/// AI 提示词预设。
class AiPromptPreset {
  final String id;
  final String name;
  final String sceneId;
  final String providerId;
  final String systemPrompt;
  final String userTemplate;
  final bool isActive;

  const AiPromptPreset({
    required this.id,
    required this.name,
    required this.sceneId,
    required this.providerId,
    required this.systemPrompt,
    required this.userTemplate,
    required this.isActive,
  });

  AiPromptPreset copyWith({
    String? id,
    String? name,
    String? sceneId,
    String? providerId,
    String? systemPrompt,
    String? userTemplate,
    bool? isActive,
  }) => AiPromptPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    sceneId: sceneId ?? this.sceneId,
    providerId: providerId ?? this.providerId,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    userTemplate: userTemplate ?? this.userTemplate,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'scene_id': sceneId,
    'provider_id': providerId,
    'system_prompt': systemPrompt,
    'user_template': userTemplate,
    'is_active': isActive,
  };

  Map<String, dynamic> toJson() => toMap();

  factory AiPromptPreset.fromMap(Map<String, dynamic> map) => AiPromptPreset(
    id: map.optString('id'),
    name: map.optString('name'),
    sceneId: map.optString('scene_id'),
    providerId: map.optString('provider_id'),
    systemPrompt: map.optString('system_prompt'),
    userTemplate: map.optString('user_template'),
    isActive: map.optBool('is_active'),
  );

  factory AiPromptPreset.fromJson(Map<String, dynamic> json) =>
      AiPromptPreset.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiPromptPreset &&
          id == other.id &&
          name == other.name &&
          sceneId == other.sceneId &&
          providerId == other.providerId &&
          systemPrompt == other.systemPrompt &&
          userTemplate == other.userTemplate &&
          isActive == other.isActive;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sceneId,
    providerId,
    systemPrompt,
    userTemplate,
    isActive,
  );

  @override
  String toString() => 'AiPromptPreset${jsonEncode(toMap())}';
}

/// 当前版本支持的 AI 场景及其模板变量。
class AiPromptScenes {
  static const comicMetadataTranslation = 'comic_metadata_translation';

  static const labels = <String, String>{comicMetadataTranslation: '漫画信息翻译'};

  static const requiredVariables = <String, Set<String>>{
    comicMetadataTranslation: {'text', 'target_language'},
  };
}

class AiTemplateRenderer {
  static String render(String template, Map<String, String> variables) {
    var result = template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }

  static String? validate(AiPromptPreset preset) {
    if (!AiPromptScenes.labels.containsKey(preset.sceneId)) {
      return '未知的 AI 场景';
    }
    final required = AiPromptScenes.requiredVariables[preset.sceneId]!;
    final source = '${preset.systemPrompt}\n${preset.userTemplate}';
    for (final variable in required) {
      if (!source.contains('{{$variable}}')) return '缺少模板变量 {{$variable}}';
    }
    return null;
  }
}

class AiDefaultPrompts {
  static const comicMetadata = AiPromptPreset(
    id: 'builtin_comic_metadata_translation',
    name: '漫画信息翻译（跟随应用语言）',
    sceneId: AiPromptScenes.comicMetadataTranslation,
    providerId: '',
    isActive: true,
    systemPrompt:
        '你是漫画标题和简介翻译助手。请将输入中每个不可变分段标记后的内容准确、自然地翻译为 {{target_language}}。'
        '形如 ⟪PICA_COMIC_TITLE⟫、⟪PICA_COMIC_INTRODUCTION⟫ 的标记必须各保留一次，字符和顺序完全不变。'
        '形如 ⟪PICA_BRACKET_0000⟫ 的标记代表作者、出版社、汉化组或其它方括号信息，必须原样保留，不得翻译、删除、移动或改写。'
        '保留人名、作品名、术语、URL、Emoji、颜文字、换行和原有语气；不要补充、删减、审查或解释，不要输出 Markdown 代码块。',
    userTemplate: '请翻译以下漫画信息：\n\n{{text}}',
  );

  static List<AiPromptPreset> create() => const [comicMetadata];
}

class AiSettingsDocument {
  final List<AiProviderConfig> providers;
  final List<AiPromptPreset> prompts;

  const AiSettingsDocument({required this.providers, required this.prompts});

  AiSettingsDocument copyWith({
    List<AiProviderConfig>? providers,
    List<AiPromptPreset>? prompts,
  }) => AiSettingsDocument(
    providers: providers ?? this.providers,
    prompts: prompts ?? this.prompts,
  );

  Map<String, dynamic> toMap() => {
    'version': 1,
    'providers': providers.map((item) => item.toJson()).toList(),
    'prompts': prompts.map((item) => item.toJson()).toList(),
  };

  Map<String, dynamic> toJson() => toMap();

  String encode() => jsonEncode(toMap());

  factory AiSettingsDocument.fromMap(Map<String, dynamic> json) {
    final providers = json
        .optDynamicList('providers')
        .whereType<Map>()
        .map((item) => AiProviderConfig.fromMap(TypeUtil.parseMap(item)))
        .toList();
    final prompts = json
        .optDynamicList('prompts')
        .whereType<Map>()
        .map((item) => AiPromptPreset.fromMap(TypeUtil.parseMap(item)))
        .toList();
    return AiSettingsDocument(providers: providers, prompts: prompts);
  }

  factory AiSettingsDocument.fromJson(Map<String, dynamic> json) =>
      AiSettingsDocument.fromMap(json);

  factory AiSettingsDocument.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('AI 配置根节点必须是对象');
    }
    return AiSettingsDocument.fromMap(TypeUtil.parseMap(decoded));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiSettingsDocument &&
          TypeUtil.equal(providers, other.providers) &&
          TypeUtil.equal(prompts, other.prompts);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'AiSettingsDocument${jsonEncode(toMap())}';
}

class AiConfigurationException implements Exception {
  final String message;
  const AiConfigurationException(this.message);

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

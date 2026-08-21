import 'package:dio/dio.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/network_interceptors.dart';
import 'package:pica_comic/network/network_telemetry.dart';

import 'ai_models.dart';

typedef AiRetryDelay = Future<void> Function(Duration duration);

class AiCompletionInput {
  final String systemPrompt;
  final String userPrompt;

  const AiCompletionInput({
    required this.systemPrompt,
    required this.userPrompt,
  });
}

abstract interface class AiProtocolAdapter {
  AiProtocolType get protocol;

  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  );
}

class AiRequestException implements Exception {
  final String message;
  const AiRequestException(this.message);

  @override
  String toString() => message;
}

/// 独立 AI HTTP 客户端，使用应用级网络监控桥接对象上报请求详情。
class AiClient {
  final Map<AiProtocolType, AiProtocolAdapter> _adapters;
  final AiRetryDelay _retryDelay;

  AiClient({
    Iterable<AiProtocolAdapter>? adapters,
    AiRetryDelay retryDelay = _defaultRetryDelay,
  }) : _retryDelay = retryDelay,
       _adapters = {
         for (final adapter
             in adapters ??
                 const [
                   OpenAiChatCompletionsAdapter(),
                   OpenAiResponsesAdapter(),
                 ])
           adapter.protocol: adapter,
       };

  static Future<void> _defaultRetryDelay(Duration duration) =>
      Future.delayed(duration);

  Future<String> complete(
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    if (config.baseUrl.trim().isEmpty) {
      throw const AiConfigurationException('请设置 Base URL');
    }
    if (config.model.trim().isEmpty) {
      throw const AiConfigurationException('请设置模型名称');
    }
    final adapter = _adapters[config.protocol];
    if (adapter == null) {
      throw AiConfigurationException('尚未支持协议：${config.protocol.label}');
    }
    final headers = <String, dynamic>{'Content-Type': 'application/json'};
    if (config.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.apiKey.trim()}';
    }
    final bridge = NetworkTelemetryBridge.instance;
    final dio =
        Dio(
            BaseOptions(
              headers: headers,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 30),
              responseType: ResponseType.json,
            ),
          )
          ..interceptors.add(NetworkSpeedInterceptor(bridge.speedMonitor))
          ..interceptors.add(NetworkLogInterceptor(bridge.logSink));
    var retries = 0;
    while (true) {
      try {
        final result = await adapter.complete(dio, config, input);
        if (result.trim().isEmpty) {
          throw const AiRequestException('AI 未返回可用文本');
        }
        return result.trim();
      } on AiRequestException {
        rethrow;
      } on DioException catch (error) {
        if (retries < config.maxRetries && _isRetryable(error)) {
          final delay = _backoffDelay(retries++);
          Log.w('AI 请求临时失败，将在 ${delay.inMilliseconds}ms 后重试');
          await _retryDelay(delay);
          continue;
        }
        _throwRequestException(error);
      } catch (_) {
        throw const AiRequestException('AI 响应格式无法识别');
      }
    }
  }

  Future<void> testConfig(AiProviderConfig config) async {
    final response = await complete(
      config,
      const AiCompletionInput(
        systemPrompt: 'Reply with exactly OK.',
        userPrompt: 'OK',
      ),
    );
    if (response.isEmpty) throw const AiRequestException('测试请求没有返回内容');
  }

  static bool _isRetryable(DioException error) {
    if (error.type == DioExceptionType.cancel ||
        error.type == DioExceptionType.badCertificate) {
      return false;
    }
    final status = error.response?.statusCode;
    return status == null ||
        status == 408 ||
        status == 425 ||
        status == 429 ||
        status >= 500;
  }

  static Duration _backoffDelay(int retryIndex) => Duration(
    milliseconds: (500 * (1 << retryIndex)).clamp(500, 8000).toInt(),
  );

  static Never _throwRequestException(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      throw const AiRequestException('AI 请求超时，请稍后重试');
    }
    final body = error.response?.data;
    final apiError = body is Map ? body['error'] : null;
    final message = apiError is Map
        ? apiError['message']
        : body is Map
        ? body['message']
        : null;
    throw AiRequestException(
      message is String && message.isNotEmpty
          ? 'AI 请求失败：$message'
          : 'AI 请求失败（HTTP ${error.response?.statusCode ?? '网络错误'}）',
    );
  }

  static String endpoint(String baseUrl, String endpoint) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final suffix = endpoint.replaceFirst(RegExp(r'^/+'), '');
    return base.endsWith('/$suffix') ? base : '$base/$suffix';
  }
}

class OpenAiChatCompletionsAdapter implements AiProtocolAdapter {
  const OpenAiChatCompletionsAdapter();

  @override
  AiProtocolType get protocol => AiProtocolType.openAiChatCompletions;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    final body = <String, dynamic>{
      'model': config.model.trim(),
      'messages': [
        {'role': 'system', 'content': input.systemPrompt},
        {'role': 'user', 'content': input.userPrompt},
      ],
    };
    if (config.reasoningEffort?.isNotEmpty == true) {
      body['reasoning_effort'] = config.reasoningEffort;
    }
    final response = await dio.post<dynamic>(
      AiClient.endpoint(config.baseUrl, 'chat/completions'),
      data: body,
    );
    final data = response.data;
    if (data is! Map) throw const AiRequestException('Chat 响应格式无效');
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AiRequestException('Chat 响应中没有可用结果');
    }
    final message = (choices.first as Map)['message'];
    final content = message is Map ? message['content'] : null;
    final text = _contentToText(content);
    if (text == null || text.trim().isEmpty) {
      throw const AiRequestException('Chat 响应中没有文本内容');
    }
    return text;
  }
}

class OpenAiResponsesAdapter implements AiProtocolAdapter {
  const OpenAiResponsesAdapter();

  @override
  AiProtocolType get protocol => AiProtocolType.openAiResponses;

  @override
  Future<String> complete(
    Dio dio,
    AiProviderConfig config,
    AiCompletionInput input,
  ) async {
    final body = <String, dynamic>{
      'model': config.model.trim(),
      'instructions': input.systemPrompt,
      'input': input.userPrompt,
      'store': false,
    };
    if (config.reasoningEffort?.isNotEmpty == true) {
      body['reasoning'] = {'effort': config.reasoningEffort};
    }
    final response = await dio.post<dynamic>(
      AiClient.endpoint(config.baseUrl, 'responses'),
      data: body,
    );
    final data = response.data;
    if (data is! Map) throw const AiRequestException('Responses 响应格式无效');
    if (data['error'] != null) {
      final error = data['error'];
      throw AiRequestException(
        error is Map ? error['message'] as String? ?? 'AI 拒绝请求' : 'AI 拒绝请求',
      );
    }
    final direct = data['output_text'];
    if (direct is String && direct.trim().isNotEmpty) return direct;
    final output = data['output'];
    if (output is! List) throw const AiRequestException('Responses 响应中没有可用结果');
    final buffer = StringBuffer();
    for (final item in output.whereType<Map>()) {
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content.whereType<Map>()) {
        if (part['type'] == 'refusal') {
          throw AiRequestException(part['refusal'] as String? ?? 'AI 拒绝生成译文');
        }
        if (part['type'] == 'output_text' && part['text'] is String) {
          buffer.write(part['text']);
        }
      }
    }
    if (buffer.isEmpty) throw const AiRequestException('Responses 响应中没有文本内容');
    return buffer.toString();
  }
}

String? _contentToText(dynamic content) {
  if (content is String) return content;
  if (content is! List) return null;
  final buffer = StringBuffer();
  for (final part in content.whereType<Map>()) {
    final text = part['text'] ?? part['content'];
    if (text is String) buffer.write(text);
  }
  return buffer.toString();
}

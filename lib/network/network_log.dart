import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../base.dart';
import 'network_monitor_settings.dart';

part 'network_log.g.dart';

/// 单条请求体或响应体最多保留的字符数。
const networkLogBodyMaxLength = 64 * 1024;

/// 网络日志最多保留的条数。
const networkLogMaxCount = 500;

/// Protocol 来源。
enum NetworkProtocolSource { actual, configured, fallback, unknown }

/// Protocol 元数据。
class NetworkProtocolInfo {
  const NetworkProtocolInfo({
    this.protocol,
    this.source = NetworkProtocolSource.unknown,
    this.backend,
    this.fallback,
  });

  final String? protocol;
  final NetworkProtocolSource source;
  final String? backend;
  final String? fallback;

  String get displayText {
    final value = protocol ?? 'Unknown';
    final sourceText = switch (source) {
      NetworkProtocolSource.actual => '实际',
      NetworkProtocolSource.configured => '配置',
      NetworkProtocolSource.fallback => 'fallback',
      NetworkProtocolSource.unknown => '未知',
    };
    return '$value · $sourceText';
  }
}

/// 日志中保存的请求体或响应体。
class NetworkLogBody {
  const NetworkLogBody({
    required this.content,
    required this.byteLength,
    this.isBinary = false,
    this.isTruncated = false,
  });

  final String content;
  final int byteLength;
  final bool isBinary;
  final bool isTruncated;

  static NetworkLogBody? capture(dynamic body, {String? contentType}) {
    if (body == null) return null;
    if (body is ResponseBody) {
      final length = body.contentLength;
      return NetworkLogBody(
        content: '<流式响应>',
        byteLength: length < 0 ? 0 : length,
        isBinary: true,
      );
    }
    if (body is Uint8List || body is List<int>) {
      final bytes = body is Uint8List ? body : Uint8List.fromList(body);
      return NetworkLogBody(
        content: '<二进制数据，${bytes.length} bytes>',
        byteLength: bytes.length,
        isBinary: true,
      );
    }

    String text;
    if (body is Map || body is List) {
      text = _encodeJson(body);
    } else if (body is String) {
      text = _formatString(body, contentType);
    } else {
      text = body.toString();
    }

    final byteLength = utf8.encode(text).length;
    if (byteLength > networkLogBodyMaxLength) {
      return NetworkLogBody(
        content: _truncateUtf8(text),
        byteLength: byteLength,
        isTruncated: true,
      );
    }
    return NetworkLogBody(content: text, byteLength: byteLength);
  }

  static String _formatString(String value, String? contentType) {
    final looksLikeJson =
        contentType?.toLowerCase().contains('json') == true ||
        value.trimLeft().startsWith('{') ||
        value.trimLeft().startsWith('[');
    if (!looksLikeJson) return value;
    try {
      return _encodeJson(jsonDecode(value));
    } catch (_) {
      return value;
    }
  }

  static String _encodeJson(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  static String _truncateUtf8(String value) {
    var byteLength = 0;
    var codeUnitEnd = 0;
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      final characterLength = utf8.encode(character).length;
      if (byteLength + characterLength > networkLogBodyMaxLength) break;
      byteLength += characterLength;
      codeUnitEnd += character.length;
    }
    return value.substring(0, codeUnitEnd);
  }
}

/// 单条网络请求日志。
class NetworkLog {
  const NetworkLog({
    required this.id,
    required this.url,
    required this.method,
    required this.requestTime,
    this.statusCode,
    this.duration,
    this.requestHeaders,
    this.requestBody,
    this.responseHeaders,
    this.responseBody,
    this.error,
    this.protocol,
    this.protocolSource = NetworkProtocolSource.unknown,
    this.backend,
    this.fallback,
  });

  final String id;
  final String url;
  final String method;
  final DateTime requestTime;
  final int? statusCode;
  final Duration? duration;
  final Map<String, dynamic>? requestHeaders;
  final NetworkLogBody? requestBody;
  final Map<String, dynamic>? responseHeaders;
  final NetworkLogBody? responseBody;
  final String? error;
  final String? protocol;
  final NetworkProtocolSource protocolSource;
  final String? backend;
  final String? fallback;

  bool get isSuccess =>
      statusCode != null && statusCode! >= 200 && statusCode! < 300;

  String get formattedRequestTime {
    final time = requestTime;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  NetworkProtocolInfo get protocolInfo => NetworkProtocolInfo(
    protocol: protocol,
    source: protocolSource,
    backend: backend,
    fallback: fallback,
  );

  NetworkLog copyWith({
    int? statusCode,
    Duration? duration,
    Map<String, dynamic>? responseHeaders,
    NetworkLogBody? responseBody,
    String? error,
    String? protocol,
    NetworkProtocolSource? protocolSource,
    String? backend,
    String? fallback,
  }) {
    return NetworkLog(
      id: id,
      url: url,
      method: method,
      requestTime: requestTime,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      statusCode: statusCode ?? this.statusCode,
      duration: duration ?? this.duration,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      error: error ?? this.error,
      protocol: protocol ?? this.protocol,
      protocolSource: protocolSource ?? this.protocolSource,
      backend: backend ?? this.backend,
      fallback: fallback ?? this.fallback,
    );
  }
}

/// 拦截器传递给日志控制器的请求标识。
class NetworkLogRequestToken {
  const NetworkLogRequestToken({required this.id, required this.startedAt});

  final String id;
  final DateTime startedAt;
}

/// 网络日志上报接口，避免网络层直接依赖 Riverpod。
abstract interface class NetworkLogSink {
  NetworkLogRequestToken? beginRequest(RequestOptions options);

  void completeResponse(NetworkLogRequestToken token, Response response);

  void failRequest(NetworkLogRequestToken token, DioException error);
}

/// 网络日志状态。
class NetworkLogState {
  const NetworkLogState({
    required this.logs,
    required this.searchQuery,
    required this.isCollecting,
  });

  final List<NetworkLog> logs;
  final String searchQuery;
  final bool isCollecting;

  List<NetworkLog> get filteredLogs {
    final query = searchQuery.trim().toLowerCase();
    final result = query.isEmpty
        ? logs
        : logs
              .where((log) {
                return log.url.toLowerCase().contains(query) ||
                    log.method.toLowerCase().contains(query) ||
                    (log.statusCode?.toString().contains(query) ?? false) ||
                    (log.protocol?.toLowerCase().contains(query) ?? false);
              })
              .toList(growable: false);
    return List.unmodifiable(result.reversed);
  }

  NetworkLogState copyWith({
    List<NetworkLog>? logs,
    String? searchQuery,
    bool? isCollecting,
  }) {
    return NetworkLogState(
      logs: logs ?? this.logs,
      searchQuery: searchQuery ?? this.searchQuery,
      isCollecting: isCollecting ?? this.isCollecting,
    );
  }
}

/// 网络日志控制器。
@Riverpod(keepAlive: true)
class NetworkLogController extends _$NetworkLogController
    implements NetworkLogSink {
  int _sequence = 0;

  @override
  NetworkLogState build() {
    return NetworkLogState(
      logs: const [],
      searchQuery: '',
      isCollecting: _readCollectingSetting(),
    );
  }

  @override
  NetworkLogRequestToken? beginRequest(RequestOptions options) {
    if (!state.isCollecting) return null;
    final startedAt = DateTime.now();
    final token = NetworkLogRequestToken(
      id: '${startedAt.microsecondsSinceEpoch}-${_sequence++}',
      startedAt: startedAt,
    );
    final log = NetworkLog(
      id: token.id,
      url: options.uri.toString(),
      method: options.method,
      requestTime: startedAt,
      requestHeaders: _copyHeaders(options.headers),
      requestBody: NetworkLogBody.capture(
        options.data,
        contentType: options.contentType,
      ),
    );
    _append(log);
    return token;
  }

  @override
  void completeResponse(NetworkLogRequestToken token, Response response) {
    final info = protocolInfoFromResponse(response);
    _update(
      token.id,
      response.statusCode,
      DateTime.now().difference(token.startedAt),
      response.headers.map,
      NetworkLogBody.capture(
        response.data,
        contentType: response.headers.value(Headers.contentTypeHeader),
      ),
      null,
      info,
    );
  }

  @override
  void failRequest(NetworkLogRequestToken token, DioException error) {
    final response = error.response;
    final info = response == null
        ? const NetworkProtocolInfo()
        : protocolInfoFromResponse(response);
    _update(
      token.id,
      response?.statusCode,
      DateTime.now().difference(token.startedAt),
      response?.headers.map,
      response == null
          ? null
          : NetworkLogBody.capture(
              response.data,
              contentType: response.headers.value(Headers.contentTypeHeader),
            ),
      error.toString(),
      info,
    );
  }

  /// 设置是否采集网络日志。
  Future<void> setCollecting(bool value) async {
    while (appdata.settings.length <= networkLogCollectingSettingIndex) {
      appdata.settings.add('0');
    }
    appdata.settings[networkLogCollectingSettingIndex] = value ? '1' : '0';
    state = state.copyWith(isCollecting: value);
    await appdata.updateSettings();
  }

  /// 修改搜索关键字。
  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value);
  }

  /// 清空网络日志。
  void clear() {
    state = state.copyWith(logs: const []);
  }

  void _append(NetworkLog log) {
    final logs = [...state.logs, log];
    final start = logs.length > networkLogMaxCount
        ? logs.length - networkLogMaxCount
        : 0;
    state = state.copyWith(logs: List.unmodifiable(logs.sublist(start)));
  }

  void _update(
    String id,
    int? statusCode,
    Duration duration,
    Map<String, List<String>>? headers,
    NetworkLogBody? body,
    String? error,
    NetworkProtocolInfo info,
  ) {
    final index = state.logs.indexWhere((log) => log.id == id);
    if (index < 0) return;
    final old = state.logs[index];
    final updated = old.copyWith(
      statusCode: statusCode,
      duration: duration,
      responseHeaders: headers,
      responseBody: body,
      error: error,
      protocol: info.protocol,
      protocolSource: info.source,
      backend: info.backend,
      fallback: info.fallback,
    );
    final logs = [...state.logs]..[index] = updated;
    state = state.copyWith(logs: List.unmodifiable(logs));
  }

  bool _readCollectingSetting() {
    return appdata.settings.length > networkLogCollectingSettingIndex &&
        appdata.settings[networkLogCollectingSettingIndex] == '1';
  }
}

/// 当前过滤后的网络日志。
@riverpod
List<NetworkLog> networkLogs(Ref ref) {
  return ref.watch(networkLogControllerProvider).filteredLogs;
}

/// 当前网络日志采集状态。
@riverpod
bool networkLogCollecting(Ref ref) {
  return ref.watch(networkLogControllerProvider).isCollecting;
}

/// 将 Dio 的响应元数据转换为详情页使用的 Protocol 信息。
NetworkProtocolInfo protocolInfoFromResponse(Response response) {
  final extra = response.extra;
  final headerProtocol = response.headers.value('x-protocol-version');
  final protocol = normalizeNetworkProtocol(
    extra['networkProtocol'] ?? headerProtocol,
  );
  var source = _parseProtocolSource(extra['networkProtocolSource']);
  if (source == NetworkProtocolSource.unknown &&
      extra['networkProtocol'] == null &&
      headerProtocol != null) {
    source = NetworkProtocolSource.actual;
  }
  return NetworkProtocolInfo(
    protocol: protocol,
    source: protocol == null ? NetworkProtocolSource.unknown : source,
    backend: extra['networkBackend']?.toString(),
    fallback: extra['networkFallback']?.toString(),
  );
}

/// 统一网络协议名称。
String? normalizeNetworkProtocol(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'http09' || 'http_0_9' => 'HTTP/0.9',
    'http10' || 'http1_0' || 'http_1_0' => 'HTTP/1.0',
    'http11' || 'http1_1' || 'http_1_1' || 'http1' => 'HTTP/1.1',
    'http2' || 'http_2' => 'HTTP/2',
    'http3' || 'http_3' => 'HTTP/3',
    'other' => 'Other',
    'auto' => 'auto',
    _ => value.toString(),
  };
}

NetworkProtocolSource _parseProtocolSource(Object? value) {
  return switch (value?.toString()) {
    'actual' => NetworkProtocolSource.actual,
    'configured' => NetworkProtocolSource.configured,
    'fallback' => NetworkProtocolSource.fallback,
    _ => NetworkProtocolSource.unknown,
  };
}

Map<String, dynamic> _copyHeaders(Map<String, dynamic> headers) {
  return Map<String, dynamic>.unmodifiable(
    headers.map((key, value) => MapEntry(key, value)),
  );
}

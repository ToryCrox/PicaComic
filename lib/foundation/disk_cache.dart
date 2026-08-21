import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/network_log.dart';
import 'package:pica_comic/network/network_telemetry.dart';

import '../tools/type_util.dart';
import 'log.dart';

class DiskCache {
  const DiskCache._();

  static const String _sTag = 'app_disk_cache';

  static Map<String, String>? _getCacheHeader(Duration? cacheTime) {
    if (cacheTime != null) {
      return {
        CacheHttpFileService.customCacheControlHeader:
            'max-age=${cacheTime.inSeconds}',
      };
    } else {
      return null;
    }
  }

  /// 获取文件流，缓存
  static Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final transferId = 'cache:${DateTime.now().microsecondsSinceEpoch}:$url';
    final requestHeaders = <String, String>{
      ...?headers,
      networkTelemetryTransferHeader: transferId,
    };
    return _trackFileStream(
      DiskCacheManager.instance.getFileStream(
        url,
        key: key,
        headers: requestHeaders,
        withProgress: withProgress,
      ),
      transferId,
    );
  }

  static Stream<FileResponse> _trackFileStream(
    Stream<FileResponse> source,
    String transferId,
  ) async* {
    await for (final response in source) {
      if (response is FileInfo && response.source == FileSource.Online) {
        NetworkTelemetryBridge.instance.reportArtifactReady(
          transferId: transferId,
          path: response.file.path,
          source: NetworkArtifactSource.imageCache,
        );
      }
      yield response;
    }
  }

  /// 下载文件，并缓存到本地, 如果已经有文件，则直接返回
  static Future<FileInfo?> downloadFileWithCache(
    String url, {
    Duration? cacheTime,
  }) async {
    final fileInfo = await getFileCache(url);
    if (fileInfo != null) {
      return fileInfo;
    }

    Completer<FileInfo?> completer = Completer();
    Stream<FileResponse> stream = getFileStream(
      url,
      withProgress: false,
      headers: _getCacheHeader(cacheTime),
    );
    stream.listen(
      (FileResponse event) {
        if (event is DownloadProgress) {
          //progress?.call(event.downloaded, event.totalSize ?? 0);
        } else if (event is FileInfo && !completer.isCompleted) {
          completer.complete(event);
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        Log.w('first download onError, url: $url, error: $e');
      },
      onDone: () {},
      cancelOnError: true,
    );
    return await completer.future;
  }

  /// 强制下载缓存
  static Future<HttpCacheFileInfo> downloadFile(
    String url, {
    String? key,
    bool force = false,
    Duration? cacheTime,
  }) async {
    final transferId =
        'cache-download:${DateTime.now().microsecondsSinceEpoch}:$url';
    try {
      final requestHeaders = <String, String>{
        ...?_getCacheHeader(cacheTime),
        networkTelemetryTransferHeader: transferId,
      };
      final fileInfo = await DiskCacheManager.instance.downloadFile(
        url,
        key: key,
        authHeaders: requestHeaders,
        force: force,
      );
      NetworkTelemetryBridge.instance.reportArtifactReady(
        transferId: transferId,
        path: fileInfo.file.path,
        source: NetworkArtifactSource.imageCache,
      );
      return HttpCacheFileInfo.fromFileInfo(fileInfo, 0);
    } catch (e) {
      Log.w('downloadFileToCache, url: $url, error: $e');
      if (e is HttpExceptionWithStatus) {
        return HttpCacheFileInfo.fromError(e.message, e.statusCode);
      } else {
        return HttpCacheFileInfo.fromError(e.toString(), -1);
      }
    }
  }

  /// 删除文件缓存
  static Future<void> deleteFileCache(String key) async {
    await DiskCacheManager.instance.removeFile(key);
  }

  /// 获取缓存文件
  static Future<FileInfo?> getFileCache(String key) async {
    FileInfo? fileInfo = await DiskCacheManager.instance.getFileFromCache(key);
    return fileInfo;
  }

  static Future<List<int>?> getFileBytes(String key) async {
    try {
      final fileInfo = await getFileCache(key);
      return await fileInfo?.file.readAsBytes();
    } catch (e) {
      Log.e(e);
      return null;
    }
  }

  /// 缓存文件
  static Future<File?> putFileBytes(String key, Uint8List fileBytes) async {
    return await DiskCacheManager.instance.putFile(
      key,
      fileBytes,
      maxAge: const Duration(days: 360),
    );
  }

  /// 读取缓存文件
  static Future<String?> readString(String key) async {
    Log.d(() => '$_sTag readCacheString, key: $key');
    final fileInfo = await getFileCache(key);
    try {
      if (fileInfo != null) {
        return utf8.decode(await fileInfo.file.readAsBytes());
      } else {
        return null;
      }
    } catch (e) {
      Log.e(e);
      return null;
    }
  }

  /// 读取缓存文件
  static Future<T?> readModel<T>(
    String key,
    T Function(Map<String, dynamic> map) fromJson,
  ) async {
    final t1 = DateTime.now().millisecondsSinceEpoch;
    final str = await readString(key);
    try {
      final Map<String, dynamic> map = TypeUtil.parseMap(str);
      final timeSpent = DateTime.now().millisecondsSinceEpoch - t1;
      Log.d(
        () => 'readCacheModel, key: $key, str: $str, timSpent: ${timeSpent}ms',
      );
      return map.isNotEmpty ? fromJson(map) : null;
    } catch (e) {
      Log.w('readCacheModel key: $key, e: $e');
      return null;
    }
  }

  /// 写入缓存文件
  static Future<void> writeString(String key, String value) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(value));
      Log.d(
        () =>
            '$_sTag writeCacheString, key: $key, bytes.size: ${bytes.length}， value: $value',
      );
      await putFileBytes(key, bytes);
    } catch (e) {
      Log.e(e);
    }
  }

  /// 写入缓存文件
  static Future<void> writeModel(String key, Map<String, dynamic> map) async {
    final jsonStr = jsonEncode(map);
    Log.d(() => 'writeModel $jsonStr');
    await writeString(key, jsonStr);
  }

  static Future<List<T>> readModelList<T>(
    String key,
    T Function(Map<String, dynamic> map) fromJson,
  ) async {
    final t1 = DateTime.now().millisecondsSinceEpoch;
    final str = await readString(key);
    try {
      final List<dynamic> list = TypeUtil.parseMapList(str);
      final timeSpent = DateTime.now().millisecondsSinceEpoch - t1;
      Log.d(
        () => 'readCacheModel, key: $key, str: $str, timSpent: ${timeSpent}ms',
      );
      return list.isNotEmpty ? list.map((e) => fromJson(e)).toList() : [];
    } catch (e) {
      Log.w('readCacheModel key: $key, e: $e');
      return [];
    }
  }

  static Future<void> writeModelList(
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    final jsonStr = jsonEncode(list);
    Log.d(() => 'writeModelList $jsonStr');
    await writeString(key, jsonStr);
  }
}

class DiskCacheManager {
  static const _key = 'app_disk_cache';
  static CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 360),
      maxNrOfCacheObjects: 10000,
      fileService: CacheHttpFileService(),
    ),
  );
}

class HttpCacheFileInfo {
  final int httpCode;
  final String message;
  final FileInfo? _fileInfo;

  FileInfo get fileInfo {
    if (_fileInfo == null) {
      throw StateError(
        'fileInfo is null, please check httpCode first,'
        ' httpCode: $httpCode, message: $message',
      );
    }
    return _fileInfo;
  }

  HttpCacheFileInfo(this.httpCode, this.message, this._fileInfo);

  factory HttpCacheFileInfo.fromFileInfo(FileInfo fileInfo, int httpCode) {
    return HttpCacheFileInfo(httpCode, '', fileInfo);
  }

  factory HttpCacheFileInfo.fromError(String message, int httpCode) {
    return HttpCacheFileInfo(httpCode, message, null);
  }

  bool get isSuccess => httpCode == 200 || httpCode == 0;
}

class CacheHttpFileService extends FileService {
  static const customCacheControlHeader = 'custom-cache-control';

  CacheHttpFileService();

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    Log.d(
      'CacheHttpFileService CacheHttpFileService get, url: $url, headers: $headers',
    );
    final requestHeaders = <String, String>{...?headers};
    String? cacheControl;
    if (requestHeaders.containsKey(customCacheControlHeader)) {
      cacheControl = requestHeaders[customCacheControlHeader];
      requestHeaders.remove(customCacheControlHeader);
    }
    final transferId = requestHeaders.remove(networkTelemetryTransferHeader);
    final extra = <String, dynamic>{};
    if (transferId != null) {
      extra[networkTransferIdExtraKey] = transferId;
    }
    extra[networkRequestKindExtraKey] = NetworkRequestKind.image.name;
    final response = await networkClientManager.mediaDio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: requestHeaders,
        extra: extra,
      ),
    );
    return DioFileServiceResponse(response, cacheControl);
  }
}

/// 使用共享媒体 Dio 的缓存文件响应。
class DioFileServiceResponse implements FileServiceResponse {
  DioFileServiceResponse(this._response, this._cacheControl);

  final Response<ResponseBody> _response;
  final String? _cacheControl;
  final DateTime _receivedTime = DateTime.now();

  String? _header(String name) {
    if (name == HttpHeaders.cacheControlHeader && _cacheControl != null) {
      return _cacheControl;
    }
    return _response.headers.value(name);
  }

  @override
  Stream<List<int>> get content =>
      _response.data?.stream ?? const Stream.empty();

  @override
  int? get contentLength => int.tryParse(
    _response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
  );

  @override
  int get statusCode => _response.statusCode ?? 0;

  @override
  DateTime get validTill {
    var duration = const Duration(days: 7);
    final controlHeader = _header(HttpHeaders.cacheControlHeader);
    if (controlHeader != null) {
      for (final setting in controlHeader.split(',')) {
        final value = setting.trim().toLowerCase();
        if (value == 'no-cache') duration = Duration.zero;
        if (value.startsWith('max-age=')) {
          duration = Duration(
            seconds: int.tryParse(value.split('=').last) ?? 0,
          );
        }
      }
    }
    return _receivedTime.add(duration);
  }

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    final contentType = _header(HttpHeaders.contentTypeHeader)?.toLowerCase();
    if (contentType == null) return '';
    if (contentType.contains('jpeg')) return '.jpg';
    if (contentType.contains('png')) return '.png';
    if (contentType.contains('gif')) return '.gif';
    if (contentType.contains('webp')) return '.webp';
    return '';
  }
}

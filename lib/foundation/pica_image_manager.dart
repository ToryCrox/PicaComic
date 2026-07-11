import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pica_comic/network/app_dio.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'dart:io' as io;
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/image_config.dart';
import 'package:file/local.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:pica_comic/foundation/def.dart';
import 'dart:typed_data';

final PicaImageManager picaImageManager = PicaImageManager._();

class PicaImageManager extends CacheManager with ImageCacheManager {
  static const key = 'libCachedImageData';

  static final PicaImageManager _instance = PicaImageManager._();

  factory PicaImageManager() {
    return _instance;
  }

  PicaImageManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 5000,
          fileService: PicaHttpFileService(),
        ),
      );

  Future<FileInfo?> _fileInfoFromIoFile(String filePath, String url) async {
    final ioFile = io.File(filePath);
    // 转换为 file 包的 File 类型
    const fs = LocalFileSystem();
    if (await ioFile.exists()) {
      // 返回 FileInfo，使用 FileSource.cache 表示本地缓存文件
      return FileInfo(
        fs.file(filePath),
        FileSource.Cache,
        DateTime.now().add(const Duration(days: 365)),
        url,
      );
    }
    return null;
  }

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) async* {
    if (url.startsWith('file://')) {
      try {
        final uri = Uri.tryParse(url);
        final filePath = uri?.toFilePath();
        if (filePath == null) {
          Log.e('filePath is null: $url');
          throw Exception('filePath is null: $url');
        }
        final response = await _fileInfoFromIoFile(filePath, url);
        Log.d(() => '加载本地文件成功: $url, ${response?.file.path}');
        if (response != null) {
          yield response;
          return;
        }
      } catch (e) {
        Log.e('读取本地文件失败: $url, $e');
      }
      // 文件不存在，直接报错
      throw Exception('getImageFile file not found: $url');
    }
    yield* super.getImageFile(
      url,
      key: key,
      headers: headers,
      withProgress: withProgress,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
    );
  }
}

class PicaHttpFileService extends FileService {
  final Dio _dio = logDio()
    ..interceptors.add(CookieManagerSql(SingleInstanceCookieJar.instance!));

  static int _ehgtLoading = 0;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final sourceKey = headers?['sourceKey'];
      ImageConfig? config;

      if (sourceKey != null) {
        final source = ComicSource.find(sourceKey);
        if (source != null) {
          if (headers?['isThumbnail'] == 'true') {
            config = source.getThumbnailLoadingConfig?.call(url);
          } else {
            final comicId = headers?['comicId'];
            final epId = headers?['epId'];
            if (comicId != null && epId != null) {
              config = source.getImageLoadingConfig?.call(url, comicId, epId);
            }
          }
        }
      }

      var requestUrl = config?.url ?? url;
      if (requestUrl.contains("s.exhentai.org")) {
        requestUrl = requestUrl.replaceFirst("s.exhentai.org", "ehgt.org");
      }

      bool isEhgt = requestUrl.contains("ehgt.org");
      if (isEhgt) {
        if (_ehgtLoading < 3) {
          _ehgtLoading++;
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          while (_ehgtLoading > 2) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
          _ehgtLoading++;
        }
      }

      final requestMethod = config?.method ?? 'GET';
      final requestHeaders =
          config?.headers ?? Map<String, String>.from(headers ?? {});

      // Merge headers if config.headers is not null
      if (config?.headers != null && headers != null) {
        requestHeaders.addAll(headers);
        requestHeaders.addAll(config!.headers!);
      }

      // Add default User-Agent if missing
      if (!requestHeaders.containsKey('User-Agent') &&
          !requestHeaders.containsKey('user-agent')) {
        requestHeaders['User-Agent'] = webUA;
      }

      // Strip meta fields
      requestHeaders.remove('sourceKey');
      requestHeaders.remove('isThumbnail');
      requestHeaders.remove('comicId');
      requestHeaders.remove('epId');

      final requestData = config?.data;

      final response = await _dio.request<ResponseBody>(
        requestUrl,
        data: requestData,
        options: Options(
          method: requestMethod,
          headers: requestHeaders,
          responseType: ResponseType.stream,
        ),
      );

      if (isEhgt) {
        _ehgtLoading--;
      }

      return PicaDioFileServiceResponse(response, config?.onResponse);
    } catch (e) {
      if (url.contains("ehgt.org") || url.contains("s.exhentai.org")) {
        _ehgtLoading--;
      }
      Log.e("PicaHttpFileService Error: $url, $e");
      rethrow;
    }
  }
}

class PicaDioFileServiceResponse implements FileServiceResponse {
  final Response<ResponseBody> _response;
  final dynamic _onResponse;

  PicaDioFileServiceResponse(this._response, [this._onResponse]);

  @override
  Stream<List<int>> get content {
    if (_onResponse == null) {
      return _response.data!.stream;
    } else {
      // If we have onResponse, we must download the whole thing first as it's a JSInvokable usually
      return Stream.fromFuture(() async {
        List<int> imageData = [];
        await for (var data in _response.data!.stream) {
          imageData.addAll(data);
        }
        final result = (_onResponse as JSInvokable)(
          Uint8List.fromList(imageData),
        );
        if (result is Uint8List) {
          return result.toList();
        }
        return imageData;
      }());
    }
  }

  @override
  int get contentLength => _getContentLength();

  @override
  DateTime get validTill {
    return DateTime.now().add(const Duration(days: 7));
  }

  @override
  String? get eTag => _response.headers.value(io.HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    final contentType = _response.headers.value(
      io.HttpHeaders.contentTypeHeader,
    );
    if (contentType != null) {
      if (contentType.contains('image/jpeg')) return '.jpg';
      if (contentType.contains('image/png')) return '.png';
      if (contentType.contains('image/gif')) return '.gif';
      if (contentType.contains('image/webp')) return '.webp';
    }
    return '.jpg';
  }

  @override
  int get statusCode => _response.statusCode ?? 200;

  int _getContentLength() {
    if (_onResponse != null) return -1;
    try {
      return int.parse(
        _response.headers.value(io.HttpHeaders.contentLengthHeader) ?? "-1",
      );
    } catch (e) {
      return -1;
    }
  }
}

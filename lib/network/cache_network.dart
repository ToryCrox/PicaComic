import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pica_comic/foundation/cache_manager.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'network_client_manager.dart';

///缓存网络请求, 仅提供get方法, 其它的没有意义
class CachedNetwork {
  Future<CachedNetworkRes<String>> get(
    String url,
    BaseOptions options, {
    CacheExpiredTime expiredTime = CacheExpiredTime.short,
    CookieJarSql? cookieJar,
    bool log = true,
    bool http2 = false,
    CancelToken? cancelToken,
  }) async {
    // 保留旧参数以兼容漫画源调用方，实际请求统一使用共享 API Dio。
    final key = url;
    if (expiredTime != CacheExpiredTime.no) {
      var cache = await CacheManager().findCache(key);
      if (cache != null) {
        var file = cache.file;
        return CachedNetworkRes(await file.readAsString(), 200, url);
      }
    }
    options.responseType = ResponseType.bytes;
    final requestOptions = Options(
      method: 'GET',
      headers: options.headers,
      responseType: ResponseType.bytes,
      sendTimeout: options.sendTimeout,
      receiveTimeout: options.receiveTimeout,
      followRedirects: options.followRedirects,
      maxRedirects: options.maxRedirects,
      validateStatus: options.validateStatus,
      receiveDataWhenStatusError: options.receiveDataWhenStatusError,
      extra: {
        if (cookieJar != null) NetworkCookieInterceptor.cookieJarKey: cookieJar,
      },
    );
    final res = await networkClientManager.apiDio.get<Uint8List>(
      url,
      options: requestOptions,
      cancelToken: cancelToken,
    );
    if (res.data == null && !url.contains("random")) {
      throw Exception("Empty data");
    }
    if (expiredTime != CacheExpiredTime.no) {
      await CacheManager().writeCache(
        key,
        res.data!,
        Duration(milliseconds: expiredTime.time),
      );
    }
    return CachedNetworkRes(
      utf8.decode(res.data!, allowMalformed: true),
      res.statusCode,
      res.realUri.toString(),
      res.headers.map,
    );
  }

  void delete(String url) async {
    await CacheManager().delete(url);
  }
}

enum CacheExpiredTime {
  no(-1),
  short(86400000),
  long(604800000),
  persistent(0);

  ///过期时间, 单位为毫秒
  final int time;

  const CacheExpiredTime(this.time);
}

class CachedNetworkRes<T> {
  T data;
  int? statusCode;
  Map<String, List<String>> headers;
  String url;

  CachedNetworkRes(
    this.data,
    this.statusCode,
    this.url, [
    this.headers = const {},
  ]);
}

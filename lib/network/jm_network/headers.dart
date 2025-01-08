import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

String get jmApiUA {
  return "Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.0.0 Mobile Safari/537.36";
}

String get jmImgUA {
  return "Dalvik/2.1.0 (Linux; Android 10; K)";
}

const _jmVersion = "1.7.5";

const _jmAuthKey = "18comicAPPContent";

BaseOptions getHeader(int time,
    {bool post = false, Map<String, String>? headers, bool byte = true}) {
  var token = md5.convert(const Utf8Encoder().convert("$time$_jmAuthKey"));

  return BaseOptions(
      receiveDataWhenStatusError: true,
      connectTimeout: const Duration(seconds: 8),
      responseType: byte ? ResponseType.bytes : null,
      headers: {
        "token": token.toString(),
        "tokenparam": "$time,$_jmVersion",
        "Connection": "Keep-Alive",
        "user-agent": jmApiUA,
        "accept-encoding": "gzip",
        ...headers ?? {},
        if (post) "Content-Type": "application/x-www-form-urlencoded"
      });
}
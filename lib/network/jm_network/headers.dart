import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'dart:math' as math;
import 'jm_network.dart';

var _device = '';

String get device {
  // 生成随机的设备标识符
  if(_device.isEmpty) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    var random = math.Random();
    for (var i = 0; i < 6; i++) {
      _device += chars[random.nextInt(chars.length)];
    }
  }
  return _device;
}

String _build = "AP3A.241105.008";

String get jmApiUA {
  return "Mozilla/5.0 (Linux; Android 15; $device Build/$_build; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.0.0 Mobile Safari/537.36";
}

String get jmImgUA {
  return "Dalvik/2.1.0 (Linux; V; Android 15; $device Build/$_build)";
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
        "Host": JmNetwork().baseUrl.replaceFirst("https://", ""),
        ...headers ?? {},
        if (post) "Content-Type": "application/x-www-form-urlencoded"
      });
}
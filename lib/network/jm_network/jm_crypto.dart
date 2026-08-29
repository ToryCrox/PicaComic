import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/ecb.dart';

/// JM API 响应解密所需的请求时间戳元数据键。
const jmResponseTimeExtraKey = '__pica_jm_response_time__';

/// JM API 响应数据的固定密钥片段。
const jmResponseSecret = '185Hcomic3PAPP7R';

/// 解密 JM 返回的 data 字段。
///
/// JM 会先对响应内容进行 Base64 编码，再使用
/// `AES-ECB(MD5(secret).toString())` 加密。其中 MD5 的十六进制字符串会
/// 作为 32 字节的 AES-256 密钥使用。
String decryptJmData(String input, String secret) {
  final key = md5.convert(utf8.encode(secret)).toString();
  final data = base64Decode(input);
  if (data.isEmpty || data.length % 16 != 0) {
    throw const FormatException('Invalid JM encrypted data length');
  }

  final cipher = ECBBlockCipher(AESEngine())
    ..init(false, KeyParameter(utf8.encode(key)));
  final plainText = Uint8List(data.length);
  var offset = 0;
  while (offset < data.length) {
    offset += cipher.processBlock(data, offset, plainText, offset);
  }

  final result = utf8.decode(plainText, allowMalformed: true);
  for (var i = result.length - 1; i >= 0; i--) {
    if (result[i] == '}' || result[i] == ']') {
      return result.substring(0, i + 1);
    }
  }
  throw const FormatException('JM decrypted data is not JSON');
}

/// 尝试解密一份 JM API 响应，失败时返回 null 以保留原始日志内容。
Object? decodeJmApiResponse({
  required Object? body,
  required int? statusCode,
  required Object? responseTime,
}) {
  if (statusCode != 200) return null;
  final time = _parseResponseTime(responseTime);
  final text = _decodeResponseText(body);
  if (time == null || text == null) return null;

  try {
    final envelope = jsonDecode(text);
    if (envelope is! Map) return null;
    final data = envelope['data'];
    if (data is! String || data.isEmpty) return null;

    final decrypted = decryptJmData(data, '$time$jmResponseSecret');
    return jsonDecode(decrypted);
  } catch (_) {
    return null;
  }
}

int? _parseResponseTime(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String? _decodeResponseText(Object? body) {
  if (body is String) return body;
  if (body is Uint8List || body is List<int>) {
    return utf8.decode(body as List<int>, allowMalformed: false);
  }
  return null;
}

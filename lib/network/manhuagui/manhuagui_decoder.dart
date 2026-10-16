import 'dart:convert';

/// 漫画柜目录压缩与阅读数据解包；不执行来自网页的 JavaScript。
abstract final class ManhuaguiDecoder {
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';

  /// 解压站点 LZString 的 Base64 数据。
  static String decompress(String input) {
    if (input.isEmpty) return '';
    var offset = 0;
    var position = 0;
    var value = 0;
    int bits(int count) {
      var result = 0;
      for (var bit = 0; bit < count; bit++) {
        if (position == 0) {
          if (offset >= input.length) throw const FormatException('漫画柜压缩数据不完整');
          value = _alphabet.indexOf(input[offset++]);
          if (value < 0) throw const FormatException('漫画柜压缩数据无效');
          position = 32;
        }
        if ((value & position) != 0) result |= 1 << bit;
        position >>= 1;
      }
      return result;
    }

    final dictionary = <String>['', '', ''];
    final first = bits(2);
    if (first == 2) return '';
    if (first > 1) throw const FormatException('漫画柜压缩头无效');
    var previous = String.fromCharCode(bits(first == 0 ? 8 : 16));
    dictionary.add(previous);
    final output = StringBuffer(previous);
    var enlargeIn = 4;
    var numBits = 3;
    while (output.length < 20 * 1024 * 1024) {
      var code = bits(numBits);
      if (code == 2) return output.toString();
      if (code == 0 || code == 1) {
        dictionary.add(String.fromCharCode(bits(code == 0 ? 8 : 16)));
        code = dictionary.length - 1;
        enlargeIn--;
      }
      if (enlargeIn == 0) {
        enlargeIn = 1 << numBits++;
      }
      final String entry;
      if (code < dictionary.length) {
        entry = dictionary[code];
      } else if (code == dictionary.length) {
        entry = previous + previous[0];
      } else {
        throw const FormatException('漫画柜压缩字典无效');
      }
      output.write(entry);
      dictionary.add(previous + entry[0]);
      previous = entry;
      if (--enlargeIn == 0) enlargeIn = 1 << numBits++;
    }
    throw const FormatException('漫画柜压缩数据过大');
  }

  /// 读取 JavaScript 字符串字面量中的标准转义。
  static String stringLiteral(String literal) {
    final output = StringBuffer();
    for (var i = 1; i < literal.length - 1; i++) {
      final char = literal[i];
      if (char != r'\') {
        output.write(char);
        continue;
      }
      final escaped = literal[++i];
      if (escaped == 'x' || escaped == 'u') {
        final length = escaped == 'x' ? 2 : 4;
        output.writeCharCode(
          int.parse(literal.substring(i + 1, i + 1 + length), radix: 16),
        );
        i += length;
      } else {
        output.write(switch (escaped) {
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          'b' => '\b',
          'f' => '\f',
          _ => escaped,
        });
      }
    }
    return output.toString();
  }

  /// 解包 radix 62 字典，兼容普通 split 和 LZString 压缩字典。
  static String unpack(String source) {
    final match = RegExp(
      r'''\}\(\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")''',
    ).firstMatch(source);
    if (match == null) throw const FormatException('找不到漫画柜章节数据');
    final payload = stringLiteral(match[1]!);
    final radix = int.parse(match[2]!);
    final count = int.parse(match[3]!);
    if (radix < 2 || radix > 62 || count > 100000) {
      throw const FormatException('漫画柜字典参数无效');
    }
    var dictionary = stringLiteral(match[4]!);
    final suffix = source.substring(match.end);
    if (!suffix.startsWith('.split(') && !suffix.startsWith("['split']")) {
      dictionary = decompress(dictionary);
    }
    final words = dictionary.split('|');
    String token(int number) {
      const chars =
          '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
      return number < radix
          ? chars[number]
          : token(number ~/ radix) + chars[number % radix];
    }

    final replacements = <String, String>{
      for (var i = 0; i < count && i < words.length; i++)
        if (words[i].isNotEmpty) token(i): words[i],
    };
    return payload.replaceAllMapped(
      RegExp(r'\b[0-9a-zA-Z]+\b'),
      (m) => replacements[m[0]] ?? m[0]!,
    );
  }

  /// 提取 imgData 的 JSON 参数，拒绝执行脚本及非 JSON 表达式。
  static Map<String, dynamic> imageData(String source) {
    final decoded = source.contains('SMH.imgData(') ? source : unpack(source);
    final start = decoded.indexOf('SMH.imgData(');
    if (start < 0) throw const FormatException('漫画柜图片数据缺失');
    final jsonStart = decoded.indexOf('{', start);
    var depth = 0;
    var quoted = false;
    var escape = false;
    for (var i = jsonStart; i < decoded.length; i++) {
      final char = decoded[i];
      if (quoted) {
        if (escape) {
          escape = false;
        } else if (char == r'\') {
          escape = true;
        } else if (char == '"') {
          quoted = false;
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        return jsonDecode(decoded.substring(jsonStart, i + 1))
            as Map<String, dynamic>;
      }
    }
    throw const FormatException('漫画柜图片数据不完整');
  }
}

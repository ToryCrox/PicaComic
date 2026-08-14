import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/tools/io_extensions.dart';

void main() {
  group('sanitizeFileName', () {
    test('保留 Windows 支持的弯引号和括号', () {
      const name =
          '[Toyo] Adam’s Sweet Agony (Ch.1-80) [English] {Hiperdex.com}';

      expect(sanitizeFileName(name), name);
    });

    test('替换非法字符和控制字符并清理首尾', () {
      expect(sanitizeFileName(' .a<b>:c\u0001?. '), 'a b c');
    });

    test('规避 Windows 保留设备名', () {
      expect(sanitizeFileName('CON'), '_CON');
      expect(sanitizeFileName('LPT1.txt'), '_LPT1.txt');
      expect(sanitizeFileName('normal.txt'), 'normal.txt');
    });

    test('按 UTF-8 字节安全截断且不拆分 emoji', () {
      expect(sanitizeFileName('ab😀cd', 6), 'ab😀');
      expect(
        utf8.encode(sanitizeFileName('中文标题', 7)).length,
        lessThanOrEqualTo(7),
      );
    });
  });

  group('buildDownloadDirectoryName', () {
    test('限制整个下载目录名长度', () {
      final directory = buildDownloadDirectoryName(
        type: 'ehentai',
        id: '3160707',
        title: List.filled(200, 'a').join(),
      );

      expect(
        utf8.encode(directory).length,
        lessThanOrEqualTo(maxDownloadDirectoryNameBytes),
      );
      expect(directory, startsWith('[ehentai][3160707]'));
    });

    test('示例标题无需截断', () {
      final directory = buildDownloadDirectoryName(
        type: 'ehentai',
        id: '3160707',
        title: '[Toyo] Adam’s Sweet Agony (Ch.1-80) [English] {Hiperdex.com}',
      );

      expect(
        directory,
        '[ehentai][3160707][Toyo] Adam’s Sweet Agony (Ch.1-80) '
        '[English] {Hiperdex.com}',
      );
    });
  });
}

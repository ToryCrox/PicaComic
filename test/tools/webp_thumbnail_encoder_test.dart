import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:pica_comic/tools/cwebp_tool.dart';
import 'package:pica_comic/tools/webp_thumbnail_encoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('横图裁左右、长图裁上下，输出尺寸保持宽高 9:16', () {
    const options = WebpProcessingOptions();
    final wide = options.targetFor(1600, 900);
    expect([wide.x, wide.y, wide.width, wide.height], [548, 2, 504, 896]);
    expect([wide.targetWidth, wide.targetHeight], [432, 768]);
    final tall = options.targetFor(900, 4000);
    expect([tall.x, tall.y, tall.width, tall.height], [0, 1200, 900, 1600]);
    final small = options.targetFor(180, 320);
    expect([small.targetWidth, small.targetHeight], [180, 320]);
    expect(() => options.targetFor(0, 1), throwsArgumentError);
  });

  test('工具缺失给出明确失败，不生成伪 WebP', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'pica_missing_webp_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final encoder = WebpThumbnailEncoder(
      executablePath: path.join(temporary.path, 'missing.exe'),
    );
    final output = File(path.join(temporary.path, 'result.webp'));
    await expectLater(
      encoder.encode(File('missing.png'), output),
      throwsUnsupportedError,
    );
    expect(await output.exists(), isFalse);
  });

  test('真实工具输出居中裁切 WebP，保留透明通道且不修改原图', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'pica_encode_webp_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final source = image.Image(width: 900, height: 900, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(0, 0, 255, 255));
    image.fillRect(
      source,
      x1: 300,
      y1: 0,
      x2: 600,
      y2: 899,
      color: image.ColorRgba8(255, 0, 0, 255),
    );
    for (var y = 420; y < 480; y++) {
      for (var x = 420; x < 480; x++) {
        source.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final original = File(path.join(temporary.path, '中文 原图.png'));
    final bytes = image.encodePng(source);
    await original.writeAsBytes(bytes);
    final output = File(path.join(temporary.path, 'thumbnail.webp'));
    await WebpThumbnailEncoder().encode(original, output);
    expect(await WebpThumbnailEncoder.isValid(output), isTrue);
    final decoded = image.decodeWebP(await output.readAsBytes())!;
    expect([decoded.width, decoded.height], [432, 768]);
    expect(decoded.getPixel(216, 384).a, 0);
    expect(decoded.getPixel(216, 100).r, greaterThan(230));
    expect(decoded.getPixel(0, 100).b, greaterThan(230));
    expect(await original.readAsBytes(), bytes);
  }, skip: !Platform.isWindows);

  test('超时终止进程，不等待进程自行结束', () async {
    final tool = CwebpTool(
      path.join(
        Platform.environment['SystemRoot']!,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      ),
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      tool.run(['-NoProfile', '-Command', 'Start-Sleep -Seconds 10']),
      throwsA(isA<Exception>()),
    );
  }, skip: !Platform.isWindows);

  test('动图首帧和其他裁切比例使用通用接口，不保留动画', () async {
    final temporary = await Directory.systemTemp.createTemp('pica_gif_webp_');
    addTearDown(() => temporary.delete(recursive: true));
    final first = image.Image(width: 160, height: 90);
    image.fill(first, color: image.ColorRgb8(255, 0, 0));
    final second = image.Image(width: 160, height: 90);
    image.fill(second, color: image.ColorRgb8(0, 0, 255));
    final gif = image.GifEncoder()
      ..addFrame(first)
      ..addFrame(second);
    final original = File(path.join(temporary.path, 'animation.gif'));
    await original.writeAsBytes(gif.finish()!);
    final encoder = WebpThumbnailEncoder();
    final output = File(path.join(temporary.path, 'first.webp'));
    await encoder.encode(original, output);
    final decoded = image.decodeWebP(await output.readAsBytes())!;
    expect(decoded.numFrames, 1);
    expect(decoded.width * 16, decoded.height * 9);
    expect(
      decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).r,
      greaterThan(230),
    );
    const options = WebpProcessingOptions(
      cropWidth: 4,
      cropHeight: 3,
      maxWidth: 80,
      maxHeight: 60,
    );
    final different = File(path.join(temporary.path, 'different.webp'));
    await encoder.encode(original, different, options: options);
    expect(
      await WebpThumbnailEncoder.isValid(different, options: options),
      isTrue,
    );
    expect(await WebpThumbnailEncoder.isValid(different), isFalse);
  }, skip: !Platform.isWindows);
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;

import 'cwebp_tool.dart';
import 'webp_processing_options.dart';

export 'webp_processing_options.dart';

/// 从 pixez_flutter 静态处理核心移植的独立 WebP 编码器。
class WebpThumbnailEncoder {
  WebpThumbnailEncoder({this.executablePath});

  final String? executablePath;
  final _waiters = <Completer<void>>[];
  int _active = 0;

  /// 限制并发为两个；调用方负责将临时输出原子替换到最终位置。
  Future<void> encode(
    File source,
    File output, {
    WebpProcessingOptions options = const WebpProcessingOptions(),
  }) async {
    if (_active >= 2) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    try {
      await _encode(source, output, options);
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  /// 检查实际格式和可解码性，不接受扩展名伪装或损坏的缓存。
  static Future<bool> isValid(
    File file, {
    WebpProcessingOptions options = const WebpProcessingOptions(),
  }) async {
    if (!await file.exists()) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(12);
      if (header.length != 12 ||
          String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WEBP') {
        return false;
      }
    } finally {
      await handle.close();
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * options.cropHeight !=
              descriptor.height * options.cropWidth ||
          descriptor.width > options.maxWidth ||
          descriptor.height > options.maxHeight) {
        return false;
      }
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// 静态图片直接交给原生工具；动图及其他格式提取首帧。
  Future<void> _encode(
    File source,
    File output,
    WebpProcessingOptions options,
  ) async {
    final tool = await CwebpTool.resolve(preferredPath: executablePath);
    if (tool == null) throw UnsupportedError('当前平台未提供 WebP 编码工具');
    await output.parent.create(recursive: true);
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    final intermediate = File('${output.path}.png');
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(source.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final crop = options.targetFor(descriptor.width, descriptor.height);
      var input = source;
      var direct = const [
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
      ].contains(path.extension(source.path).toLowerCase());
      final codec = await descriptor.instantiateCodec(
        targetWidth: 1,
        targetHeight: 1,
      );
      try {
        direct =
            direct &&
            codec.frameCount == 1 &&
            descriptor.width >= options.cropWidth &&
            descriptor.height >= options.cropHeight;
      } finally {
        codec.dispose();
      }
      if (!direct) {
        await _firstFrame(descriptor, intermediate, crop, options);
        input = intermediate;
      }
      final result = await tool.run([
        '-q',
        '${options.quality}',
        '-m',
        '4',
        '-mt',
        '-metadata',
        'none',
        if (direct) ...[
          '-crop',
          '${crop.x}',
          '${crop.y}',
          '${crop.width}',
          '${crop.height}',
          '-resize',
          '${crop.targetWidth}',
          '${crop.targetHeight}',
        ],
        '-o',
        output.path,
        '--',
        input.path,
      ]);
      if (result.exitCode != 0 || !await isValid(output, options: options)) {
        throw StateError('WebP 编码失败：${result.stderr}');
      }
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
      if (await intermediate.exists()) await intermediate.delete();
    }
  }

  /// 限制首帧解码体积，中心裁切后输出小尺寸 PNG 供 cwebp 编码。
  Future<void> _firstFrame(
    ui.ImageDescriptor descriptor,
    File file,
    WebpCrop target,
    WebpProcessingOptions options,
  ) async {
    final scale = math.min(
      1.0,
      2048 / math.max(descriptor.width, descriptor.height),
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    ui.Image? frame;
    ui.Image? result;
    ui.Picture? picture;
    try {
      frame = (await codec.getNextFrame()).image;
      final ratio = options.cropWidth / options.cropHeight;
      var cropWidth = frame.width.toDouble();
      var cropHeight = frame.height.toDouble();
      if (cropWidth / cropHeight > ratio) {
        cropWidth = cropHeight * ratio;
      } else {
        cropHeight = cropWidth / ratio;
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        frame,
        ui.Rect.fromLTWH(
          (frame.width - cropWidth) / 2,
          (frame.height - cropHeight) / 2,
          cropWidth,
          cropHeight,
        ),
        ui.Rect.fromLTWH(
          0,
          0,
          target.targetWidth.toDouble(),
          target.targetHeight.toDouble(),
        ),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();
      result = await picture.toImage(target.targetWidth, target.targetHeight);
      final bytes = await result.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('无法提取图片首帧');
      await file.writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      result?.dispose();
      picture?.dispose();
      frame?.dispose();
      codec.dispose();
    }
  }
}

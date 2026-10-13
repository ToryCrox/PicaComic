import 'dart:math' as math;

/// 从 pixez_flutter 移植的 WebP 编码及缩放参数。
class WebpProcessingOptions {
  const WebpProcessingOptions({
    this.quality = 80,
    this.maxWidth = 432,
    this.maxHeight = 768,
    this.cropWidth = 9,
    this.cropHeight = 16,
  });

  final int quality;
  final int maxWidth;
  final int maxHeight;
  final int cropWidth;
  final int cropHeight;

  /// 计算最大居中裁切区域和不放大的整比例输出尺寸。
  WebpCrop targetFor(int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        quality < 0 ||
        quality > 100 ||
        maxWidth < cropWidth ||
        maxHeight < cropHeight ||
        cropWidth <= 0 ||
        cropHeight <= 0) {
      throw ArgumentError('WebP 尺寸或质量无效');
    }
    final units = math.min(width ~/ cropWidth, height ~/ cropHeight);
    // 极小图片不足一个比例单元时使用最小输出，避免零像素裁切。
    final cropW = units > 0 ? units * cropWidth : width;
    final cropH = units > 0 ? units * cropHeight : height;
    final targetUnits = math.max(
      1,
      math.min(units, math.min(maxWidth ~/ cropWidth, maxHeight ~/ cropHeight)),
    );
    return WebpCrop(
      x: (width - cropW) ~/ 2,
      y: (height - cropH) ~/ 2,
      width: cropW,
      height: cropH,
      targetWidth: targetUnits * cropWidth,
      targetHeight: targetUnits * cropHeight,
    );
  }
}

/// 编码前的中心裁切及输出尺寸。
class WebpCrop {
  const WebpCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.targetWidth,
    required this.targetHeight,
  });
  final int x;
  final int y;
  final int width;
  final int height;
  final int targetWidth;
  final int targetHeight;
}

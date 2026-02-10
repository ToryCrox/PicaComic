import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as Path;
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart' hide Size;
import 'package:pica_comic/tools/shared_compute.dart';
import 'package:worker_manager/worker_manager.dart';

// 图片尺寸缓存，用于存储已加载的图片尺寸信息
Map<String, ImageSizeInfo> _imageSizeCache = {};

/// 计算图片尺寸
///
/// 此函数接收一组图片路径，并异步计算每张图片的尺寸信息
/// 它首先检查图片尺寸是否已经缓存，如果是，则直接返回缓存的信息
/// 对于未缓存的图片，它将使用共享计算资源进行计算，并更新缓存
///
/// [imagePaths] 一组图片的路径
Stream<Map<String, ImageSizeInfo>> computeImageSizes(
    List<String> imagePaths) async* {
  // 初始化图片尺寸结果集
  Map<String, ImageSizeInfo> imageSizeResult = <String, ImageSizeInfo>{};
  // 需要计算尺寸的图片路径列表
  final needsCompute = <String>[];
  // 需要检查缓存有效性的图片路径列表
  final checkList = <String>[];

  for (var imagePath in imagePaths) {
    // 调整图片路径，去除可能的"file://"前缀
    final imagePathKey = adjustImagePath(imagePath);
    // 尝试从缓存中获取图片尺寸信息
    var imageSizeInfo = _imageSizeCache[imagePathKey];
    if (imageSizeInfo != null) {
      // 如果缓存存在，则添加到结果集中
      imageSizeResult[imagePath] = imageSizeInfo;
      checkList.add(imagePath);
    } else {
      // 如果缓存不存在，则添加到需要计算尺寸的列表中
      needsCompute.add(imagePath);
    }
  }

  // 如果结果集不为空，则立即返回当前结果集
  if (imageSizeResult.isNotEmpty) {
    yield imageSizeResult;
  }

  // 检查缓存的图片是否有效
  if (checkList.isNotEmpty) {
    const checkBatchSize = 50;
    for (int i = 0; i < checkList.length; i += checkBatchSize) {
      final end = i + checkBatchSize > checkList.length
          ? checkList.length
          : i + checkBatchSize;
      final list = checkList.sublist(i, end);

      await Future.wait(list.map((imagePath) async {
        final imagePathKey = adjustImagePath(imagePath);
        final imageSizeInfo = _imageSizeCache[imagePathKey];
        if (imageSizeInfo == null) return;

        try {
          final file = File(imagePathKey);
          if (!file.existsSync()) {
            _imageSizeCache.remove(imagePathKey);
            needsCompute.add(imagePath);
            return;
          }
          final stat = await file.stat();
          if (stat.size != imageSizeInfo.fileSize ||
              stat.modified.millisecondsSinceEpoch !=
                  imageSizeInfo.lastModifiedTime) {
            _imageSizeCache.remove(imagePathKey);
            needsCompute.add(imagePath);
          }
        } catch (e) {
          _imageSizeCache.remove(imagePathKey);
          needsCompute.add(imagePath);
        }
      }));
    }
  }

  const batchSize = 20;
  // 分批处理需要计算尺寸的图片路径，每批最多10张
  for (int i = 0; i < needsCompute.length; i += batchSize) {
    final end = i + batchSize > needsCompute.length
        ? needsCompute.length
        : i + batchSize;
    final list = needsCompute.sublist(i, end).toList();
    // 使用共享计算资源并行计算图片尺寸
    final result = await sharedCompute(loadImageSizes, list);
    // 更新缓存并合并结果
    for (var imagePath in result.keys) {
      final imagePathKey = adjustImagePath(imagePath);
      _imageSizeCache[imagePathKey] = result[imagePath]!;
    }
    yield result;
    debugPrint("computeImageSizes: ${result.length}");
  }
}

/// 加载图片尺寸
///
/// 此函数接收一组图片路径，并返回这些图片的尺寸信息
/// 它遍历每个图片路径，计算其尺寸，并将信息存储在映射中返回
///
/// [imageUrs] 一组图片的路径
@pragma('vm:entry-point')
Map<String, ImageSizeInfo> loadImageSizes(List<String> imageUrs) {
  final imageSizes = <String, ImageSizeInfo>{};
  for (var i = 0; i < imageUrs.length; i++) {
    final url = imageUrs[i];
    // 调整图片路径，去除可能的"file://"前缀
    String imageFilePath = adjustImagePath(url);
    final file = File(imageFilePath);
    try {
      // 使用ImageSizeGetter库计算图片尺寸
      final sizeResult = ImageSizeGetter.getSizeResult(FileInput(file));
      // 将图片尺寸信息添加到结果集中
      imageSizes[url] = ImageSizeInfo(
        imagePath: file.path,
        width: sizeResult.size.width.toDouble(),
        height: sizeResult.size.height.toDouble(),
        fileSize: file.lengthSync(),
        lastModifiedTime: file.lastModifiedSync().millisecondsSinceEpoch,
      );
    } catch (e) {
      // 打印错误信息，方便调试
      debugPrint("loadImageSizes error: $e");
    }
  }
  return imageSizes;
}

/// 调整图片路径
///
/// 此函数接收一个图片路径，如果路径以"file://"开头，则去除这个前缀
/// 这是为了统一路径格式，确保路径在不同环境下的一致性
///
/// [imagePath] 图片的路径
String adjustImagePath(String imagePath) {
  String absolutePath = imagePath;
  if (imagePath.startsWith("file://")) {
    absolutePath = imagePath.substring(7);
  }
  return Path.canonicalize(absolutePath);
}

/// 图片尺寸信息类
///
/// 此类用于存储图片的路径、尺寸和最后修改时间
class ImageSizeInfo {
  final String imagePath;
  final double width;
  final double height;
  final int fileSize;
  final int lastModifiedTime;

  Size get size => Size(width, height);

  ImageSizeInfo({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.lastModifiedTime,
  });
}

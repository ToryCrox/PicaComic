import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:pica_comic/tools/shared_compute.dart';

Map<String, ImageSizeInfo> _imageSizeCache = {};

Stream<Map<String, ImageSizeInfo>> computeImageSizes(
    List<String> imagePaths) async* {
  Map<String, ImageSizeInfo> imageSizeResult = <String, ImageSizeInfo>{};

  final needsCompute = <String>[];
  for (var imagePath in imagePaths) {
    final imagePathKey = _adjustImagePath(imagePath);
    var imageSizeInfo = _imageSizeCache[imagePathKey];
    if (imageSizeInfo != null) {
      imageSizeResult[imagePath] = imageSizeInfo;
    } else {
      needsCompute.add(imagePath);
    }
  }
  if (imageSizeResult.isNotEmpty) {
    yield imageSizeResult;
  }

  for (int i = 0; i < needsCompute.length; i += 10) {
    final end = i + 10 > needsCompute.length
        ? needsCompute.length
        : i + 10;
    final list = needsCompute.sublist(i, end).toList();
    final result = await sharedCompute(_loadImageSizes, list);
    for (var imagePath in result.keys) {
      final imagePathKey = _adjustImagePath(imagePath);
      _imageSizeCache[imagePath] = result[imagePathKey]!;
    }
    yield result;
  }
}

Map<String, ImageSizeInfo> _loadImageSizes(List<String> imageUrs) {
  final imageSizes = <String, ImageSizeInfo>{};
  for (var i = 0; i < imageUrs.length; i++) {
    final url = imageUrs[i];
    String imageFilePath = _adjustImagePath(url);
    final file = File(imageFilePath);
    try {
      final sizeResult = ImageSizeGetter.getSizeResult(FileInput(file));
      imageSizes[url] = ImageSizeInfo(
        imagePath: file.path,
        size: Size(sizeResult.size.width, sizeResult.size.height),
        lastModifiedTime: file.lastModifiedSync().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint("loadImageSizes error: $e");
    }
  }
  return imageSizes;
}

String _adjustImagePath(String imagePath) {
  if (imagePath.startsWith("file://")) {
    return imagePath.substring(7);
  }
  return imagePath;
}

class ImageSizeInfo {
  final String imagePath;
  final Size size;
  final int lastModifiedTime;

  ImageSizeInfo({
    required this.imagePath,
    required this.size,
    required this.lastModifiedTime,
  });
}

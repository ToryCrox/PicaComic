import 'package:flutter/material.dart';
import 'package:pica_comic/components/components.dart';

/// 网络日志图片缩略图的解码宽度上限。
const networkArtifactThumbnailMemCacheWidth = 36;

/// 网络日志图片放大预览的解码宽度上限，避免直接按原图尺寸解码。
const networkArtifactPreviewMemCacheWidth = 360;

/// 构建网络日志中的本地图片预览。
///
/// [PicaImage] 的缓存管理器支持 `file://` 本地路径，同时统一处理
/// 图片解码缓存和错误状态。所有调用都显式限制 [memCacheWidth]，避免
/// 网络响应图片尺寸过大时造成内存峰值。
Widget buildNetworkArtifactPreview(
  String path, {
  BoxFit fit = BoxFit.contain,
  int memCacheWidth = networkArtifactPreviewMemCacheWidth,
}) {
  final url = path.startsWith('file://') ? path : Uri.file(path).toString();
  return PicaImage(
    url: url,
    fit: fit,
    memCacheWidth: memCacheWidth,
    fade: false,
    errorWidget: (_, _, _) => const Center(
      child: Text(
        '文件已不存在或无法预览',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ),
  );
}

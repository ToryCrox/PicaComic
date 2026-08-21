import 'package:flutter/material.dart';

/// 构建本地网络产物预览。
Widget buildNetworkArtifactPreview(String path, {BoxFit fit = BoxFit.contain}) {
  return const Center(
    child: Text(
      '当前平台不支持本地图片预览',
      style: TextStyle(fontSize: 12, color: Colors.grey),
    ),
  );
}

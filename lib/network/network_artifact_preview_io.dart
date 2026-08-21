import 'dart:io';

import 'package:flutter/material.dart';

/// 构建本地网络产物预览。
Widget buildNetworkArtifactPreview(String path, {BoxFit fit = BoxFit.contain}) {
  final file = File(path);
  if (!file.existsSync()) {
    return const Center(
      child: Text('文件已不存在', style: TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }
  return Image.file(
    file,
    fit: fit,
    errorBuilder: (_, _, _) {
      return const Center(
        child: Text(
          '图片无法预览',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    },
  );
}

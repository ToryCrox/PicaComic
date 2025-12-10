import 'dart:io';
import 'package:flutter/services.dart';

/// Web 静态资源处理器
/// 
/// 提供 Web 构建产物的静态文件服务
class WebHandler {
  /// 静态资源目录（package 资源路径）
  static const String webAssetsPath = 'packages/log_viewer_server/assets/web';
  
  /// MIME 类型映射
  static const Map<String, String> mimeTypes = {
    'html': 'text/html',
    'js': 'application/javascript',
    'css': 'text/css',
    'json': 'application/json',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'eot': 'application/vnd.ms-fontobject',
  };
  
  /// 处理静态资源请求
  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    
    try {
      // 默认返回 index.html
      final filePath = path == '/' || path.isEmpty
          ? '$webAssetsPath/index.html'
          : '$webAssetsPath$path';
      
      // 从资源包加载文件
      final data = await _loadAsset(filePath);
      
      if (data != null) {
        final contentType = _getContentType(filePath);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('Content-Type', contentType)
          ..headers.set('Cache-Control', 'no-cache');
        
        request.response.add(data);
        await request.response.close();
      } else {
        // 文件不存在，返回 404
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.set('Content-Type', 'text/plain');
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.set('Content-Type', 'text/plain');
      request.response.write('Internal Server Error: $e');
      await request.response.close();
    }
  }
  
  /// 从资源包加载文件
  Future<Uint8List?> _loadAsset(String path) async {
    try {
      // 移除开头的斜杠
      final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
      
      // 使用 rootBundle 加载资源
      final byteData = await rootBundle.load(normalizedPath);
      return byteData.buffer.asUint8List();
    } catch (e) {
      // 资源不存在
      return null;
    }
  }
  
  /// 根据文件路径获取 Content-Type
  String _getContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return mimeTypes[extension] ?? 'application/octet-stream';
  }
}


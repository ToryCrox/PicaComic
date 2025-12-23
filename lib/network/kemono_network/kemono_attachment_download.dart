import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download_model.dart';
import 'package:pica_comic/network/kemono_network/models.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:path/path.dart' as Path;

/// Kemono 附件下载任务
/// 
/// 这个类将 Kemono 附件下载集成到 DownloadManager 中
/// 通过将附件列表映射为"单章节多文件"模型来复用现有的下载基础设施
class KemonoAttachmentDownloadingItem extends DownloadingItem {
  /// 要下载的附件列表
  final List<KemonoFile> files;
  
  /// 自定义下载路径（用户选择的目录）
  final String customDownloadPath;
  
  /// 作者名称（用于创建子目录）
  final String authorName;
  
  /// 发布日期（用于文件名前缀）
  final DateTime? publishedDate;
  
  /// Post ID（用作标识符的一部分）
  final String postId;
  
  /// 封面 URL
  final String? coverUrl;
  
  /// 已下载的文件数量
  int _downloadedFiles = 0;
  
  /// 已下载文件的总大小（字节）
  int _totalDownloadedBytes = 0;
  
  /// 预期的总下载大小（字节，通过 HEAD 请求获取）
  int _totalExpectedBytes = 0;
  
  /// 下载失败的文件列表
  final List<String> _failedFiles = [];
  
  /// Dio 实例（用于下载）
  Dio? _dio;

  KemonoAttachmentDownloadingItem({
    required this.files,
    required this.customDownloadPath,
    required this.authorName,
    required this.postId,
    this.publishedDate,
    this.coverUrl,
    required DownloadProgressCallback onFinish,
    required DownloadProgressCallback onError,
    required DownloadProgressCallbackAsync updateInfo,
    required String id,
  })  : super(onFinish, onError, updateInfo, id, type: DownloadType.other) {
    // Kemono 附件下载不保存到数据库（临时下载任务）
    shouldSaveToDatabase = false;
  }

  @override
  String get cover => coverUrl ?? ''; // 返回封面 URL

  @override
  Map<String, String> get headers => {
    'Referer': 'https://kemono.cr/',
    'Accept': 'text/css',
  };

  @override
  String get title => '[$authorName] ${files.length} 个附件';

  @override
  bool get haveEps => false; // 附件下载没有章节概念

  @override
  int get totalPages {
    // 返回预期的总字节数（如果已获取）
    // 下载管理器会使用这个值显示进度
    return _totalExpectedBytes > 0 ? _totalExpectedBytes : super.totalPages;
  }

  @override
  int get downloadedPages {
    // 返回已下载的字节数
    // 下载管理器会使用这个值显示进度
    return _totalDownloadedBytes;
  }

  @override
  String get path {
    // 覆盖默认路径，使用用户选择的目录
    final sanitizedAuthor = sanitizeFileName(authorName);
    return Path.join(customDownloadPath, sanitizedAuthor);
  }

  @override
  Future<void> downloadCover() async {
    // 附件下载不需要封面，跳过
    return;
  }

  @override
  Future<void> onStart() async {
    // 设置 directory 为作者名（用于路径构建）
    // path getter 会将其与 customDownloadPath 结合
    final sanitizedAuthor = sanitizeFileName(authorName);
    directory = sanitizedAuthor;
    
    // 创建目标目录
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // 调用 super.onStart() 
    // 因为 directory 已经设置，基类会跳过目录创建逻辑
    await super.onStart();
  }

  @override
  Future<Map<int, List<String>>> getLinks() async {
    // 尝试获取文件大小，但不阻塞下载流程
    try {
      await _fetchFileSizes();
    } catch (e) {
      // 获取大小失败不影响下载
      Log.e('Failed to fetch file sizes: $e');
    }
    
    // 将附件列表转换为 URL 列表
    // 使用章节 0 来表示所有附件
    return {
      0: files.map((file) => file.fullUrl).toList(),
    };
  }
  
  /// 通过 HEAD 请求获取所有文件的大小
  Future<void> _fetchFileSizes() async {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
    ));
    
    int totalSize = 0;
    
    for (var file in files) {
      try {
        final response = await _dio!.head(
          file.fullUrl,
          options: Options(
            headers: headers, // 使用相同的 headers
          ),
        );
        
        // 从响应头获取文件大小
        final contentLength = response.headers.value('content-length');
        if (contentLength != null) {
          final size = int.tryParse(contentLength) ?? 0;
          totalSize += size;
        }
      } catch (e) {
        // HEAD 请求失败不影响下载，只是无法提前知道大小
        Log.e('Failed to get size for ${file.name}: $e');
      }
    }
    
    // 保存总大小（用于在下载管理器中显示）
    _totalExpectedBytes = totalSize;
  }

  @override
  Stream<DownloadProgress> downloadImage(String link) async* {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
    ));

    // 从 URL 中找到对应的 KemonoFile
    final file = files.firstWhere(
      (f) => f.fullUrl == link,
      orElse: () => throw Exception('File not found for URL: $link'),
    );

    // 生成日期前缀
    String datePrefix = _getDatePrefix();
    
    // 生成文件名
    String fileName = '$datePrefix${sanitizeFileName(file.name)}';
    
    // 检查文件是否已存在，如果存在则自动重命名
    fileName = _getUniqueFileName(fileName);
    
    final savePath = Path.join(path, fileName);

    int totalBytes = 0;
    int lastReportedBytes = 0; // 用于追踪上次报告的字节数

    try {
      await _dio!.download(
        link,
        savePath,
        onReceiveProgress: (count, total) {
          totalBytes = total > 0 ? total : count;
          
          // 计算当前文件新增的字节数
          final newBytes = count - lastReportedBytes;
          if (newBytes > 0) {
            // 更新总下载字节数（实时更新）
            _totalDownloadedBytes += newBytes;
            
            // 调用 onData() 报告新下载的字节数（用于速度计算）
            onData(newBytes);
            lastReportedBytes = count;
          }
        },
      );

      _downloadedFiles++;
      
      // 注意：_totalDownloadedBytes 已经在 onReceiveProgress 中更新了
      // 这里不需要再累加
      
      // 返回完成的进度
      yield DownloadProgress(
        totalBytes,
        totalBytes,
        link,
        savePath,
      );
    } catch (e, s) {
      Log.e('Kemono 附件下载失败: ${file.name}\n$e', stackTrace: s);
      _failedFiles.add(file.name);
      rethrow;
    }
  }

  /// 获取日期前缀
  String _getDatePrefix() {
    final date = publishedDate ?? DateTime.now();
    return '[${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}]';
  }

  /// 获取唯一的文件名（处理文件名冲突）
  String _getUniqueFileName(String fileName) {
    final file = File(Path.join(path, fileName));
    if (!file.existsSync()) {
      return fileName;
    }

    // 文件已存在，添加数字后缀
    final baseName = Path.basenameWithoutExtension(fileName);
    final extension = Path.extension(fileName);
    
    int counter = 1;
    String newFileName;
    do {
      newFileName = '$baseName ($counter)$extension';
      counter++;
    } while (File(Path.join(path, newFileName)).existsSync());

    return newFileName;
  }

  @override
  Map<String, dynamic> toMap() => {
        'files': files.map((f) => {'name': f.name, 'path': f.path}).toList(),
        'customDownloadPath': customDownloadPath,
        'authorName': authorName,
        'postId': postId,
        'publishedDate': publishedDate?.toIso8601String(),
        'coverUrl': coverUrl,
        '_downloadedFiles': _downloadedFiles,
        '_totalDownloadedBytes': _totalDownloadedBytes,
        '_totalExpectedBytes': _totalExpectedBytes,
        '_failedFiles': _failedFiles,
        ...super.toBaseMap(),
      };

  KemonoAttachmentDownloadingItem.fromMap(
    Map<String, dynamic> map,
    DownloadProgressCallback whenFinish,
    DownloadProgressCallback whenError,
    DownloadProgressCallbackAsync updateInfo,
    String id,
  )   : files = (map['files'] as List)
            .map((f) => KemonoFile(name: f['name'], path: f['path']))
            .toList(),
        customDownloadPath = map['customDownloadPath'],
        authorName = map['authorName'],
        postId = map['postId'],
        publishedDate = map['publishedDate'] != null
            ? DateTime.parse(map['publishedDate'])
            : null,
        coverUrl = map['coverUrl'],
        _downloadedFiles = map['_downloadedFiles'] ?? 0,
        _totalDownloadedBytes = map['_totalDownloadedBytes'] ?? 0,
        _totalExpectedBytes = map['_totalExpectedBytes'] ?? 0,
        super.fromMap(map, whenFinish, whenError, updateInfo) {
    if (map['_failedFiles'] != null) {
      _failedFiles.addAll(List<String>.from(map['_failedFiles']));
    }
  }

  @override
  Future<DownloadedItem> toDownloadedItem() async {
    // 计算下载大小（MB）
    final sizeInMB = _totalDownloadedBytes / (1024 * 1024);
    
    // 附件下载不记录到"已下载"列表
    // 返回一个临时的 Item，完成后会被丢弃
    return _KemonoAttachmentDownloadedItem(
      id: id,
      name: title,
      subTitle: authorName,
      downloadedFiles: _downloadedFiles,
      totalFiles: files.length,
      failedFiles: _failedFiles,
      downloadPath: path,
      totalSizeInMB: sizeInMB,
    );
  }

  @override
  Future<void> stop() async {
    // 先关闭 Dio，取消所有正在进行的请求
    // 这样可以立即停止下载，而不用等待当前请求完成
    _dio?.close(force: true);
    _dio = null;
    
    // 然后调用基类的 stop 方法
    await super.stop();
  }

  /// 获取下载报告
  String getDownloadReport() {
    final successCount = _downloadedFiles;
    final failCount = _failedFiles.length;
    final total = files.length;
    
    // 格式化文件大小
    String sizeStr = _formatBytes(_totalDownloadedBytes);
    
    // 如果有预期大小，显示进度
    if (_totalExpectedBytes > 0) {
      String expectedStr = _formatBytes(_totalExpectedBytes);
      sizeStr = '$sizeStr / $expectedStr';
    }

    if (failCount == 0) {
      return '下载完成: 成功 $successCount/$total ($sizeStr)';
    } else {
      return '下载完成: 成功 $successCount/$total ($sizeStr)，失败 $failCount\n失败文件: ${_failedFiles.join(", ")}';
    }
  }
  
  /// 将字节数格式化为可读的字符串
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
  }
}

/// Kemono 附件下载完成项（临时使用，不会被持久化）
class _KemonoAttachmentDownloadedItem extends DownloadedItem {
  @override
  final String id;

  @override
  final String name;

  @override
  final String subTitle;

  final int downloadedFiles;
  final int totalFiles;
  final List<String> failedFiles;
  final String downloadPath;

  @override
  double? comicSize;

  _KemonoAttachmentDownloadedItem({
    required this.id,
    required this.name,
    required this.subTitle,
    required this.downloadedFiles,
    required this.totalFiles,
    required this.failedFiles,
    required this.downloadPath,
    double? totalSizeInMB,
  }) {
    comicSize = totalSizeInMB;
  }

  @override
  List<int> get downloadedEps => [0];

  @override
  List<String> get eps => ['附件'];

  @override
  List<String> get tags => ['Kemono', 'Attachment'];

  @override
  DownloadType get type => DownloadType.other;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subTitle': subTitle,
        'downloadedFiles': downloadedFiles,
        'totalFiles': totalFiles,
        'failedFiles': failedFiles,
        'downloadPath': downloadPath,
      };
}

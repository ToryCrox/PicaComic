import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';

/// 去除HTML标签
String stripHtml(String html) {
  if (html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim();
}

/// Kemono 文件/附件数据模型
@immutable
class KemonoFile {
  /// 文件名称
  final String name;

  /// 文件路径 (相对路径,需要拼接CDN域名)
  final String path;

  const KemonoFile({
    required this.name,
    required this.path,
  });

  /// 从 JSON Map 创建 KemonoFile
  factory KemonoFile.fromJson(Map<dynamic, dynamic> json) {
    return KemonoFile(
      name: json.optString('name'),
      path: json.optString('path'),
    );
  }

  /// 获取缩略图 URL
  String get thumbnailUrl => 'https://img.kemono.cr/thumbnail/data$path';

  /// 获取原图 URL (使用 n3 服务器)
  String get fullUrl => 'https://n3.kemono.cr/data$path';

  /// 判断是否是图片文件
  bool get isImage {
    final ext = name.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.webp');
  }

  /// 判断是否是压缩包文件
  bool get isArchive {
    final ext = name.toLowerCase();
    return ext.endsWith('.zip') ||
        ext.endsWith('.rar') ||
        ext.endsWith('.7z') ||
        ext.endsWith('.bin');
  }
}

/// Kemono 图集简要信息 (用于列表显示)
@immutable
class KemonoPostBrief extends BaseComic {
  /// 图集ID
  @override
  final String id;

  /// 图集标题
  @override
  final String title;

  /// 服务类型 (patreon/fanbox/fantia等)
  final String service;

  /// 作者ID
  final String userId;

  /// 作者名称
  final String userName;

  /// 主文件 (封面图)
  final KemonoFile? file;

  /// 发布时间
  final DateTime? published;

  const KemonoPostBrief({
    required this.id,
    required this.title,
    required this.service,
    required this.userId,
    required this.userName,
    this.file,
    this.published,
  });

  /// 从 JSON Map 创建 KemonoPostBrief
  factory KemonoPostBrief.fromJson(Map<dynamic, dynamic> json) {
    final fileJson = json['file'];
    KemonoFile? file;
    if (fileJson is Map && fileJson['path'] != null && (fileJson['path'] as String).isNotEmpty) {
      file = KemonoFile.fromJson(fileJson);
    } else if (json['attachments'] is List && (json['attachments'] as List).isNotEmpty) {
      // Discord data uses attachments instead of file
      final attachments = json['attachments'] as List;
      if (attachments.first is Map && attachments.first['path'] != null) {
        file = KemonoFile.fromJson(attachments.first as Map);
      }
    }

    DateTime? published;
    final publishedStr = json.optString('published');
    if (publishedStr.isNotEmpty) {
      published = DateTime.tryParse(publishedStr);
    }

    String title = json.optString('title');
    if (title.isEmpty) {
      // Discord data uses 'content' for the message
      title = stripHtml(json.optString('content'));
    }

    String userId = json.optString('user');
    String userName = json['user_name']?.toString() ?? '';
    
    // Discord data uses 'author' object
    if (json['author'] is Map) {
      final author = json['author'] as Map;
      if (userId.isEmpty) userId = author['id']?.toString() ?? '';
      if (userName.isEmpty) userName = author['username']?.toString() ?? '';
    }
    
    if (userId.isEmpty) userId = json['user']?.toString() ?? '';
    if (userName.isEmpty) userName = userId;

    return KemonoPostBrief(
      id: json.optString('id'),
      title: title,
      service: json.optString('service').isNotEmpty ? json.optString('service') : (json.optString('server').isNotEmpty ? json.optString('server') : ''),
      userId: userId,
      userName: userName,
      file: file,
      published: published,
    );
  }

  @override
  String get cover => file?.thumbnailUrl ?? '';

  @override
  String get subTitle => userName;

  @override
  List<String> get tags => [service];

  @override
  String get description => '';
}

/// Kemono 图集详情
class KemonoPost with HistoryMixin {
  /// 图集ID
  final String id;

  /// 图集标题
  @override
  String title;

  /// 服务类型 (patreon/fanbox/fantia等)
  final String service;

  /// 作者ID
  final String userId;

  /// 作者名称
  final String userName;

  /// 主文件
  final KemonoFile? file;

  /// 附件列表
  final List<KemonoFile> attachments;

  /// 图集内容/描述 (HTML格式)
  final String content;

  /// 发布时间
  final DateTime? published;

  /// 添加时间
  final DateTime? added;

  /// 嵌入内容 (视频等)
  final List<Map<String, dynamic>> embeds;

  KemonoPost({
    required this.id,
    required this.title,
    required this.service,
    required this.userId,
    required this.userName,
    this.file,
    required this.attachments,
    required this.content,
    this.published,
    this.added,
    required this.embeds,
  });

  /// 从 JSON Map 创建 KemonoPost
  factory KemonoPost.fromJson(Map<dynamic, dynamic> json) {
    final fileJson = json['file'];
    KemonoFile? file;
    if (fileJson is Map && fileJson['path'] != null && (fileJson['path'] as String).isNotEmpty) {
      file = KemonoFile.fromJson(fileJson);
    }

    final attachmentsList = json.optDynamicList('attachments');
    final attachments = <KemonoFile>[];
    for (var item in attachmentsList) {
      if (item is Map && item['path'] != null && (item['path'] as String).isNotEmpty) {
        attachments.add(KemonoFile.fromJson(item));
      }
    }

    if (file == null && attachments.isNotEmpty && attachments.first.isImage) {
      file = attachments.first;
    }

    DateTime? published;
    final publishedStr = json.optString('published');
    if (publishedStr.isNotEmpty) {
      published = DateTime.tryParse(publishedStr);
    }

    DateTime? added;
    final addedStr = json.optString('added');
    if (addedStr.isNotEmpty) {
      added = DateTime.tryParse(addedStr);
    }

    final embedsList = json.optDynamicList('embeds');
    final embeds = <Map<String, dynamic>>[];
    for (var item in embedsList) {
      if (item is Map) {
        embeds.add(Map<String, dynamic>.from(item));
      }
    }

    String title = json.optString('title');
    if (title.isEmpty) {
      title = stripHtml(json.optString('content'));
      if (title.length > 50) title = '${title.substring(0, 50)}...';
    }

    String userId = json.optString('user');
    String userName = json['user_name']?.toString() ?? '';
    if (json['author'] is Map) {
      final author = json['author'] as Map;
      if (userId.isEmpty) userId = author['id']?.toString() ?? '';
      if (userName.isEmpty) userName = author['username']?.toString() ?? '';
    }

    return KemonoPost(
      id: json.optString('id'),
      title: title,
      service: json.optString('service').isNotEmpty ? json.optString('service') : (json.optString('server').isNotEmpty ? json.optString('server') : ''),
      userId: userId,
      userName: userName,
      file: file,
      attachments: attachments,
      content: json.optString('content'),
      published: published,
      added: added,
      embeds: embeds,
    );
  }

  /// 获取所有图片URL列表 (用于阅读器)
  List<String> get imageUrls {
    final urls = <String>[];
    
    // 添加主文件
    if (file != null && file!.isImage) {
      urls.add(file!.fullUrl);
    }
    
    // 添加附件中的图片
    for (var attachment in attachments) {
      if (attachment.isImage) {
        urls.add(attachment.fullUrl);
      }
    }
    
    return urls;
  }

  /// 获取所有压缩包附件
  List<KemonoFile> get archiveAttachments {
    return attachments.where((a) => a.isArchive).toList();
  }

  @override
  String get cover => file?.thumbnailUrl ?? '';

  @override
  String get subTitle => userName;

  @override
  HistoryType get historyType => HistoryType('kemono'.hashCode);

  @override
  String get target => '$service/$userId/$id';
}

/// Kemono 作者简要信息
@immutable
class KemonoCreator extends BaseComic {
  /// 作者ID
  @override
  final String id;

  /// 作者名称
  @override
  final String title;

  /// 服务类型 (patreon/fanbox/fantia等)
  final String service;

  /// 最后更新时间
  final DateTime? updated;

  /// 收录时间
  final DateTime? indexed;

  /// 收藏数
  final int favorited;

  const KemonoCreator({
    required this.id,
    required this.title,
    required this.service,
    this.updated,
    this.indexed,
    this.favorited = 0,
  });

  /// 从 JSON Map 创建 KemonoCreator
  factory KemonoCreator.fromJson(Map<dynamic, dynamic> json) {
    DateTime? updated;
    final updatedValue = json['updated'];
    if (updatedValue is num) {
      // Unix 时间戳 (秒)
      updated = DateTime.fromMillisecondsSinceEpoch(updatedValue.toInt() * 1000);
    } else if (updatedValue is String && updatedValue.isNotEmpty) {
      updated = DateTime.tryParse(updatedValue);
    }

    DateTime? indexed;
    final indexedValue = json['indexed'];
    if (indexedValue is num) {
      indexed = DateTime.fromMillisecondsSinceEpoch(indexedValue.toInt() * 1000);
    } else if (indexedValue is String && indexedValue.isNotEmpty) {
      indexed = DateTime.tryParse(indexedValue);
    }

    return KemonoCreator(
      id: json.optString('id'),
      title: json.optString('name'),
      service: json.optString('service'),
      updated: updated,
      indexed: indexed,
      favorited: json.optInt('favorited'),
    );
  }

  /// 作者头像URL (Kemono API不直接提供,使用官方图标构造逻辑)
  @override
  String get cover => 'https://img.kemono.cr/icons/$service/$id';

  @override
  String get subTitle => service;

  @override
  List<String> get tags => [service];

  @override
  String get description => '收藏: $favorited';

  /// 获取作者主页链接
  String get link => 'https://kemono.cr/$service/user/$id';
}

/// 作者排序方式
enum KemonoCreatorSort {
  /// 最近更新
  updated,
  /// 收藏数量
  favorited,
  /// 收录时间
  indexed,
  /// 名称
  name,
}

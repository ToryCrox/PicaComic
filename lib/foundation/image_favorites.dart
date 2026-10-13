import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../tools/type_util.dart';
import '../tools/map_extension.dart';

/// 收藏原图的存储方式。
enum ImageFavoriteStorage { download, standalone }

/// 图片收藏记录；所有文件位置均为相对路径。
class ImageFavorite {
  const ImageFavorite({
    required this.sourceKey,
    required this.comicId,
    required this.title,
    required this.ep,
    required this.page,
    required this.imagePath,
    this.storage = ImageFavoriteStorage.standalone,
    this.downloadId = '',
    this.imageUrl = '',
    this.otherInfo = const {},
  });

  final String sourceKey;
  final String comicId;
  final String title;
  final int ep;
  final int page;
  final String imagePath;
  final ImageFavoriteStorage storage;
  final String downloadId;
  final String imageUrl;
  final Map<String, dynamic> otherInfo;

  /// 阅读标识与下载数据库标识分别保存。
  String get id => '$sourceKey-$comicId';

  /// 使用结构化身份生成稳定文件名，避免同名、分隔符及目录泄露。
  String get recordId => sha256
      .convert(utf8.encode(jsonEncode([sourceKey, comicId, ep, page])))
      .toString();

  /// 创建更新后的不可变记录。
  ImageFavorite copyWith({
    String? imagePath,
    ImageFavoriteStorage? storage,
    String? downloadId,
  }) => ImageFavorite(
    sourceKey: sourceKey,
    comicId: comicId,
    title: title,
    ep: ep,
    page: page,
    imagePath: imagePath ?? this.imagePath,
    storage: storage ?? this.storage,
    downloadId: downloadId ?? this.downloadId,
    imageUrl: imageUrl,
    otherInfo: otherInfo,
  );

  /// 读取新格式记录，不读取旧收藏字段。
  factory ImageFavorite.fromJson(Map<String, dynamic> map) => ImageFavorite(
    sourceKey: map.optString('source_key'),
    comicId: map.optString('comic_id'),
    title: map.optString('title'),
    ep: map.optInt('ep'),
    page: map.optInt('page'),
    imagePath: map.optString('image_path'),
    storage: ImageFavoriteStorage.values.byName(map.optString('storage')),
    downloadId: map.optString('download_id'),
    imageUrl: map.optString('image_url'),
    otherInfo: map.optMap('other'),
  );

  /// 解码数据库中的阅读元数据。
  factory ImageFavorite.fromRow(Map<String, dynamic> row) =>
      ImageFavorite.fromJson(row);

  /// 导出新格式字段。
  Map<String, dynamic> toJson() => {
    'record_id': recordId,
    'source_key': sourceKey,
    'comic_id': comicId,
    'title': title,
    'ep': ep,
    'page': page,
    'image_path': imagePath,
    'storage': storage.name,
    'download_id': downloadId,
    'image_url': imageUrl,
    'other': otherInfo,
  };

  /// 编码数据库中的阅读元数据。
  Map<String, dynamic> toRow() => {...toJson(), 'other': jsonEncode(otherInfo)};

  @override
  bool operator ==(Object other) =>
      other is ImageFavorite && TypeUtil.equal(toJson(), other.toJson());

  @override
  int get hashCode => recordId.hashCode;
}

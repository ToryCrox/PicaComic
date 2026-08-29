import 'package:flutter/material.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

/// 标签分类枚举
enum TagCategory {
  author(1, '作者', Colors.pinkAccent),
  work(2, '作品', Colors.blueAccent),
  character(3, '角色', Colors.greenAccent),
  special(5, '特点', Colors.deepPurple),
  manga(4, '漫画', Colors.orangeAccent),
  date(6, '日期', Colors.brown),
  none(0, '未分类', Colors.grey);

  final int value;
  final String label;
  final Color color;

  const TagCategory(this.value, this.label, this.color);

  static TagCategory fromValue(int value) {
    return TagCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TagCategory.none,
    );
  }
}

/// 标签模型
class DownloadTag {
  final int id;
  final String name;
  final String? coverComicId;
  final DateTime createdTime;
  final int sortOrder;
  final DateTime updatedTime;
  final TagCategory category;
  final int categorySortOrder;

  const DownloadTag({
    required this.id,
    required this.name,
    this.coverComicId,
    required this.createdTime,
    this.sortOrder = 0,
    DateTime? updatedTime,
    this.category = TagCategory.none,
    this.categorySortOrder = 0,
  }) : updatedTime = updatedTime ?? createdTime;

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    final timestamp = TypeUtil.parseIntOrNull(value);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    final parsed = DateTime.tryParse(TypeUtil.parseString(value));
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 从数据库Map创建DownloadTag对象
  factory DownloadTag.fromMap(Map<String, Object?> map) {
    return DownloadTag(
      id: map.optInt('id'),
      name: map.optString('name'),
      coverComicId: map.optStringOrNull('cover_comic_id'),
      createdTime: _parseDate(map['created_time']),
      sortOrder: map.optInt('sort_order'),
      updatedTime: map['updated_time'] == null
          ? null
          : _parseDate(map['updated_time']),
      category: TagCategory.fromValue(map.optInt('category')),
      categorySortOrder: map.optInt('category_sort_order'),
    );
  }

  factory DownloadTag.fromJson(Map<String, dynamic> json) =>
      DownloadTag.fromMap(json);

  DownloadTag copyWith({
    int? id,
    String? name,
    String? coverComicId,
    DateTime? createdTime,
    int? sortOrder,
    DateTime? updatedTime,
    TagCategory? category,
    int? categorySortOrder,
    bool clearCoverComicId = false,
  }) => DownloadTag(
    id: id ?? this.id,
    name: name ?? this.name,
    coverComicId: clearCoverComicId ? null : coverComicId ?? this.coverComicId,
    createdTime: createdTime ?? this.createdTime,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedTime: updatedTime ?? this.updatedTime,
    category: category ?? this.category,
    categorySortOrder: categorySortOrder ?? this.categorySortOrder,
  );

  /// 转换为Map用于数据库操作
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_comic_id': coverComicId,
      'created_time': createdTime.millisecondsSinceEpoch,
      'sort_order': sortOrder,
      'updated_time': updatedTime.millisecondsSinceEpoch,
      'category': category.value,
      'category_sort_order': categorySortOrder,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  @override
  String toString() =>
      'DownloadTag(id: $id, name: $name, category: ${category.label})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

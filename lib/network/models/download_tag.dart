import 'package:flutter/material.dart';

/// 标签分类枚举
enum TagCategory {
  author(1, '作者', Colors.pinkAccent),
  work(2, '作品', Colors.blueAccent),
  character(3, '角色', Colors.greenAccent),
  special(5, '特点', Colors.deepPurple),
  manga(4, '漫画', Colors.orangeAccent),
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

  DownloadTag({
    required this.id,
    required this.name,
    this.coverComicId,
    required this.createdTime,
    this.sortOrder = 0,
    DateTime? updatedTime,
    this.category = TagCategory.none,
  }) : updatedTime = updatedTime ?? createdTime;

  /// 从数据库Map创建DownloadTag对象
  factory DownloadTag.fromMap(Map<String, Object?> map) {
    return DownloadTag(
      id: map['id'] as int,
      name: map['name'] as String,
      coverComicId: map['cover_comic_id'] as String?,
      createdTime: DateTime.fromMillisecondsSinceEpoch(
        map['created_time'] as int,
      ),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      updatedTime: map['updated_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_time'] as int)
          : null,
      category: TagCategory.fromValue((map['category'] as int?) ?? 0),
    );
  }

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
    };
  }

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

/// 标签模型
class DownloadTag {
  final int id;
  final String name;
  final String? coverComicId;
  final DateTime createdTime;

  DownloadTag({
    required this.id,
    required this.name,
    this.coverComicId,
    required this.createdTime,
  });

  /// 从数据库Map创建DownloadTag对象
  factory DownloadTag.fromMap(Map<String, Object?> map) {
    return DownloadTag(
      id: map['id'] as int,
      name: map['name'] as String,
      coverComicId: map['cover_comic_id'] as String?,
      createdTime: DateTime.fromMillisecondsSinceEpoch(
        map['created_time'] as int,
      ),
    );
  }

  /// 转换为Map用于数据库操作
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'cover_comic_id': coverComicId,
      'created_time': createdTime.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() => 'DownloadTag(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

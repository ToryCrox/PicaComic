import 'dart:convert';

import 'package:pica_comic/tools/type_util.dart';

/// 漫画目录中的章节分组，章节 ID 对应完整目录的键。
class ComicChapterGroup {
  final String id;
  final String title;
  final List<String> chapterIds;

  const ComicChapterGroup({
    this.id = '',
    this.title = '',
    this.chapterIds = const [],
  });

  /// 复制分组并替换指定字段。
  ComicChapterGroup copyWith({
    String? id,
    String? title,
    List<String>? chapterIds,
  }) => ComicChapterGroup(
    id: id ?? this.id,
    title: title ?? this.title,
    chapterIds: chapterIds ?? this.chapterIds,
  );

  /// 从持久化快照恢复分组。
  factory ComicChapterGroup.fromMap(Map<String, dynamic> map) =>
      ComicChapterGroup(
        id: TypeUtil.parseString(map['id']),
        title: TypeUtil.parseString(map['title']),
        chapterIds: TypeUtil.parseStringList(map['chapterIds']),
      );

  /// 转换为持久化快照。
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'chapterIds': chapterIds,
  };

  /// 从 JSON 字符串恢复分组。
  factory ComicChapterGroup.fromJson(String source) =>
      ComicChapterGroup.fromMap(jsonDecode(source) as Map<String, dynamic>);

  /// 编码为 JSON 字符串。
  String toJson() => jsonEncode(toMap());

  @override
  bool operator ==(Object other) =>
      other is ComicChapterGroup &&
      id == other.id &&
      title == other.title &&
      TypeUtil.equal(chapterIds, other.chapterIds);

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(chapterIds));
}

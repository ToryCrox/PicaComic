import 'dart:convert';

import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

class Tag {
  final String name;
  final String link;

  const Tag({this.name = '', this.link = ''});

  Tag copyWith({String? name, String? link}) =>
      Tag(name: name ?? this.name, link: link ?? this.link);

  factory Tag.fromMap(Map<String, dynamic> map) =>
      Tag(name: map.optString('name'), link: map.optString('link'));

  Map<String, dynamic> toMap() => {'name': name, 'link': link};

  factory Tag.fromJson(Map<String, dynamic> json) => Tag.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag && name == other.name && link == other.link;

  @override
  int get hashCode => Object.hash(name, link);

  @override
  String toString() => 'Tag${jsonEncode(toMap())}';
}

class HitomiComicBrief extends BaseComic {
  String name;
  String type;
  String lang;
  List<Tag> tagList;
  String time;
  String artist;
  String link;
  @override
  String cover;

  HitomiComicBrief(
    this.name,
    this.type,
    this.lang,
    this.tagList,
    this.time,
    this.artist,
    this.link,
    this.cover,
  );

  @override
  String get description => lang;

  @override
  String get id => link;

  @override
  String get subTitle => artist;

  @override
  List<String> get tags => tagList.map((e) => e.name).toList();

  @override
  String get title => name;

  @override
  bool get enableTagsTranslation => true;
}

class ComicList {
  ///数据源
  String url;

  ///要获取的开始位置
  int toLoad = 0;

  ///总共的byte数量
  int total = 100;

  List<int> comicIds = [];

  ComicList(this.url);
}

class HitomiFile {
  final String name;
  final String hash;
  final bool hasWebp;
  final bool hasAvif;
  final int height;
  final int width;
  final String galleryId;

  const HitomiFile({
    this.name = '',
    this.hash = '',
    this.hasWebp = false,
    this.hasAvif = false,
    this.height = 0,
    this.width = 0,
    this.galleryId = '',
  });

  HitomiFile copyWith({
    String? name,
    String? hash,
    bool? hasWebp,
    bool? hasAvif,
    int? height,
    int? width,
    String? galleryId,
  }) => HitomiFile(
    name: name ?? this.name,
    hash: hash ?? this.hash,
    hasWebp: hasWebp ?? this.hasWebp,
    hasAvif: hasAvif ?? this.hasAvif,
    height: height ?? this.height,
    width: width ?? this.width,
    galleryId: galleryId ?? this.galleryId,
  );

  factory HitomiFile.fromMap(Map<String, dynamic> map) => HitomiFile(
    name: map.optString('name'),
    hash: map.optString('hash'),
    hasWebp: map.optBool('hasWebp'),
    hasAvif: map.optBool('hasAvif'),
    height: map.optInt('height'),
    width: map.optInt('width'),
    galleryId: map.optString('galleryId'),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'hash': hash,
    'hasWebp': hasWebp,
    'hasAvif': hasAvif,
    'height': height,
    'width': width,
    'galleryId': galleryId,
  };

  factory HitomiFile.fromJson(Map<String, dynamic> json) =>
      HitomiFile.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HitomiFile &&
          name == other.name &&
          hash == other.hash &&
          hasWebp == other.hasWebp &&
          hasAvif == other.hasAvif &&
          height == other.height &&
          width == other.width &&
          galleryId == other.galleryId;

  @override
  int get hashCode =>
      Object.hash(name, hash, hasWebp, hasAvif, height, width, galleryId);

  @override
  String toString() => 'HitomiFile${jsonEncode(toMap())}';
}

class HitomiComic with HistoryMixin {
  final String id;
  final String name;
  final List<int> related;
  final String type;
  final List<String>? artists;
  final String lang;
  final List<Tag>? parodys;
  final List<Tag>? characters;
  final List<Tag> tags;
  final String time;
  final List<HitomiFile> files;
  final List<String> group;
  @override
  final String cover;

  const HitomiComic({
    this.id = '',
    this.name = '',
    this.related = const [],
    this.type = '',
    this.artists,
    this.lang = 'Unknown',
    this.parodys,
    this.characters,
    this.tags = const [],
    this.time = '',
    this.files = const [],
    this.group = const [],
    this.cover = '',
  });

  HitomiComic copyWith({
    String? id,
    String? name,
    List<int>? related,
    String? type,
    List<String>? artists,
    String? lang,
    List<Tag>? parodys,
    List<Tag>? characters,
    List<Tag>? tags,
    String? time,
    List<HitomiFile>? files,
    List<String>? group,
    String? cover,
    bool clearArtists = false,
    bool clearParodys = false,
    bool clearCharacters = false,
  }) {
    return HitomiComic(
      id: id ?? this.id,
      name: name ?? this.name,
      related: related ?? this.related,
      type: type ?? this.type,
      artists: clearArtists ? null : artists ?? this.artists,
      lang: lang ?? this.lang,
      parodys: clearParodys ? null : parodys ?? this.parodys,
      characters: clearCharacters ? null : characters ?? this.characters,
      tags: tags ?? this.tags,
      time: time ?? this.time,
      files: files ?? this.files,
      group: group ?? this.group,
      cover: cover ?? this.cover,
    );
  }

  factory HitomiComic.fromMap(Map<String, dynamic> map) {
    final group = map.optStringList('group');
    final parodys = map.optMapList('parodys').map(Tag.fromMap).toList();
    return HitomiComic(
      id: map.optString('id'),
      name: map.optString('name'),
      type: map.optString('type'),
      artists: map['artists'] == null ? null : map.optStringList('artists'),
      lang: map.optString('lang', 'Unknown'),
      time: map.optString('time'),
      parodys: parodys.isEmpty ? [const Tag(name: 'N/A')] : parodys,
      characters: map.optMapList('characters').map(Tag.fromMap).toList(),
      tags: map.optMapList('tags').map(Tag.fromMap).toList(),
      related: map.optIntList('related'),
      group: group.isEmpty ? ['N/A'] : group,
      cover: map.optString('cover'),
      files: map.optMapList('files').map(HitomiFile.fromMap).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'artists': artists,
    'lang': lang,
    'related': related,
    'parodys': parodys?.map((tag) => tag.toMap()).toList(),
    'characters': characters?.map((tag) => tag.toMap()).toList(),
    'tags': tags.map((tag) => tag.toMap()).toList(),
    'time': time,
    'group': group,
    'cover': cover,
    'files': files.map((file) => file.toMap()).toList(),
  };

  factory HitomiComic.fromJson(Map<String, dynamic> json) =>
      HitomiComic.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  HitomiComicBrief toBrief(String link, String cover) => HitomiComicBrief(
    name,
    type,
    lang,
    tags,
    time,
    (artists ?? ["未知"]).isEmpty ? "未知" : (artists ?? ["未知"])[0],
    link,
    cover,
  );

  @override
  HistoryType get historyType => HistoryType.hitomi;

  @override
  String get subTitle => artists?.firstOrNull ?? '';

  @override
  String get target => id;

  @override
  String get title => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HitomiComic &&
          id == other.id &&
          name == other.name &&
          TypeUtil.equal(related, other.related) &&
          type == other.type &&
          TypeUtil.equal(artists, other.artists) &&
          lang == other.lang &&
          TypeUtil.equal(parodys, other.parodys) &&
          TypeUtil.equal(characters, other.characters) &&
          TypeUtil.equal(tags, other.tags) &&
          time == other.time &&
          TypeUtil.equal(files, other.files) &&
          TypeUtil.equal(group, other.group) &&
          cover == other.cover;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HitomiComic${jsonEncode(toMap())}';
}

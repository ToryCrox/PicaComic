import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

@immutable
class HtHomePageData {
  final List<List<HtComicBrief>> comics;
  final Map<String, String> links;

  /// 主页
  const HtHomePageData({this.comics = const [], this.links = const {}});

  HtHomePageData copyWith({
    List<List<HtComicBrief>>? comics,
    Map<String, String>? links,
  }) =>
      HtHomePageData(comics: comics ?? this.comics, links: links ?? this.links);

  factory HtHomePageData.fromMap(Map<String, dynamic> map) {
    return HtHomePageData(
      comics: map.optList(
        'comics',
        (items) =>
            TypeUtil.parseMapList(items).map(HtComicBrief.fromMap).toList(),
      ),
      links: map
          .optMap('links')
          .map((key, value) => MapEntry(key, TypeUtil.parseString(value))),
    );
  }

  Map<String, dynamic> toMap() => {
    'comics': comics.map((e) => e.map((e) => e.toMap()).toList()).toList(),
    'links': links,
  };

  factory HtHomePageData.fromJson(Map<String, dynamic> json) =>
      HtHomePageData.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HtHomePageData &&
          TypeUtil.equal(comics, other.comics) &&
          TypeUtil.equal(links, other.links);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HtHomePageData${jsonEncode(toMap())}';
}

@immutable
class HtComicBrief extends BaseComic {
  final String name;
  final String time;
  final String image;
  final int pages;
  @override
  final String id;
  final String? favoriteId;

  /// 漫画简略信息
  const HtComicBrief({
    this.name = '',
    this.time = '',
    this.image = '',
    this.id = '',
    this.pages = 0,
    this.favoriteId,
  });

  HtComicBrief copyWith({
    String? name,
    String? time,
    String? image,
    String? id,
    int? pages,
    String? favoriteId,
    bool clearFavoriteId = false,
  }) => HtComicBrief(
    name: name ?? this.name,
    time: time ?? this.time,
    image: image ?? this.image,
    id: id ?? this.id,
    pages: pages ?? this.pages,
    favoriteId: clearFavoriteId ? null : favoriteId ?? this.favoriteId,
  );

  @override
  String get cover => image;

  @override
  String get description => time;

  @override
  String get subTitle => id;

  @override
  List<String> get tags => const [];

  @override
  String get title => name;

  factory HtComicBrief.fromMap(Map<String, dynamic> map) => HtComicBrief(
    name: map.optString('name'),
    time: map.optString('time'),
    image: map.optString('image'),
    pages: map.optInt('pages'),
    id: map.optString('id'),
    favoriteId: map.optStringOrNull('favoriteId'),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'time': time,
    'image': image,
    'pages': pages,
    'id': id,
    'favoriteId': favoriteId,
  };

  factory HtComicBrief.fromJson(Map<String, dynamic> json) =>
      HtComicBrief.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HtComicBrief &&
          name == other.name &&
          time == other.time &&
          image == other.image &&
          pages == other.pages &&
          id == other.id &&
          favoriteId == other.favoriteId;

  @override
  int get hashCode => Object.hash(name, time, image, pages, id, favoriteId);

  @override
  String toString() => 'HtComicBrief${jsonEncode(toMap())}';
}

@immutable
class HtComicInfo with HistoryMixin {
  final String id;
  final String coverPath;
  final String name;
  final String category;
  final int pages;
  final Map<String, String> tags;
  final String description;
  final String uploader;
  final String avatar;
  final int uploadNum;
  final List<String> thumbnails;

  const HtComicInfo({
    this.id = '',
    this.coverPath = '',
    this.name = '',
    this.category = '',
    this.pages = 0,
    this.tags = const {},
    this.description = '',
    this.uploader = '',
    this.avatar = '',
    this.uploadNum = 0,
    this.thumbnails = const [],
  });

  HtComicInfo copyWith({
    String? id,
    String? coverPath,
    String? name,
    String? category,
    int? pages,
    Map<String, String>? tags,
    String? description,
    String? uploader,
    String? avatar,
    int? uploadNum,
    List<String>? thumbnails,
  }) => HtComicInfo(
    id: id ?? this.id,
    coverPath: coverPath ?? this.coverPath,
    name: name ?? this.name,
    category: category ?? this.category,
    pages: pages ?? this.pages,
    tags: tags ?? this.tags,
    description: description ?? this.description,
    uploader: uploader ?? this.uploader,
    avatar: avatar ?? this.avatar,
    uploadNum: uploadNum ?? this.uploadNum,
    thumbnails: thumbnails ?? this.thumbnails,
  );

  HtComicBrief toBrief() =>
      HtComicBrief(name: name, image: coverPath, id: id, pages: pages);

  Map<String, dynamic> toMap() => {
    'id': id,
    'coverPath': coverPath,
    'name': name,
    'category': category,
    'pages': pages,
    'tags': tags,
    'description': description,
    'uploader': uploader,
    'avatar': avatar,
    'uploadNum': uploadNum,
    'thumbnails': thumbnails,
  };

  factory HtComicInfo.fromMap(Map<String, dynamic> map) => HtComicInfo(
    id: map.optString('id'),
    coverPath: map.optString('coverPath'),
    name: map.optString('name'),
    category: map.optString('category'),
    pages: map.optInt('pages'),
    tags: map
        .optMap('tags')
        .map((key, value) => MapEntry(key, TypeUtil.parseString(value))),
    description: map.optString('description'),
    uploader: map.optString('uploader'),
    avatar: map.optString('avatar'),
    uploadNum: map.optInt('uploadNum'),
    thumbnails: map.optStringList('thumbnails'),
  );

  factory HtComicInfo.fromJson(Map<String, dynamic> json) =>
      HtComicInfo.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  String get cover => coverPath;

  @override
  HistoryType get historyType => HistoryType.htmanga;

  @override
  String get subTitle => uploader;

  @override
  String get target => id;

  @override
  String get title => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HtComicInfo &&
          id == other.id &&
          coverPath == other.coverPath &&
          name == other.name &&
          category == other.category &&
          pages == other.pages &&
          TypeUtil.equal(tags, other.tags) &&
          description == other.description &&
          uploader == other.uploader &&
          avatar == other.avatar &&
          uploadNum == other.uploadNum &&
          TypeUtil.equal(thumbnails, other.thumbnails);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HtComicInfo${jsonEncode(toMap())}';
}

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

@immutable
class NhentaiComicBrief extends BaseComic {
  @override
  final String title;
  @override
  final String cover;
  @override
  final String id;
  final String lang;
  @override
  final List<String> tags;

  const NhentaiComicBrief({
    this.title = '',
    this.cover = '',
    this.id = '',
    this.lang = '',
    this.tags = const [],
  });

  NhentaiComicBrief copyWith({
    String? title,
    String? cover,
    String? id,
    String? lang,
    List<String>? tags,
  }) => NhentaiComicBrief(
    title: title ?? this.title,
    cover: cover ?? this.cover,
    id: id ?? this.id,
    lang: lang ?? this.lang,
    tags: tags ?? this.tags,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'cover': cover,
    'id': id,
    'lang': lang,
    'tags': tags,
  };

  factory NhentaiComicBrief.fromMap(Map<String, dynamic> map) =>
      NhentaiComicBrief(
        title: map.optString('title'),
        cover: map.optString('cover'),
        id: map.optString('id'),
        lang: map.optString('lang'),
        tags: map.optStringList('tags'),
      );

  factory NhentaiComicBrief.fromJson(Map<String, dynamic> json) =>
      NhentaiComicBrief.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NhentaiComicBrief &&
          title == other.title &&
          cover == other.cover &&
          id == other.id &&
          lang == other.lang &&
          TypeUtil.equal(tags, other.tags);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'NhentaiComicBrief${jsonEncode(toMap())}';

  @override
  String get description => lang;

  @override
  String get subTitle => id;

  @override
  bool get enableTagsTranslation => true;
}

class NhentaiHomePageData {
  final List<NhentaiComicBrief> popular;
  List<NhentaiComicBrief> latest;
  int page = 1;

  NhentaiHomePageData(this.popular, this.latest);
}

class NhentaiComic with HistoryMixin {
  final String id;
  @override
  final String title;
  @override
  final String subTitle;
  @override
  final String cover;
  final Map<String, List<String>> tags;
  final bool favorite;
  final List<String> thumbnails;
  final List<NhentaiComicBrief> recommendations;
  final String token;

  const NhentaiComic({
    this.id = '',
    this.title = '',
    this.subTitle = '',
    this.cover = '',
    this.tags = const {},
    this.favorite = false,
    this.thumbnails = const [],
    this.recommendations = const [],
    this.token = '',
  });

  NhentaiComic copyWith({
    String? id,
    String? title,
    String? subTitle,
    String? cover,
    Map<String, List<String>>? tags,
    bool? favorite,
    List<String>? thumbnails,
    List<NhentaiComicBrief>? recommendations,
    String? token,
  }) => NhentaiComic(
    id: id ?? this.id,
    title: title ?? this.title,
    subTitle: subTitle ?? this.subTitle,
    cover: cover ?? this.cover,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    thumbnails: thumbnails ?? this.thumbnails,
    recommendations: recommendations ?? this.recommendations,
    token: token ?? this.token,
  );

  factory NhentaiComic.fromMap(Map<String, dynamic> map) {
    final tags = map
        .optMap('tags')
        .map((key, value) => MapEntry(key, TypeUtil.parseStringList(value)));
    return NhentaiComic(
      id: map.optString('id'),
      title: map.optString('title'),
      subTitle: map.optString('subTitle'),
      cover: map.optString('cover'),
      tags: tags,
      favorite: map.optBool('favorite'),
      thumbnails: map.optStringList('thumbnails'),
      recommendations: map.optList(
        'recommendations',
        (item) => NhentaiComicBrief.fromMap(item),
      ),
      token: map.optString('token'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subTitle': subTitle,
    'cover': cover,
    'tags': tags,
    'favorite': favorite,
    'thumbnails': thumbnails,
    'recommendations': recommendations.map((comic) => comic.toMap()).toList(),
    'token': token,
  };

  factory NhentaiComic.fromJson(Map<String, dynamic> json) =>
      NhentaiComic.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  HistoryType get historyType => HistoryType.nhentai;

  @override
  String get target => id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NhentaiComic &&
          id == other.id &&
          title == other.title &&
          subTitle == other.subTitle &&
          cover == other.cover &&
          TypeUtil.equal(tags, other.tags) &&
          favorite == other.favorite &&
          TypeUtil.equal(thumbnails, other.thumbnails) &&
          TypeUtil.equal(recommendations, other.recommendations) &&
          token == other.token;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'NhentaiComic${jsonEncode(toMap())}';
}

class NhentaiComment {
  String userName;
  String avatar;
  String content;
  int date;

  NhentaiComment(this.userName, this.avatar, this.content, this.date);
}

import 'package:flutter/cupertino.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';

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

  const NhentaiComicBrief(
    this.title,
    this.cover,
    this.id,
    this.lang,
    this.tags,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    'cover': cover,
    'id': id,
    'lang': lang,
    'tags': tags,
  };

  NhentaiComicBrief.fromMap(Map<String, dynamic> map)
    : title = map['title'],
      cover = map['cover'],
      id = map['id'],
      lang = map['lang'] ?? '',
      tags = List<String>.from(map['tags'] ?? []);

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
  String id;
  @override
  String title;
  @override
  String subTitle;
  @override
  String cover;
  Map<String, List<String>> tags;
  bool favorite;
  List<String> thumbnails;
  List<NhentaiComicBrief> recommendations;
  String token;

  NhentaiComic(
    this.id,
    this.title,
    this.subTitle,
    this.cover,
    this.tags,
    this.favorite,
    this.thumbnails,
    this.recommendations,
    this.token,
  );

  Map<String, dynamic> toMap() => {
    "id": id,
    "title": title,
    "subTitle": subTitle,
    "cover": cover,
    "tags": tags,
    "favorite": favorite,
    "thumbnails": thumbnails,
    "recommendations": recommendations.map((comic) => comic.toMap()).toList(),
    "token": token,
  };

  NhentaiComic.fromMap(Map<String, dynamic> map)
    : id = map["id"],
      title = map["title"],
      subTitle = map["subTitle"],
      cover = map["cover"],
      tags =
          (map['tags'] as Map?)?.map(
            (key, value) =>
                MapEntry(key.toString(), List<String>.from(value as List)),
          ) ??
          {},
      favorite = map['favorite'] is bool ? map['favorite'] : false,
      thumbnails = List<String>.from(map['thumbnails'] ?? []),
      recommendations = (map['recommendations'] as List? ?? [])
          .map((e) => NhentaiComicBrief.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      token = map['token'] ?? "";

  @override
  HistoryType get historyType => HistoryType.nhentai;

  @override
  String get target => id;
}

class NhentaiComment {
  String userName;
  String avatar;
  String content;
  int date;

  NhentaiComment(this.userName, this.avatar, this.content, this.date);
}

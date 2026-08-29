import 'dart:convert';

import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

class HomePageData {
  final List<HomePageItem> items;

  const HomePageData({this.items = const []});

  HomePageData copyWith({List<HomePageItem>? items}) =>
      HomePageData(items: items ?? this.items);

  factory HomePageData.fromMap(Map<String, dynamic> map) => HomePageData(
    items: map.optList('items', (item) => HomePageItem.fromMap(item)),
  );

  Map<String, dynamic> toMap() => {
    'items': items.map((e) => e.toMap()).toList(),
  };

  factory HomePageData.fromJson(Map<String, dynamic> json) =>
      HomePageData.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomePageData && TypeUtil.equal(items, other.items);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HomePageData${jsonEncode(toMap())}';
}

class HomePageItem {
  final String name;
  final String id;
  final bool category;
  final List<JmComicBrief> comics;

  const HomePageItem({
    this.name = '',
    this.id = '',
    this.comics = const [],
    this.category = false,
  });

  HomePageItem copyWith({
    String? name,
    String? id,
    List<JmComicBrief>? comics,
    bool? category,
  }) {
    return HomePageItem(
      name: name ?? this.name,
      id: id ?? this.id,
      comics: comics ?? this.comics,
      category: category ?? this.category,
    );
  }

  factory HomePageItem.fromMap(Map<String, dynamic> map) => HomePageItem(
    name: map.optString('name'),
    id: map.optString('id'),
    category: map.optBool('category'),
    comics: map.optList('comics', (item) => JmComicBrief.fromMap(item)),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'id': id,
    'category': category,
    'comics': comics.map((e) => e.toMap()).toList(),
  };

  factory HomePageItem.fromJson(Map<String, dynamic> json) =>
      HomePageItem.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomePageItem &&
          name == other.name &&
          id == other.id &&
          category == other.category &&
          TypeUtil.equal(comics, other.comics);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'HomePageItem${jsonEncode(toMap())}';
}

class JmComicBrief extends BaseComic {
  @override
  final String id;
  final String author;
  final String name;
  @override
  final String description;
  final List<ComicCategoryInfo> categories;
  @override
  List<String> get tags => categories.map((e) => e.name).toList();

  const JmComicBrief({
    this.id = '',
    this.author = '',
    this.name = '',
    this.description = '',
    this.categories = const [],
  });

  JmComicBrief copyWith({
    String? id,
    String? author,
    String? name,
    String? description,
    List<ComicCategoryInfo>? categories,
  }) {
    return JmComicBrief(
      id: id ?? this.id,
      author: author ?? this.author,
      name: name ?? this.name,
      description: description ?? this.description,
      categories: categories ?? this.categories,
    );
  }

  @override
  String get cover => getJmCoverUrl(id);

  @override
  String get subTitle => author;

  @override
  String get title => name;

  factory JmComicBrief.fromMap(Map<String, dynamic> map) => JmComicBrief(
    id: map.optString('id'),
    author: map.optString('author'),
    name: map.optString('name'),
    description: map.optString('description'),
    categories: map.optList(
      'categories',
      (item) => ComicCategoryInfo.fromMap(item),
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'author': author,
    'name': name,
    'description': description,
    'categories': categories.map((e) => e.toMap()).toList(),
  };

  factory JmComicBrief.fromJson(Map<String, dynamic> json) =>
      JmComicBrief.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JmComicBrief &&
          id == other.id &&
          author == other.author &&
          name == other.name &&
          description == other.description &&
          TypeUtil.equal(categories, other.categories);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'JmComicBrief${jsonEncode(toMap())}';
}

class ComicCategoryInfo {
  final String id;
  final String name;

  const ComicCategoryInfo({this.id = '', this.name = ''});

  ComicCategoryInfo copyWith({String? id, String? name}) =>
      ComicCategoryInfo(id: id ?? this.id, name: name ?? this.name);

  factory ComicCategoryInfo.fromMap(Map<String, dynamic> map) =>
      ComicCategoryInfo(id: map.optString('id'), name: map.optString('name'));

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  factory ComicCategoryInfo.fromJson(Map<String, dynamic> json) =>
      ComicCategoryInfo.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicCategoryInfo && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'ComicCategoryInfo${jsonEncode(toMap())}';
}

class PromoteList {
  String id;
  List<JmComicBrief> comics;
  int loaded = 0;
  int total = 1;
  int page = 0;

  PromoteList(this.id, this.comics);
}

class SearchRes {
  String keyword;
  int loaded;
  int total;
  int loadedPage = 1;
  List<JmComicBrief> comics;

  SearchRes(this.keyword, this.loaded, this.total, this.comics);
}

class Category {
  String name;
  String slug;
  List<SubCategory> subCategories;

  Category(this.name, this.slug, this.subCategories) {
    if (slug == "") {
      slug = "0";
    }
  }
}

class SubCategory {
  String cid;
  String name;
  String slug;

  SubCategory(this.cid, this.name, this.slug);
}

class JmComicInfo with HistoryMixin {
  final String name;
  final String id;
  final List<String> author;
  final String description;
  final int likes;
  final int views;
  final int comments;

  ///章节信息, 键为章节序号, 值为漫画ID
  final Map<int, String> series;
  final List<String> tags;
  final List<String> works;
  final List<String> actors;
  final List<JmComicBrief> relatedComics;
  final bool liked;
  final bool favorite;
  final List<String> epNames;

  const JmComicInfo({
    this.name = '',
    this.id = '',
    this.author = const [],
    this.description = '',
    this.likes = 0,
    this.views = 0,
    this.comments = 0,
    this.series = const {},
    this.tags = const [],
    this.works = const [],
    this.actors = const [],
    this.relatedComics = const [],
    this.liked = false,
    this.favorite = false,
    this.epNames = const [],
  });

  JmComicInfo copyWith({
    String? name,
    String? id,
    List<String>? author,
    String? description,
    int? likes,
    int? views,
    int? comments,
    Map<int, String>? series,
    List<String>? tags,
    List<String>? works,
    List<String>? actors,
    List<JmComicBrief>? relatedComics,
    bool? liked,
    bool? favorite,
    List<String>? epNames,
  }) {
    return JmComicInfo(
      name: name ?? this.name,
      id: id ?? this.id,
      author: author ?? this.author,
      description: description ?? this.description,
      likes: likes ?? this.likes,
      views: views ?? this.views,
      comments: comments ?? this.comments,
      series: series ?? this.series,
      tags: tags ?? this.tags,
      works: works ?? this.works,
      actors: actors ?? this.actors,
      relatedComics: relatedComics ?? this.relatedComics,
      liked: liked ?? this.liked,
      favorite: favorite ?? this.favorite,
      epNames: epNames ?? this.epNames,
    );
  }

  static Map<String, String> seriesToJsonMap(Map<int, String> map) {
    var res = <String, String>{};
    for (var i in map.entries) {
      res[i.key.toString()] = i.value;
    }
    return res;
  }

  static Map<int, String> jsonMapToSeries(Map<String, dynamic> map) {
    var res = <int, String>{};
    for (var i in map.entries) {
      final key = TypeUtil.parseIntOrNull(i.key);
      if (key != null) {
        res[key] = TypeUtil.parseString(i.value);
      }
    }
    return res;
  }

  factory JmComicInfo.fromMap(Map<String, dynamic> map) => JmComicInfo(
    name: map.optString('name'),
    id: map.optString('id'),
    author: map.optStringList('author'),
    description: map.optString('description'),
    likes: map.optInt('likes'),
    views: map.optInt('views'),
    series: jsonMapToSeries(map.optMap('series')),
    tags: map.optStringList('tags'),
    works: map.optStringList('works'),
    actors: map.optStringList('actors'),
    relatedComics: map.optList(
      'relatedComics',
      (item) => JmComicBrief.fromMap(item),
    ),
    liked: map.optBool('liked'),
    favorite: map.optBool('favorite'),
    comments: map.optInt('comments'),
    epNames: map.optStringList('epNames'),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'id': id,
    'author': author,
    'description': description,
    'likes': likes,
    'views': views,
    'series': seriesToJsonMap(series),
    'tags': tags,
    'works': works,
    'actors': actors,
    'relatedComics': relatedComics.map((e) => e.toMap()).toList(),
    'liked': liked,
    'favorite': favorite,
    'comments': comments,
    'epNames': epNames,
  };

  factory JmComicInfo.fromJson(Map<String, dynamic> json) =>
      JmComicInfo.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  JmComicBrief toBrief() => JmComicBrief(
    id: id,
    author: author.firstOrNull ?? '',
    name: name,
    description: description,
  );

  @override
  String get cover => getJmCoverUrl(id);

  @override
  HistoryType get historyType => HistoryType.jmComic;

  @override
  String get subTitle => author.firstOrNull ?? '';

  @override
  String get target => id;

  @override
  String get title => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JmComicInfo &&
          name == other.name &&
          id == other.id &&
          TypeUtil.equal(author, other.author) &&
          description == other.description &&
          likes == other.likes &&
          views == other.views &&
          TypeUtil.equal(series, other.series) &&
          TypeUtil.equal(tags, other.tags) &&
          TypeUtil.equal(works, other.works) &&
          TypeUtil.equal(actors, other.actors) &&
          TypeUtil.equal(relatedComics, other.relatedComics) &&
          liked == other.liked &&
          favorite == other.favorite &&
          comments == other.comments &&
          TypeUtil.equal(epNames, other.epNames);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'JmComicInfo${jsonEncode(toMap())}';
}

class Comment {
  String id;
  String avatar;
  String name;
  String time;
  String content;
  List<Comment> reply;

  Comment(this.id, this.avatar, this.name, this.time, this.content, this.reply);
}

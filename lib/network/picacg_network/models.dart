import 'dart:convert';

import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

class Profile {
  final String id;
  final String title;
  final String email;
  final String name;
  final int level;
  final int exp;
  final String avatarUrl;
  final String? frameUrl;
  final bool? isPunched;
  final String? slogan;

  const Profile({
    this.id = '',
    this.title = '',
    this.email = '',
    this.name = '',
    this.level = 0,
    this.exp = 0,
    this.avatarUrl = '',
    this.frameUrl,
    this.isPunched,
    this.slogan,
  });

  Profile copyWith({
    String? id,
    String? title,
    String? email,
    String? name,
    int? level,
    int? exp,
    String? avatarUrl,
    String? frameUrl,
    bool? isPunched,
    String? slogan,
    bool clearFrameUrl = false,
    bool clearIsPunched = false,
    bool clearSlogan = false,
  }) {
    return Profile(
      id: id ?? this.id,
      title: title ?? this.title,
      email: email ?? this.email,
      name: name ?? this.name,
      level: level ?? this.level,
      exp: exp ?? this.exp,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      frameUrl: clearFrameUrl ? null : frameUrl ?? this.frameUrl,
      isPunched: clearIsPunched ? null : isPunched ?? this.isPunched,
      slogan: clearSlogan ? null : slogan ?? this.slogan,
    );
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map.optString('id'),
      title: map.optString('title'),
      email: map.optString('email'),
      name: map.optString('name'),
      level: map.optInt('level'),
      exp: map.optInt('exp'),
      avatarUrl: map.optString('avatarUrl'),
      frameUrl: map.optStringOrNull('frameUrl'),
      isPunched: map.optBoolOrNull('isPunched'),
      slogan: map.optStringOrNull('slogan'),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'email': email,
    'name': name,
    'level': level,
    'exp': exp,
    'avatarUrl': avatarUrl,
    'frameUrl': frameUrl,
    'isPunched': isPunched,
    'slogan': slogan,
  };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile &&
          id == other.id &&
          title == other.title &&
          email == other.email &&
          name == other.name &&
          level == other.level &&
          exp == other.exp &&
          avatarUrl == other.avatarUrl &&
          frameUrl == other.frameUrl &&
          isPunched == other.isPunched &&
          slogan == other.slogan;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    email,
    name,
    level,
    exp,
    avatarUrl,
    frameUrl,
    isPunched,
    slogan,
  );

  @override
  String toString() => 'Profile${jsonEncode(toMap())}';
}

class CategoryItem {
  String title;
  String path;
  CategoryItem(this.title, this.path);
}

class InitData {
  String imageServer;
  String fileServer;
  var categories = <CategoryItem>[];
  InitData(this.imageServer, this.fileServer);
}

class ComicItemBrief extends BaseComic {
  @override
  final String title;
  final String author;
  final int likes;
  final String path;
  @override
  final String id;
  @override
  final List<String> tags;
  final int? pages;

  const ComicItemBrief({
    this.title = '',
    this.author = '',
    this.likes = 0,
    this.path = '',
    this.id = '',
    this.tags = const [],
    this.pages,
  });

  ComicItemBrief copyWith({
    String? title,
    String? author,
    int? likes,
    String? path,
    String? id,
    List<String>? tags,
    int? pages,
    bool clearPages = false,
  }) {
    return ComicItemBrief(
      title: title ?? this.title,
      author: author ?? this.author,
      likes: likes ?? this.likes,
      path: path ?? this.path,
      id: id ?? this.id,
      tags: tags ?? this.tags,
      pages: clearPages ? null : pages ?? this.pages,
    );
  }

  factory ComicItemBrief.fromMap(Map<String, dynamic> map) {
    return ComicItemBrief(
      title: map.optString('title'),
      author: map.optString('author'),
      likes: map.optInt('likes'),
      path: map.optString('path'),
      id: map.optString('id'),
      tags: map.optStringList('tags'),
      pages: map.optIntOrNull('pages'),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'author': author,
    'likes': likes,
    'path': path,
    'id': id,
    'tags': tags,
    'pages': pages,
  };

  factory ComicItemBrief.fromJson(Map<String, dynamic> json) =>
      ComicItemBrief.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicItemBrief &&
          title == other.title &&
          author == other.author &&
          likes == other.likes &&
          path == other.path &&
          id == other.id &&
          TypeUtil.equal(tags, other.tags) &&
          pages == other.pages;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'ComicItemBrief${jsonEncode(toMap())}';

  @override
  String get cover => path;

  @override
  String get description => "$likes pages";

  @override
  String get subTitle => author;
}

class ComicItem with HistoryMixin {
  final String id;
  final Profile creator;
  @override
  final String title;
  final String description;
  final String thumbUrl;
  final String author;
  final String chineseTeam;
  final List<String> categories;
  final List<String> tags;
  final int likes;
  final int comments;
  final bool isLiked;
  final bool isFavourite;
  final int epsCount;
  final int pagesCount;
  final String time;
  final List<String> eps;
  final List<ComicItemBrief> recommendation;

  const ComicItem({
    this.creator = const Profile(),
    this.title = '',
    this.description = '',
    this.thumbUrl = '',
    this.author = '',
    this.chineseTeam = '',
    this.categories = const [],
    this.tags = const [],
    this.likes = 0,
    this.comments = 0,
    this.isFavourite = false,
    this.isLiked = false,
    this.epsCount = 0,
    this.id = '',
    this.pagesCount = 0,
    this.time = '',
    this.eps = const [],
    this.recommendation = const [],
  });

  ComicItem copyWith({
    Profile? creator,
    String? title,
    String? description,
    String? thumbUrl,
    String? author,
    String? chineseTeam,
    List<String>? categories,
    List<String>? tags,
    int? likes,
    int? comments,
    bool? isLiked,
    bool? isFavourite,
    int? epsCount,
    String? id,
    int? pagesCount,
    String? time,
    List<String>? eps,
    List<ComicItemBrief>? recommendation,
  }) {
    return ComicItem(
      creator: creator ?? this.creator,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbUrl: thumbUrl ?? this.thumbUrl,
      author: author ?? this.author,
      chineseTeam: chineseTeam ?? this.chineseTeam,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
      isFavourite: isFavourite ?? this.isFavourite,
      epsCount: epsCount ?? this.epsCount,
      id: id ?? this.id,
      pagesCount: pagesCount ?? this.pagesCount,
      time: time ?? this.time,
      eps: eps ?? this.eps,
      recommendation: recommendation ?? this.recommendation,
    );
  }

  ComicItemBrief toBrief() => ComicItemBrief(
    title: title,
    author: author,
    likes: likes,
    path: thumbUrl,
    id: id,
  );

  factory ComicItem.fromMap(Map<String, dynamic> map) {
    return ComicItem(
      creator: Profile.fromMap(map.optMap('creator')),
      id: map.optString('id'),
      title: map.optString('title'),
      description: map.optString('description'),
      thumbUrl: map.optString('thumbUrl'),
      author: map.optString('author'),
      chineseTeam: map.optString('chineseTeam'),
      categories: map.optStringList('categories'),
      tags: map.optStringList('tags'),
      likes: map.optInt('likes'),
      comments: map.optInt('comments'),
      isLiked: map.optBool('isLiked'),
      isFavourite: map.optBool('isFavourite'),
      epsCount: map.optInt('epsCount'),
      time: map.optString('time'),
      pagesCount: map.optInt('pagesCount'),
      eps: map.optStringList('eps'),
      recommendation: map.optList(
        'recommendation',
        (item) => ComicItemBrief.fromMap(item),
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'creator': creator.toMap(),
    'id': id,
    'title': title,
    'description': description,
    'thumbUrl': thumbUrl,
    'author': author,
    'chineseTeam': chineseTeam,
    'categories': categories,
    'tags': tags,
    'likes': likes,
    'comments': comments,
    'isLiked': isLiked,
    'isFavourite': isFavourite,
    'epsCount': epsCount,
    'time': time,
    'pagesCount': pagesCount,
    'eps': eps,
    'recommendation': recommendation.map((e) => e.toMap()).toList(),
  };

  factory ComicItem.fromJson(Map<String, dynamic> json) =>
      ComicItem.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicItem &&
          creator == other.creator &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          thumbUrl == other.thumbUrl &&
          author == other.author &&
          chineseTeam == other.chineseTeam &&
          TypeUtil.equal(categories, other.categories) &&
          TypeUtil.equal(tags, other.tags) &&
          likes == other.likes &&
          comments == other.comments &&
          isLiked == other.isLiked &&
          isFavourite == other.isFavourite &&
          epsCount == other.epsCount &&
          pagesCount == other.pagesCount &&
          time == other.time &&
          TypeUtil.equal(eps, other.eps) &&
          TypeUtil.equal(recommendation, other.recommendation);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'ComicItem${jsonEncode(toMap())}';

  @override
  String get cover => thumbUrl;

  @override
  HistoryType get historyType => HistoryType.picacg;

  @override
  String get subTitle => author;

  @override
  String get target => id;
}

class Comment {
  String name;
  String avatarUrl;
  String userId;
  int level;
  String text;
  int reply;
  String id;
  bool isLiked;
  int likes;
  String? frame;
  String? slogan;
  String time;

  @override
  String toString() => "$name:$text";

  Comment(
    this.name,
    this.avatarUrl,
    this.userId,
    this.level,
    this.text,
    this.reply,
    this.id,
    this.isLiked,
    this.likes,
    this.frame,
    this.slogan,
    this.time,
  );
}

class Comments {
  List<Comment> comments;
  String id;
  int pages;
  int loaded;

  Comments(this.comments, this.id, this.pages, this.loaded);
}

class Favorites {
  List<ComicItemBrief> comics;
  int pages;
  int loaded;

  Favorites(this.comics, this.pages, this.loaded);
}

class SearchResult {
  String keyWord;
  String sort;
  int pages;
  int loaded;
  List<ComicItemBrief> comics;
  SearchResult(this.keyWord, this.sort, this.comics, this.pages, this.loaded);
}

class Reply {
  String id;
  int loaded;
  int total;
  List<Comment> comments;
  Reply(this.id, this.loaded, this.total, this.comments);
}

class GameItemBrief {
  String id;
  String iconUrl;
  String name;
  String publisher;
  bool adult;
  GameItemBrief(this.id, this.name, this.adult, this.iconUrl, this.publisher);
}

class Games {
  List<GameItemBrief> games;
  int total;
  int loaded;
  Games(this.games, this.loaded, this.total);
}

class GameInfo {
  String id;
  String name;
  String description;
  String icon;
  String publisher;
  List<String> screenshots;
  String link;
  bool isLiked;
  int likes;
  int comments;
  GameInfo(
    this.id,
    this.name,
    this.description,
    this.icon,
    this.publisher,
    this.screenshots,
    this.link,
    this.isLiked,
    this.likes,
    this.comments,
  );
}

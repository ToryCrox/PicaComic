import 'dart:convert';

import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/type_util.dart';

class EhGalleryBrief extends BaseComic {
  @override
  final String title;
  final String type;
  final String time;
  final String uploader;
  final double stars; //0-5
  final String coverPath;
  final String link;
  @override
  final List<String> tags;
  final int? pages;

  const EhGalleryBrief({
    this.title = '',
    this.type = '',
    this.time = '',
    this.uploader = '',
    this.coverPath = '',
    this.stars = 0,
    this.link = '',
    this.tags = const [],
    this.pages,
  });

  EhGalleryBrief copyWith({
    String? title,
    String? type,
    String? time,
    String? uploader,
    String? coverPath,
    double? stars,
    String? link,
    List<String>? tags,
    int? pages,
    bool clearPages = false,
  }) {
    return EhGalleryBrief(
      title: title ?? this.title,
      type: type ?? this.type,
      time: time ?? this.time,
      uploader: uploader ?? this.uploader,
      coverPath: coverPath ?? this.coverPath,
      stars: stars ?? this.stars,
      link: link ?? this.link,
      tags: tags ?? this.tags,
      pages: clearPages ? null : pages ?? this.pages,
    );
  }

  factory EhGalleryBrief.fromMap(Map<String, dynamic> map) {
    return EhGalleryBrief(
      title: map.optString('title'),
      type: map.optString('type'),
      time: map.optString('time'),
      uploader: map.optString('uploader'),
      stars: map.optDouble('stars'),
      coverPath: map.optString('coverPath'),
      link: map.optString('link'),
      tags: map.optStringList('tags'),
      pages: map.optIntOrNull('pages'),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'type': type,
    'time': time,
    'uploader': uploader,
    'stars': stars,
    'coverPath': coverPath,
    'tags': tags,
    'link': link,
    'pages': pages,
  };

  factory EhGalleryBrief.fromJson(Map<String, dynamic> json) =>
      EhGalleryBrief.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EhGalleryBrief &&
          title == other.title &&
          type == other.type &&
          time == other.time &&
          uploader == other.uploader &&
          stars == other.stars &&
          coverPath == other.coverPath &&
          link == other.link &&
          TypeUtil.equal(tags, other.tags) &&
          pages == other.pages;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'EhGalleryBrief${jsonEncode(toMap())}';

  @override
  String get cover => coverPath;

  @override
  String get description => time;

  @override
  String get id => link;

  @override
  String get subTitle => uploader;

  @override
  bool get enableTagsTranslation => true;
}

class Galleries {
  final List<EhGalleryBrief> galleries;
  final String? next; //下一页的链接
  EhGalleryBrief operator [](int index) => galleries[index];
  int get length => galleries.length;

  const Galleries({this.galleries = const [], this.next});

  Galleries copyWith({
    List<EhGalleryBrief>? galleries,
    String? next,
    bool clearNext = false,
  }) {
    return Galleries(
      galleries: galleries ?? this.galleries,
      next: clearNext ? null : next ?? this.next,
    );
  }

  factory Galleries.fromMap(Map<String, dynamic> map) {
    return Galleries(
      galleries: List.unmodifiable(
        map.optMapList('galleries').map(EhGalleryBrief.fromMap),
      ),
      next: map.optStringOrNull('next'),
    );
  }

  Map<String, dynamic> toMap() => {
    'galleries': galleries.map((e) => e.toMap()).toList(),
    'next': next,
  };

  factory Galleries.fromJson(Map<String, dynamic> json) =>
      Galleries.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Galleries &&
          TypeUtil.equal(galleries, other.galleries) &&
          next == other.next;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'Galleries${jsonEncode(toMap())}';
}

class Comment {
  final String id;
  final String name;
  final String content;
  final String time;
  final int score;
  // true: up, false: down, null: not voted
  final bool? voteUP;

  const Comment({
    this.id = '',
    this.name = '',
    this.content = '',
    this.time = '',
    this.score = 0,
    this.voteUP,
  });

  Comment copyWith({
    String? id,
    String? name,
    String? content,
    String? time,
    int? score,
    bool? voteUP,
    bool clearVoteUP = false,
  }) {
    return Comment(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      time: time ?? this.time,
      score: score ?? this.score,
      voteUP: clearVoteUP ? null : voteUP ?? this.voteUP,
    );
  }

  factory Comment.fromMap(Map<String, dynamic> map) => Comment(
    id: map.optString('id'),
    name: map.optString('name'),
    content: map.optString('content'),
    time: map.optString('time'),
    score: map.optInt('score'),
    voteUP: map.optBoolOrNull('voteUP'),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'content': content,
    'time': time,
    'score': score,
    'voteUP': voteUP,
  };

  factory Comment.fromJson(Map<String, dynamic> json) => Comment.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Comment &&
          id == other.id &&
          name == other.name &&
          content == other.content &&
          time == other.time &&
          score == other.score &&
          voteUP == other.voteUP;

  @override
  int get hashCode => Object.hash(id, name, content, time, score, voteUP);

  @override
  String toString() => 'Comment${jsonEncode(toMap())}';
}

class Gallery with HistoryMixin {
  @override
  final String title;
  @override
  final String? subTitle;
  final String type;
  final String time;
  final String uploader;
  final double stars;
  final String? rating;
  final String coverPath;
  final Map<String, List<String>> tags;
  final List<Comment> comments;

  /// api身份验证信息
  final Map<String, String> auth;
  final bool favorite;
  final String link;
  @override
  final String maxPage;
  final int pageSize;
  final List<String> thumbnails;
  final String ext;
  final int width;
  final String fileSize;

  List<String> _generateTags() {
    var res = <String>[];
    tags.forEach((key, value) {
      for (var element in value) {
        res.add("$key:$element");
      }
    });
    return res;
  }

  Gallery({
    this.title = '',
    this.subTitle,
    this.type = '',
    this.time = '',
    this.uploader = '',
    this.stars = 0,
    this.rating,
    this.coverPath = '',
    this.tags = const {},
    this.comments = const [],
    Map<String, String>? auth,
    this.favorite = false,
    this.link = '',
    this.maxPage = '',
    this.pageSize = 20,
    this.thumbnails = const [],
    this.ext = 'jpg',
    this.width = 100,
    this.fileSize = '',
  }) : auth = Map.of(auth ?? const {});

  Gallery copyWith({
    String? title,
    String? subTitle,
    String? type,
    String? time,
    String? uploader,
    double? stars,
    String? rating,
    String? coverPath,
    Map<String, List<String>>? tags,
    List<Comment>? comments,
    Map<String, String>? auth,
    bool? favorite,
    String? link,
    String? maxPage,
    int? pageSize,
    List<String>? thumbnails,
    String? ext,
    int? width,
    String? fileSize,
    bool clearSubTitle = false,
    bool clearRating = false,
    bool clearAuth = false,
  }) {
    return Gallery(
      title: title ?? this.title,
      subTitle: clearSubTitle ? null : subTitle ?? this.subTitle,
      type: type ?? this.type,
      time: time ?? this.time,
      uploader: uploader ?? this.uploader,
      stars: stars ?? this.stars,
      rating: clearRating ? null : rating ?? this.rating,
      coverPath: coverPath ?? this.coverPath,
      tags: tags ?? this.tags,
      comments: comments ?? this.comments,
      auth: clearAuth ? null : auth ?? this.auth,
      favorite: favorite ?? this.favorite,
      link: link ?? this.link,
      maxPage: maxPage ?? this.maxPage,
      pageSize: pageSize ?? this.pageSize,
      thumbnails: thumbnails ?? this.thumbnails,
      ext: ext ?? this.ext,
      width: width ?? this.width,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  factory Gallery.fromMap(Map<String, dynamic> map) {
    final tags = map
        .optMap('tags')
        .map((key, value) => MapEntry(key, TypeUtil.parseStringList(value)));
    final authMap = map.optMapOrNull('auth');
    return Gallery(
      title: map.optString('title'),
      type: map.optString('type'),
      time: map.optString('time'),
      uploader: map.optString('uploader'),
      subTitle: map.optStringOrNull('subTitle'),
      stars: map.optDouble('stars'),
      rating: map.optStringOrNull('rating'),
      coverPath: map.optString('coverPath'),
      tags: tags,
      favorite: map.optBool('favorite'),
      link: map.optString('link'),
      maxPage: map.optString('maxPage'),
      pageSize: map.optInt('pageSize', 20),
      thumbnails: map.optStringList('thumbnails'),
      ext: map.optString('ext', 'jpg'),
      width: map.optInt('width', 100),
      fileSize: map.optString('fileSize'),
      auth: authMap?.map(
        (key, value) => MapEntry(key, TypeUtil.parseString(value)),
      ),
      comments: map.optList('comments', (item) => Comment.fromMap(item)),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'subTitle': subTitle,
    'type': type,
    'time': time,
    'uploader': uploader,
    'stars': stars,
    'rating': rating,
    'coverPath': coverPath,
    'tags': tags,
    'favorite': favorite,
    'link': link,
    'maxPage': maxPage,
    'pageSize': pageSize,
    'ext': ext,
    'width': width,
    'fileSize': fileSize,
    'thumbnails': thumbnails,
    'auth': auth,
    'comments': comments.map((comment) => comment.toMap()).toList(),
  };

  factory Gallery.fromJson(Map<String, dynamic> json) => Gallery.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  EhGalleryBrief toBrief() => EhGalleryBrief(
    title: title,
    type: type,
    time: time,
    uploader: uploader,
    coverPath: coverPath,
    stars: stars,
    link: link,
    tags: _generateTags(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Gallery &&
          title == other.title &&
          subTitle == other.subTitle &&
          type == other.type &&
          time == other.time &&
          uploader == other.uploader &&
          stars == other.stars &&
          rating == other.rating &&
          coverPath == other.coverPath &&
          TypeUtil.equal(tags, other.tags) &&
          TypeUtil.equal(comments, other.comments) &&
          TypeUtil.equal(auth, other.auth) &&
          favorite == other.favorite &&
          link == other.link &&
          maxPage == other.maxPage &&
          pageSize == other.pageSize &&
          TypeUtil.equal(thumbnails, other.thumbnails) &&
          ext == other.ext &&
          width == other.width &&
          fileSize == other.fileSize;

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'Gallery${jsonEncode(toMap())}';

  @override
  String get cover => coverPath;

  @override
  HistoryType get historyType => HistoryType.ehentai;

  @override
  String get target => link;
}

enum EhLeaderboardType {
  yesterday(15),
  month(13),
  year(12),
  all(11);

  final int value;

  const EhLeaderboardType(this.value);

  static EhLeaderboardType fromValue(int value) {
    switch (value) {
      case 15:
        return EhLeaderboardType.yesterday;
      case 13:
        return EhLeaderboardType.month;
      case 12:
        return EhLeaderboardType.year;
      case 11:
        return EhLeaderboardType.all;
      default:
        throw Exception("Invalid value");
    }
  }
}

class EhLeaderboard {
  EhLeaderboardType type;
  List<EhGalleryBrief> galleries;
  int loaded;
  static const int max = 199;

  EhLeaderboard(this.type, this.galleries, this.loaded);
}

class EhImageLimit {
  final int current;
  final int max;
  final int resetCost;
  final int kGP;
  final int credits;

  const EhImageLimit(
    this.current,
    this.max,
    this.resetCost,
    this.kGP,
    this.credits,
  );
}

class ArchiveDownloadInfo {
  final String originSize;
  final String resampleSize;
  final String originCost;
  final String resampleCost;
  final String? cancelUnlockUrl;

  const ArchiveDownloadInfo(
    this.originSize,
    this.resampleSize,
    this.originCost,
    this.resampleCost,
    this.cancelUnlockUrl,
  );
}

part of "history.dart";

// 表名常量
const String kTableImageFavorites = 'image_favorites';

// 字段名常量
const String kImageFavoriteId = 'id';
const String kImageFavoriteTitle = 'title';
const String kImageFavoriteCover = 'cover';
const String kImageFavoriteEp = 'ep';
const String kImageFavoritePage = 'page';
const String kImageFavoriteOther = 'other';

// 直接用history.db了, 没必要再加一个favorites.db

class ImageFavorite {
  /// unique id for the comic
  final String id;

  final String imagePath;

  final String title;

  final int ep;

  final int page;

  final Map<String, dynamic> otherInfo;

  const ImageFavorite({
    required this.id,
    required this.imagePath,
    required this.title,
    required this.ep,
    required this.page,
    this.otherInfo = const {},
  });

  ImageFavorite copyWith({
    String? id,
    String? imagePath,
    String? title,
    int? ep,
    int? page,
    Map<String, dynamic>? otherInfo,
  }) => ImageFavorite(
    id: id ?? this.id,
    imagePath: imagePath ?? this.imagePath,
    title: title ?? this.title,
    ep: ep ?? this.ep,
    page: page ?? this.page,
    otherInfo: otherInfo ?? this.otherInfo,
  );

  factory ImageFavorite.fromMap(Map<String, dynamic> map) => ImageFavorite(
    id: map.optString(kImageFavoriteId),
    imagePath: map.optString(kImageFavoriteCover, map.optString('imagePath')),
    title: map.optString(kImageFavoriteTitle),
    ep: map.optInt(kImageFavoriteEp),
    page: map.optInt(kImageFavoritePage),
    otherInfo: map.optMap(kImageFavoriteOther),
  );

  factory ImageFavorite.fromRow(Map<String, dynamic> map) =>
      ImageFavorite.fromMap(map);

  factory ImageFavorite.fromJson(Map<String, dynamic> json) =>
      ImageFavorite.fromMap(json);

  Map<String, dynamic> toMap() => {
    kImageFavoriteId: id,
    kImageFavoriteCover: imagePath,
    kImageFavoriteTitle: title,
    kImageFavoriteEp: ep,
    kImageFavoritePage: page,
    kImageFavoriteOther: otherInfo,
  };

  Map<String, dynamic> toJson() => toMap();

  Map<String, dynamic> toRow() => {
    kImageFavoriteId: id,
    kImageFavoriteCover: imagePath,
    kImageFavoriteTitle: title,
    kImageFavoriteEp: ep,
    kImageFavoritePage: page,
    kImageFavoriteOther: jsonEncode(otherInfo),
  };

  @override
  String toString() {
    return 'ImageFavorite{id: $id, imagePath: $imagePath, title: $title, ep: $ep, page: $page, otherInfo: $otherInfo}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageFavorite &&
          id == other.id &&
          imagePath == other.imagePath &&
          title == other.title &&
          ep == other.ep &&
          page == other.page &&
          TypeUtil.equal(otherInfo, other.otherInfo);

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;
}

class ImageFavoriteManager {
  static Future<Database> get _db => HistoryManager().db;

  /// 检查表image_favorites是否存在, 不存在则创建
  static Future<void> createTable(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS $kTableImageFavorites ("
      "$kImageFavoriteId TEXT,"
      "$kImageFavoriteTitle TEXT NOT NULL,"
      "$kImageFavoriteCover TEXT NOT NULL,"
      "$kImageFavoriteEp INTEGER NOT NULL,"
      "$kImageFavoritePage INTEGER NOT NULL,"
      "$kImageFavoriteOther TEXT NOT NULL,"
      "PRIMARY KEY ($kImageFavoriteId, $kImageFavoriteEp, $kImageFavoritePage)"
      ");",
    );
  }

  static Future<void> add(ImageFavorite favorite) async {
    final db = await _db;
    await db.insert(
      kTableImageFavorites,
      favorite.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    Webdav.uploadData();
  }

  static Future<List<ImageFavorite>> getAll() async {
    final db = await _db;
    var res = await db.query(kTableImageFavorites);
    return res.map(ImageFavorite.fromRow).toList();
  }

  static Future<List<ImageFavorite>> getAllByTitle(String title) async {
    final db = await _db;
    final res = await db.query(
      kTableImageFavorites,
      where: '$kImageFavoriteTitle = ?',
      whereArgs: [title],
    );
    return res.map(ImageFavorite.fromRow).toList();
  }

  static Future<List<String>> getAllTitle() async {
    final db = await _db;
    final res = await db.query(
      kTableImageFavorites,
      columns: [kImageFavoriteTitle],
      distinct: true,
    );
    return res
        .map((e) => TypeUtil.parseString(e[kImageFavoriteTitle]))
        .toList();
  }

  static Future<void> delete(ImageFavorite favorite) async {
    final db = await _db;
    await db.delete(
      kTableImageFavorites,
      where:
          '$kImageFavoriteId = ? AND $kImageFavoriteEp = ? AND $kImageFavoritePage = ?',
      whereArgs: [favorite.id, favorite.ep, favorite.page],
    );
    Webdav.uploadData();
  }

  static Future<bool> exist(String id, int ep, int page) async {
    final db = await _db;
    var res = await db.query(
      kTableImageFavorites,
      where:
          '$kImageFavoriteId = ? AND $kImageFavoriteEp = ? AND $kImageFavoritePage = ?',
      whereArgs: [id, ep, page],
    );
    return res.isNotEmpty;
  }

  static Future<int> get length async {
    final db = await _db;
    var res = await db.rawQuery("select count(*) from $kTableImageFavorites;");
    return res.first.values.first! as int;
  }
}

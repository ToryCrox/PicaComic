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

class ImageFavorite{
  /// unique id for the comic
  final String id;

  final String imagePath;

  final String title;

  final int ep;

  final int page;

  final Map<String, dynamic> otherInfo;

  const ImageFavorite(this.id, this.imagePath, this.title, this.ep, this.page, this.otherInfo);

  @override
  String toString() {
    return 'ImageFavorite{id: $id, imagePath: $imagePath, title: $title, ep: $ep, page: $page, otherInfo: $otherInfo}';
  }
}

class ImageFavoriteManager{
  static Future<Database> get _db => HistoryManager().db;

  /// 检查表image_favorites是否存在, 不存在则创建
  static Future<void> createTable(Database db) async {
    await db.execute("CREATE TABLE IF NOT EXISTS $kTableImageFavorites ("
        "$kImageFavoriteId TEXT,"
        "$kImageFavoriteTitle TEXT NOT NULL,"
        "$kImageFavoriteCover TEXT NOT NULL,"
        "$kImageFavoriteEp INTEGER NOT NULL,"
        "$kImageFavoritePage INTEGER NOT NULL,"
        "$kImageFavoriteOther TEXT NOT NULL,"
        "PRIMARY KEY ($kImageFavoriteId, $kImageFavoriteEp, $kImageFavoritePage)"
        ");");
  }

  static Future<void> add(ImageFavorite favorite) async {
    final db = await _db;
    await db.insert(kTableImageFavorites, {
      kImageFavoriteId: favorite.id,
      kImageFavoriteTitle: favorite.title,
      kImageFavoriteCover: favorite.imagePath,
      kImageFavoriteEp: favorite.ep,
      kImageFavoritePage: favorite.page,
      kImageFavoriteOther: jsonEncode(favorite.otherInfo)
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    Webdav.uploadData();
    Future.microtask(() => StateController.findOrNull(tag: "me_page")?.update());
  }

  static Future<List<ImageFavorite>> getAll() async {
    final db = await _db;
    var res = await db.query(kTableImageFavorites);
    return res
        .map((e) => ImageFavorite(
            e[kImageFavoriteId] as String,
            e[kImageFavoriteCover] as String,
            e[kImageFavoriteTitle] as String,
            e[kImageFavoriteEp] as int,
            e[kImageFavoritePage] as int,
            jsonDecode(e[kImageFavoriteOther] as String)))
        .toList();
  }

  static Future<List<ImageFavorite>> getAllByTitle(String title) async {
    final db = await _db;
    final res = await db.query(kTableImageFavorites,
        where: '$kImageFavoriteTitle = ?', whereArgs: [title]);
    return res
        .map((e) => ImageFavorite(
            e[kImageFavoriteId] as String,
            e[kImageFavoriteCover] as String,
            e[kImageFavoriteTitle] as String,
            e[kImageFavoriteEp] as int,
            e[kImageFavoritePage] as int,
            jsonDecode(e[kImageFavoriteOther] as String)))
        .toList();
  }

  static Future<List<String>> getAllTitle() async {
    final db = await _db;
    final res = await db.query(
      kTableImageFavorites,
      columns: [kImageFavoriteTitle],
      distinct: true,
    );
    return res.map((e) => e[kImageFavoriteTitle] as String).toList();
  }

  static Future<void> delete(ImageFavorite favorite) async {
    final db = await _db;
    await db.delete(
      kTableImageFavorites,
      where: '$kImageFavoriteId = ? AND $kImageFavoriteEp = ? AND $kImageFavoritePage = ?',
      whereArgs: [favorite.id, favorite.ep, favorite.page]
    );
    Webdav.uploadData();
  }

  static Future<bool> exist(String id, int ep, int page) async {
    final db = await _db;
    var res = await db.query(
      kTableImageFavorites,
      where: '$kImageFavoriteId = ? AND $kImageFavoriteEp = ? AND $kImageFavoritePage = ?',
      whereArgs: [id, ep, page]
    );
    return res.isNotEmpty;
  }

  static Future<int> get length async {
    final db = await _db;
    var res = await db.rawQuery("select count(*) from $kTableImageFavorites;");
    return res.first.values.first! as int;
  }
}
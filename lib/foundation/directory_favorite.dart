import 'database/download_database.dart';
import '../tools/map_extension.dart';

/// 本地目录收藏的不可变持久化记录。
class LocalFavoriteItem {
  final String path;
  final int sortOrder;
  final int time;

  const LocalFavoriteItem({
    required this.path,
    required this.sortOrder,
    required this.time,
  });

  LocalFavoriteItem copyWith({String? path, int? sortOrder, int? time}) =>
      LocalFavoriteItem(
        path: path ?? this.path,
        sortOrder: sortOrder ?? this.sortOrder,
        time: time ?? this.time,
      );

  factory LocalFavoriteItem.fromMap(Map<String, dynamic> map) {
    return LocalFavoriteItem(
      path: map.optString(kLocalFavoritePath),
      sortOrder: map.optInt(kLocalFavoriteSortOrder),
      time: map.optInt(kLocalFavoriteTime),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      kLocalFavoritePath: path,
      kLocalFavoriteSortOrder: sortOrder,
      kLocalFavoriteTime: time,
    };
  }

  factory LocalFavoriteItem.fromJson(Map<String, dynamic> json) =>
      LocalFavoriteItem.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalFavoriteItem &&
          path == other.path &&
          sortOrder == other.sortOrder &&
          time == other.time;

  @override
  int get hashCode => Object.hash(path, sortOrder, time);

  @override
  String toString() => 'LocalFavoriteItem${toMap()}';
}

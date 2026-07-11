import 'package:pica_comic/base.dart';

/// 禁漫图片混淆 ID
///
/// 用于图片反混淆处理，似乎所有漫画的 scramble ID 都相同
const String kJmScrambleId = "220980";

String getBaseUrl() {
  return appdata.settings[86];
}

String getJmCoverUrl(String id) {
  return "${getBaseUrl()}/media/albums/${id}_3x4.jpg";
}

String getJmImageUrl(String imageName, String id) {
  return "${getBaseUrl()}/media/photos/$id/$imageName";
}

String getJmAvatarUrl(String imageName) {
  return "${getBaseUrl()}/media/users/$imageName";
}

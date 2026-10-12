import 'package:pica_comic/base.dart';

/// 禁漫图片混淆 ID
///
/// 用于图片反混淆处理，似乎所有漫画的 scramble ID 都相同
const String kJmScrambleId = "220980";

String getBaseUrl() {
  return appdata.getSetting(AppSettingKeys.jmImageDomain);
}

String buildJmCoverUrl(String baseUrl, String id) {
  return "$baseUrl/media/albums/${id}_3x4.jpg";
}

String getJmCoverUrl(String id) {
  return buildJmCoverUrl(getBaseUrl(), id);
}

String buildJmImageUrl(String baseUrl, String imageName, String id) {
  return "$baseUrl/media/photos/$id/$imageName";
}

String getJmImageUrl(String imageName, String id) {
  return buildJmImageUrl(getBaseUrl(), imageName, id);
}

String buildJmAvatarUrl(String baseUrl, String imageName) {
  return "$baseUrl/media/users/$imageName";
}

String getJmAvatarUrl(String imageName) {
  return buildJmAvatarUrl(getBaseUrl(), imageName);
}

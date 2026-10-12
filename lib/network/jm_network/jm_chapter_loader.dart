import 'package:pica_comic/network/download/download_exceptions.dart';
import 'package:pica_comic/network/res.dart';

/// 指定 JM 章节在有限次请求后仍无法取得图片列表。
class JmChapterLoadException extends DownloadNonRetryableException {
  const JmChapterLoadException(this.episodeIndex, this.chapterId, this.cause);

  /// 从 1 开始的章节序号。
  final int episodeIndex;

  /// 服务端使用的章节 ID。
  final String chapterId;

  /// 最后一次请求失败的原因。
  final Object? cause;

  @override
  String get message => 'JM 章节 $episodeIndex (ID $chapterId) 获取图片信息失败: $cause';
}

/// 取得章节图片列表；失败后只在当前章节内重试两次。
Future<List<String>> fetchJmChapterImages(
  int episodeIndex,
  String chapterId,
  Future<Res<List<String>>> Function(String chapterId) fetch, {
  Future<void> Function(Duration delay)? waitBeforeRetry,
}) async {
  if (chapterId.isEmpty) {
    throw JmChapterLoadException(episodeIndex, chapterId, '章节 ID 为空');
  }

  Object? lastError;
  var emptyResponses = 0;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final response = await fetch(chapterId);
      if (response.error) {
        if (response.errorMessage?.toLowerCase().contains('empty data') ==
            true) {
          emptyResponses++;
        }
        throw StateError(response.errorMessageWithoutNull);
      }

      final images = response.data;
      if (images.isEmpty) {
        emptyResponses++;
        throw const FormatException('Empty chapter images');
      }
      return images;
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        const delay = Duration(seconds: 3);
        await (waitBeforeRetry?.call(delay) ?? Future<void>.delayed(delay));
      }
    }
  }

  if (emptyResponses == 3) {
    throw JmChapterLoadException(episodeIndex, chapterId, lastError);
  }
  throw Exception('JM 章节 $episodeIndex (ID $chapterId) 获取图片信息失败: $lastError');
}

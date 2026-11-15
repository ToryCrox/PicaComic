part of 'components.dart';

class PicaImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Map<String, String>? headers;
  final String? sourceKey;
  final bool? isThumbnail;
  final String? comicId;
  final String? epId;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final bool fade;
  final String? cacheKey;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const PicaImage({
    required this.url,
    super.key,
    this.width,
    this.height,
    this.fit,
    this.headers,
    this.sourceKey,
    this.isThumbnail,
    this.comicId,
    this.epId,
    this.placeholder,
    this.errorWidget,
    this.fade = true,
    this.cacheKey,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  /// 缩略图统一使用的解码宽度。
  ///
  /// 列表卡片、详情页封面与 Hero 飞行层必须共用同一档位：`memCacheWidth`
  /// 参与 `CachedNetworkImageProvider` 的相等判断，两端不同就是两个缓存项，
  /// Hero 落地时必然重新解码，视觉上就是封面先空一下再出现。
  static const int thumbnailCacheWidth = kComicThumbnailCacheWidth;

  /// 根据缩略图的逻辑宽度和设备像素比计算分档后的内存解码宽度。
  ///
  /// 保留该计算方法供响应式场景与非 Hero 图片使用；封面缩略图已统一到
  /// [thumbnailCacheWidth]，不再随布局宽度变化。
  @visibleForTesting
  static int calculateThumbnailCacheWidth(
    double logicalWidth,
    double devicePixelRatio,
  ) {
    final physicalWidth = logicalWidth * devicePixelRatio;
    const cacheWidthStep = 64;
    return ((physicalWidth / cacheWidthStep).ceil() * cacheWidthStep)
        .clamp(cacheWidthStep, 1024)
        .toInt();
  }

  @override
  Widget build(BuildContext context) {
    // 决定 BoxFit
    final imageFit =
        fit ??
        (appdata.getSetting(AppSettingKeys.thumbnailFit) == "0"
            ? BoxFit.cover
            : BoxFit.contain);

    final Map<String, String> finalHeaders = {
      ...?headers,
      if (sourceKey != null) 'sourceKey': sourceKey!,
      if (isThumbnail != null) 'isThumbnail': isThumbnail!.toString(),
      if (comicId != null) 'comicId': comicId!,
      if (epId != null) 'epId': epId!,
    };

    // Hero 飞行期间关闭淡入：缓存命中时 CachedNetworkImage 会从全透明重新
    // 播放一次淡入，飞行途中就表现为封面忽明忽暗。
    final inHeroFlight = HeroImageScope.maybeOf(context) != null;
    final effectiveFade = fade && !inHeroFlight;

    Widget buildImage(int? targetMemCacheWidth) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheKey: cacheKey,
        httpHeaders: finalHeaders,
        width: width,
        height: height,
        fit: imageFit,
        cacheManager: picaImageManager,
        memCacheWidth: targetMemCacheWidth,
        memCacheHeight: memCacheHeight,
        fadeOutDuration: effectiveFade
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        fadeInDuration: effectiveFade
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        placeholder: placeholder ?? (context, url) => const Center(),
        errorWidget:
            errorWidget ??
            (context, url, error) => const Center(child: Icon(Icons.error)),
      );
    }

    // 缩略图（以及飞行层里的任何图片）一律使用统一档位，避免约束变化导致
    // provider 在飞行途中被替换。
    final resolvedCacheWidth =
        memCacheWidth ??
        ((isThumbnail == true || inHeroFlight) ? thumbnailCacheWidth : null);
    return buildImage(resolvedCacheWidth);
  }
}

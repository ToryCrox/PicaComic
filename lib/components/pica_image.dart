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

  /// 根据缩略图的逻辑宽度和设备像素比计算分档后的内存解码宽度。
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
        fit ?? (appdata.settings[66] == "0" ? BoxFit.cover : BoxFit.contain);

    final Map<String, String> finalHeaders = {
      ...?headers,
      if (sourceKey != null) 'sourceKey': sourceKey!,
      if (isThumbnail != null) 'isThumbnail': isThumbnail!.toString(),
      if (comicId != null) 'comicId': comicId!,
      if (epId != null) 'epId': epId!,
    };

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
        fadeOutDuration: fade
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        fadeInDuration: fade
            ? const Duration(milliseconds: 200)
            : Duration.zero,
        placeholder: placeholder ?? (context, url) => const Center(),
        errorWidget:
            errorWidget ??
            (context, url, error) => const Center(child: Icon(Icons.error)),
      );
    }

    if (isThumbnail != true || memCacheWidth != null) {
      return buildImage(memCacheWidth);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : width;
        if (logicalWidth == null ||
            !logicalWidth.isFinite ||
            logicalWidth <= 0) {
          return buildImage(null);
        }
        final cacheWidth = calculateThumbnailCacheWidth(
          logicalWidth,
          MediaQuery.devicePixelRatioOf(context),
        );
        return buildImage(cacheWidth);
      },
    );
  }
}

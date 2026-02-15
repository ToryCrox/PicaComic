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
  });

  @override
  Widget build(BuildContext context) {
    // 决定 BoxFit
    final imageFit = fit ?? (appdata.settings[66] == "0" ? BoxFit.cover : BoxFit.contain);

    final Map<String, String> finalHeaders = {
      ...?headers,
      if (sourceKey != null) 'sourceKey': sourceKey!,
      if (isThumbnail != null) 'isThumbnail': isThumbnail!.toString(),
      if (comicId != null) 'comicId': comicId!,
      if (epId != null) 'epId': epId!,
    };

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: finalHeaders,
      width: width,
      height: height,
      fit: imageFit,
      cacheManager: picaImageManager,
      fadeOutDuration: fade ? const Duration(milliseconds: 200) : Duration.zero,
      fadeInDuration: fade ? const Duration(milliseconds: 200) : Duration.zero,
      placeholder: placeholder ?? (context, url) => const Center(),
      errorWidget: errorWidget ?? (context, url, error) => const Center(
        child: Icon(Icons.error),
      ),
    );
  }
}

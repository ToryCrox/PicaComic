part of 'components.dart';

class PicaImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Map<String, String>? headers;
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
    this.placeholder,
    this.errorWidget,
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    // 决定 BoxFit
    final imageFit = fit ?? (appdata.settings[66] == "0" ? BoxFit.cover : BoxFit.contain);

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
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

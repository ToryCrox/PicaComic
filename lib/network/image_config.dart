class ImageConfig {
  final String url;
  final String method;
  final Map<String, String>? headers;
  final dynamic data;
  final dynamic onResponse;

  const ImageConfig({
    required this.url,
    this.method = 'GET',
    this.headers,
    this.data,
    this.onResponse,
  });
}

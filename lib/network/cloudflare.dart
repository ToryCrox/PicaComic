import 'dart:convert';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/pages/webview.dart';
import 'package:pica_comic/tools/translations.dart';

import '../components/components.dart';

class CloudflareException implements DioException {
  final String url;

  const CloudflareException(this.url);

  @override
  String toString() {
    return "CloudflareException: $url";
  }

  static CloudflareException? fromString(String message) {
    var match = RegExp(r"CloudflareException: (.+)").firstMatch(message);
    if (match == null) return null;
    return CloudflareException(match.group(1)!);
  }

  @override
  DioException copyWith({
    RequestOptions? requestOptions,
    Response<dynamic>? response,
    DioExceptionType? type,
    Object? error,
    StackTrace? stackTrace,
    String? message,
  }) {
    return this;
  }

  @override
  Object? get error => this;

  @override
  String? get message => toString();

  @override
  RequestOptions get requestOptions => RequestOptions();

  @override
  Response? get response => null;

  @override
  StackTrace get stackTrace => StackTrace.empty;

  @override
  DioExceptionType get type => DioExceptionType.badResponse;
}

class CloudflareInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['cloudflare'] != true) {
      handler.next(options);
      return;
    }
    if (options.headers['cookie'].toString().contains('cf_clearance')) {
      options.headers['user-agent'] = appdata.implicitData[3];
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.requestOptions.extra['cloudflare'] != true) {
      handler.next(err);
      return;
    }
    if (err.response?.statusCode == 403) {
      handler.next(_check(err.response!) ?? err);
    } else {
      handler.next(err);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra['cloudflare'] != true) {
      handler.next(response);
      return;
    }
    if (response.statusCode == 403) {
      var err = _check(response);
      if (err != null) {
        handler.reject(err);
        return;
      }
    }
    handler.next(response);
  }

  CloudflareException? _check(Response response) {
    if (response.headers['cf-mitigated']?.firstOrNull == "challenge") {
      return CloudflareException(response.requestOptions.uri.toString());
    }
    return null;
  }
}

void passCloudflare(CloudflareException e, void Function() onFinished) async {
  var url = e.url;
  var uri = Uri.parse(url);

  Future<void> saveCookies(Map<String, String> cookies) async {
    var domain = uri.host;
    var splits = domain.split('.');
    if (splits.length > 1) {
      domain = ".${splits[splits.length - 2]}.${splits[splits.length - 1]}";
    }
    await SingleInstanceCookieJar.instance!.saveFromResponse(
      uri,
      List<io.Cookie>.generate(cookies.length, (index) {
        var cookie = io.Cookie(
          cookies.keys.elementAt(index),
          cookies.values.elementAt(index),
        );
        cookie.domain = domain;
        return cookie;
      }),
    );
  }

  if (App.isDesktop && (await DesktopWebview.isAvailable())) {
    var verificationCheckInProgress = false;
    var verificationCompleted = false;
    var webview = DesktopWebview(
      initialUrl: url,
      onTitleChange: (_, controller) async {
        if (verificationCheckInProgress || verificationCompleted) return;
        verificationCheckInProgress = true;
        try {
          var ua = controller.userAgent;
          if (ua != null && ua.isNotEmpty && appdata.implicitData[3] != ua) {
            appdata.implicitData[3] = ua;
            appdata.writeImplicitData();
          }

          final challengeResolved = await controller.evaluateJavascript('''
            (function() {
              if (document.readyState !== 'complete') return false;
              const title = (document.title || '').toLowerCase();
              // 正常页面也可能保留 Cloudflare 脚本，只判断可见的挑战控件。
              const isVisible = (element) => {
                const style = getComputedStyle(element);
                const bounds = element.getBoundingClientRect();
                return style.display !== 'none' &&
                  style.visibility !== 'hidden' &&
                  style.opacity !== '0' &&
                  bounds.width > 0 && bounds.height > 0;
              };
              const challengeElements = document.querySelectorAll(
                '#challenge-form, #challenge-stage, #challenge-running, #challenge-spinner, #challenge-error-text, [id^="cf-chl-widget"], iframe[src*="challenges.cloudflare.com/cdn-cgi/challenge-platform/"]'
              );
              const challengeVisible =
                title.includes('just a moment') ||
                title.includes('please wait') ||
                title.includes('请稍候') ||
                title.includes('安全验证') ||
                Array.from(challengeElements).some(isVisible);
              return !challengeVisible;
            })()
          ''');
          if (!_isJavaScriptTrue(challengeResolved)) return;

          final cookieDetails = await controller.getCookieDetails(url);
          final hasClearance = cookieDetails.any((cookie) {
            final expires = cookie['expires'];
            final isExpired =
                expires is DateTime && expires.isBefore(DateTime.now());
            return cookie['name'] == 'cf_clearance' &&
                !isExpired &&
                (cookie['value']?.toString().isNotEmpty ?? false);
          });
          if (!hasClearance) return;

          await _saveWebviewCookies(uri, cookieDetails);
          verificationCompleted = true;
          Log.i('Cloudflare 验证完成，Cookie 已同步，关闭窗口并重试请求。');
          controller.close();
          onFinished();
        } catch (error, stackTrace) {
          Log.w('Cloudflare verification check failed: $error\n$stackTrace');
        } finally {
          verificationCheckInProgress = false;
        }
      },
    );
    webview.open();
  } else if (App.isMobile) {
    await App.globalTo(
      () => AppWebview(
        initialUrl: url,
        singlePage: true,
        onTitleChange: (title, controller) async {
          var res = await controller.platform.evaluateJavascript(
            source:
                "document.head.innerHTML.includes('#challenge-success-text')",
          );
          if (res == false) {
            var ua = await controller.getUA();
            if (ua != null) {
              appdata.implicitData[3] = ua;
              appdata.writeImplicitData();
            }
            var cookiesMap = await controller.getCookies(url) ?? {};
            if (cookiesMap['cf_clearance'] == null) {
              return;
            }
            await saveCookies(cookiesMap);
            App.globalBack();
          }
        },
        onStarted: (controller) async {
          var ua = await controller.getUA();
          if (ua != null) {
            appdata.implicitData[3] = ua;
            appdata.writeImplicitData();
          }
          var cookiesMap = await controller.getCookies(url) ?? {};
          await saveCookies(cookiesMap);
        },
      ),
    );
    onFinished();
  } else {
    showToast(message: "当前设备不支持".tl);
  }
}

bool _isJavaScriptTrue(String? value) {
  if (value == null) return false;
  final result = value.replaceAll('\u0000', '').trim();
  if (result == 'true') return true;
  try {
    final decoded = jsonDecode(result);
    return decoded == true || decoded == 'true';
  } catch (_) {
    return false;
  }
}

Future<void> _saveWebviewCookies(
  Uri uri,
  List<Map<String, dynamic>> cookieDetails,
) async {
  final jar = SingleInstanceCookieJar.instance!;
  final cookies = <io.Cookie>[];
  for (final details in cookieDetails) {
    final name = details['name']?.toString() ?? '';
    final value = details['value']?.toString() ?? '';
    if (name.isEmpty || value.isEmpty) continue;

    final cookie = io.Cookie(name, value)
      ..domain = details['domain']?.toString() ?? uri.host
      ..path = details['path']?.toString() ?? '/'
      ..secure = details['secure'] == true
      ..httpOnly = details['httpOnly'] == true;
    final expires = details['expires'];
    if (expires is DateTime) {
      if (expires.isBefore(DateTime.now())) continue;
      cookie.expires = expires;
    } else if (details['sessionOnly'] == true) {
      cookie.expires = DateTime.now().add(const Duration(hours: 1));
    }
    cookies.add(cookie);
  }
  if (cookies.isEmpty) return;

  await jar.deleteCookiesForRequest(uri, cookies.map((cookie) => cookie.name));
  await jar.saveFromResponse(uri, cookies);
}

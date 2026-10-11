import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/http_client.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';

export 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show WebUri, URLRequest;

extension WebviewExtension on InAppWebViewController {
  Future<Map<String, String>?> getCookies(String url) async {
    if (url.contains("https://")) {
      url.replaceAll("https://", "");
    }
    if (url[url.length - 1] == '/') {
      url = url.substring(0, url.length - 1);
    }
    CookieManager cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(url: WebUri(url));
    Map<String, String> res = {};
    for (var cookie in cookies) {
      res[cookie.name] = cookie.value;
    }
    return res;
  }

  Future<String?> getUA() async {
    var res = await evaluateJavascript(source: "navigator.userAgent");
    if (res is String) {
      if (res[0] == "'" || res[0] == "\"") {
        res = res.substring(1, res.length - 1);
      }
    }
    return res is String ? res : null;
  }
}

class AppWebview extends StatefulWidget {
  const AppWebview({
    required this.initialUrl,
    this.onTitleChange,
    this.onNavigation,
    this.singlePage = false,
    this.onStarted,
    super.key,
  });

  final String initialUrl;

  final void Function(String title, InAppWebViewController controller)?
  onTitleChange;

  final bool Function(String url)? onNavigation;

  final void Function(InAppWebViewController controller)? onStarted;

  final bool singlePage;

  @override
  State<AppWebview> createState() => _AppWebviewState();
}

class _AppWebviewState extends State<AppWebview> {
  InAppWebViewController? controller;

  String title = "Webview";

  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    bool useCustomAppBar = !UiMode.m1(context) && !widget.singlePage;

    final actions = [
      PopupMenuButton<void>(
        tooltip: "更多".tl,
        position: PopupMenuPosition.under,
        icon: const Icon(Icons.more_horiz),
        itemBuilder: (_) => [
          popupMenuItem<void>(
            text: "在浏览器中打开".tl,
            icon: Icons.open_in_browser,
            onTap: () async {
              final url = await controller?.getUrl();
              if (url != null) {
                await launchUrlString(url.path);
              }
            },
          ),
          popupMenuItem<void>(
            text: "复制链接".tl,
            icon: Icons.link,
            onTap: () async {
              final url = await controller?.getUrl();
              if (url != null) {
                await Clipboard.setData(ClipboardData(text: url.path));
              }
            },
          ),
          popupMenuItem<void>(
            text: "重新加载".tl,
            icon: Icons.refresh,
            onTap: () => controller?.reload(),
          ),
        ],
      ),
    ];

    Widget body = InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      onTitleChanged: (c, t) {
        if (mounted) {
          setState(() {
            title = t ?? "Webview";
          });
        }
        widget.onTitleChange?.call(title, controller!);
      },
      shouldOverrideUrlLoading: (c, r) async {
        var res =
            widget.onNavigation?.call(r.request.url?.toString() ?? "") ?? false;
        if (res) {
          return NavigationActionPolicy.CANCEL;
        } else {
          return NavigationActionPolicy.ALLOW;
        }
      },
      onWebViewCreated: (c) {
        controller = c;
        widget.onStarted?.call(c);
      },
      onProgressChanged: (c, p) {
        if (mounted) {
          setState(() {
            _progress = p / 100;
          });
        }
      },
    );

    body = Stack(
      children: [
        Positioned.fill(child: body),
        if (_progress < 1.0)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );

    if (useCustomAppBar) {
      body = Column(
        children: [
          Appbar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: actions,
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: !useCustomAppBar
          ? AppBar(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: actions,
            )
          : null,
      body: body,
    );
  }
}

class DesktopWebview {
  static Future<bool> isAvailable() => WebviewWindow.isWebviewAvailable();

  final String initialUrl;

  final void Function(String title, DesktopWebview controller)? onTitleChange;

  final void Function(String url, DesktopWebview webview)? onNavigation;

  final void Function(DesktopWebview controller)? onStarted;

  final void Function()? onClose;

  DesktopWebview({
    required this.initialUrl,
    this.onTitleChange,
    this.onNavigation,
    this.onStarted,
    this.onClose,
  });

  Webview? _webview;

  String? _ua;

  String? title;

  bool _collecting = false;

  void onMessage(String message) {
    dynamic json;
    try {
      json = jsonDecode(_removeCode0(message));
    } on FormatException {
      // 导航期间可能返回空结果，等待下次轮询。
      return;
    }
    if (json is Map) {
      if (json["id"] == "document_created" && json['data'] is Map) {
        title = _removeCode0(json["data"]["title"]?.toString() ?? '');
        _ua = _removeCode0(json["data"]["ua"]?.toString() ?? '');
        onTitleChange?.call(title!, this);
      }
    }
  }

  String? get userAgent => _ua;

  Timer? timer;

  void _runTimer() {
    timer ??= Timer.periodic(const Duration(seconds: 2), (t) async {
      const js = '''
        function collect() {
          if(document.readyState === 'loading') {
            return '';
          }
          let data = {
            id: "document_created",
            data: {
              title: document.title,
              url: location.href,
              ua: navigator.userAgent
            }
          };
          return data;
        }
        collect();
      ''';
      final view = _webview;
      if (view == null || _collecting) return;
      _collecting = true;
      try {
        final message = await view.evaluateJavaScript(js);
        if (identical(view, _webview) && message != null) {
          onMessage(message);
        }
      } catch (error) {
        if (identical(view, _webview)) {
          Log.d('WebView 页面正在导航，稍后重试状态读取：$error');
        }
      } finally {
        _collecting = false;
      }
    });
  }

  void open() async {
    _webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        useWindowPositionAndSize: true,
        userDataFolderWindows: "${App.dataPath}\\webview",
        title: "webview",
        proxy: proxyHttpOverrides?.proxyStr,
      ),
    );
    _webview!.addOnWebMessageReceivedCallback(onMessage);
    _webview!.setOnNavigation((s) => onNavigation?.call(s, this));
    _webview!.launch(initialUrl, triggerOnUrlRequestEvent: false);
    _runTimer();
    _webview!.onClose.then((value) {
      _webview = null;
      timer?.cancel();
      timer = null;
      onClose?.call();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      onStarted?.call(this);
    });
  }

  Future<String?> evaluateJavascript(String source) {
    return _webview!.evaluateJavaScript(source);
  }

  Future<Map<String, String>> getCookies(String url) async {
    var allCookies = await _webview!.getAllCookies();
    var res = <String, String>{};
    for (var c in allCookies) {
      if (_cookieMatch(url, c.domain)) {
        res[_removeCode0(c.name)] = _removeCode0(c.value);
      }
    }
    return res;
  }

  /// 获取指定站点 Cookie 及其属性，供网络层保持有效期和作用域。
  Future<List<Map<String, dynamic>>> getCookieDetails(String url) async {
    final cookies = await _webview!.getAllCookies();
    return cookies
        .where((cookie) => _cookieMatch(url, cookie.domain))
        .map(
          (cookie) => <String, dynamic>{
            'name': _removeCode0(cookie.name),
            'value': _removeCode0(cookie.value),
            'domain': _removeCode0(cookie.domain),
            'path': _removeCode0(cookie.path),
            'expires': cookie.expires,
            'secure': cookie.secure,
            'httpOnly': cookie.httpOnly,
            'sessionOnly': cookie.sessionOnly,
          },
        )
        .toList();
  }

  String _removeCode0(String s) {
    var codeUints = List<int>.from(s.codeUnits);
    codeUints.removeWhere((e) => e == 0);
    return String.fromCharCodes(codeUints);
  }

  bool _cookieMatch(String url, String domain) {
    domain = _removeCode0(domain);
    var host = Uri.parse(url).host;
    var acceptedHost = _getAcceptedDomains(host);
    return acceptedHost.contains(domain.removeAllBlank);
  }

  List<String> _getAcceptedDomains(String host) {
    var acceptedDomains = <String>[host];
    var hostParts = host.split(".");
    for (var i = 0; i < hostParts.length - 1; i++) {
      acceptedDomains.add(".${hostParts.sublist(i).join(".")}");
    }
    return acceptedDomains;
  }

  void close() {
    timer?.cancel();
    timer = null;
    _webview?.close();
    _webview = null;
  }
}

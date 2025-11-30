
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

import '../foundation/log.dart';

/// 表名常量
const String kTableCookies = 'cookies';

/// 字段名常量
const String kCookieName = 'name';
const String kCookieValue = 'value';
const String kCookieDomain = 'domain';
const String kCookiePath = 'path';
const String kCookieExpires = 'expires';
const String kCookieSecure = 'secure';
const String kCookieHttpOnly = 'httpOnly';

class CookieJarSql {
  Database? _db;
  bool _initialized = false;
  final Completer<Database> _initCompleter = Completer<Database>();
  final Lock _lock = Lock();

  final String path;

  CookieJarSql(this.path) {
    init();
  }

  Future<void> init() async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;

      // 确保目录存在
      final dir = Directory(path).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS $kTableCookies (
                  $kCookieName TEXT NOT NULL,
                  $kCookieValue TEXT NOT NULL,
                  $kCookieDomain TEXT NOT NULL,
                  $kCookiePath TEXT,
                  $kCookieExpires INTEGER,
                  $kCookieSecure INTEGER,
                  $kCookieHttpOnly INTEGER,
                  PRIMARY KEY ($kCookieName, $kCookieDomain, $kCookiePath)
                );
              ''');
            },
          ));

      _initialized = true;
      _initCompleter.complete(_db);
    });
  }

  /// 确保数据库已初始化并返回数据库实例
  Future<Database> _getDatabase() {
    final db = _db;
    if (db != null) {
      return SynchronousFuture(db);
    }
    return _initCompleter.future;
  }

  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    for (var cookie in cookies) {
      Log.d(() => "CookieJarSql: save cookie ${cookie.name}, ${cookie.value}, domain: ${cookie.domain}");
      await _saveCookie(uri, cookie);
    }
  }

  Future<void> _saveCookie(Uri uri, Cookie cookie) async {
    final db = await _getDatabase();
    
    await db.insert(
      kTableCookies,
      {
        kCookieName: cookie.name,
        kCookieValue: cookie.value,
        kCookieDomain: cookie.domain ?? uri.host,
        kCookiePath: cookie.path ?? "/",
        kCookieExpires: cookie.expires?.millisecondsSinceEpoch,
        kCookieSecure: cookie.secure ? 1 : 0,
        kCookieHttpOnly: cookie.httpOnly ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Cookie>> _loadWithDomain(String domain) async {
    final db = await _getDatabase();
    
    final rows = await db.query(
      kTableCookies,
      where: '$kCookieDomain = ?',
      whereArgs: [domain],
    );

    return rows.map((row) {
      return Cookie(
        row[kCookieName] as String,
        row[kCookieValue] as String,
      )
        ..domain = row[kCookieDomain] as String
        ..path = row[kCookiePath] as String?
        ..expires = row[kCookieExpires] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row[kCookieExpires] as int)
        ..secure = row[kCookieSecure] == 1
        ..httpOnly = row[kCookieHttpOnly] == 1;
    }).toList();
  }

  List<String> _getAcceptedDomains(String host) {
    var acceptedDomains = <String>[host];
    var hostParts = host.split(".");
    for (var i = 0; i < hostParts.length - 1; i++) {
      acceptedDomains.add(".${hostParts.sublist(i).join(".")}");
    }
    return acceptedDomains;
  }

  Future<List<Cookie>> loadForRequest(Uri uri) async {
    // if uri.host is example.example.com, acceptedDomains will be [".example.example.com", ".example.com", "example.com"]
    var acceptedDomains = _getAcceptedDomains(uri.host);

    var cookies = <Cookie>[];
    for (var domain in acceptedDomains) {
      cookies.addAll(await _loadWithDomain(domain));
    }
    Log.d(() => "CookieJarSql: load cookies for request $uri, acceptedDomains: $acceptedDomains, cookies: $cookies");

    // check expires
    var now = DateTime.now();
    var expiredCookies = cookies.where((cookie) =>
        cookie.expires != null && cookie.expires!.isBefore(now)).toList();
        
    // 删除过期的 cookies
    for (var cookie in expiredCookies) {
      await _deleteCookie(cookie.name, cookie.domain!, cookie.path ?? "/");
    }

    return cookies
        .where((element) =>
            !expiredCookies.contains(element) && _checkPathMatch(uri, element.path))
        .toList();
  }

  bool _checkPathMatch(Uri uri, String? cookiePath) {
    if (cookiePath == null) {
      return true;
    }

    if (cookiePath == uri.path) {
      return true;
    }

    if (cookiePath == "/") {
      return true;
    }

    if (cookiePath.endsWith("/")) {
      return uri.path.startsWith(cookiePath);
    }

    return uri.path.startsWith(cookiePath);
  }

  Future<void> saveFromResponseCookieHeader(Uri uri, List<String> cookieHeader) async {
    var cookies = cookieHeader
        .map((header) => Cookie.fromSetCookieValue(header))
        .toList();
    await saveFromResponse(uri, cookies);
  }

  Future<String> loadForRequestCookieHeader(Uri uri) async {
    var cookies = await loadForRequest(uri);
    var map = <String, Cookie>{};
    for (var cookie in cookies) {
      if (map.containsKey(cookie.name)) {
        if (cookie.domain![0] != '.' && map[cookie.name]!.domain![0] == '.') {
          map[cookie.name] = cookie;
        } else if (cookie.domain!.length > map[cookie.name]!.domain!.length) {
          map[cookie.name] = cookie;
        }
      } else {
        map[cookie.name] = cookie;
      }
    }
    return map.entries
        .map((cookie) => "${cookie.value.name}=${cookie.value.value}")
        .join("; ");
  }

  Future<void> _deleteCookie(String name, String domain, String path) async {
    final db = await _getDatabase();
    await db.delete(
      kTableCookies,
      where: '$kCookieName = ? AND $kCookieDomain = ? AND $kCookiePath = ?',
      whereArgs: [name, domain, path],
    );
  }

  Future<void> delete(Uri uri, String name) async {
    var acceptedDomains = _getAcceptedDomains(uri.host);
    for (var domain in acceptedDomains) {
      await _deleteCookie(name, domain, uri.path);
    }
  }

  Future<void> deleteUri(Uri uri) async {
    var acceptedDomains = _getAcceptedDomains(uri.host);
    final db = await _getDatabase();
    
    for (var domain in acceptedDomains) {
      await db.delete(
        kTableCookies,
        where: '$kCookieDomain = ?',
        whereArgs: [domain],
      );
    }
  }

  Future<void> deleteAll() async {
    final db = await _getDatabase();
    await db.delete(kTableCookies);
  }

  Future<void> dispose() async {
    if (_db != null && _initialized) {
      await _db!.close();
      _db = null;
      _initialized = false;
    }
  }
}

class SingleInstanceCookieJar extends CookieJarSql {
  factory SingleInstanceCookieJar(String path) =>
      instance ??= SingleInstanceCookieJar._create(path);

  SingleInstanceCookieJar._create(super.path);

  static SingleInstanceCookieJar? instance;
}

class CookieManagerSql extends Interceptor {
  final CookieJarSql cookieJar;

  CookieManagerSql(this.cookieJar);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    var cookies = await cookieJar.loadForRequestCookieHeader(options.uri);
    if (cookies.isNotEmpty) {
      options.headers["cookie"] = cookies;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    cookieJar.saveFromResponseCookieHeader(
        response.requestOptions.uri, response.headers["set-cookie"] ?? []);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err);
  }
}
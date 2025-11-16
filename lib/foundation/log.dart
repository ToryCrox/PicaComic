import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/throttle.dart';

import 'advanced_file_output.dart';
import 'app.dart';
import 'logger_pretty_printer.dart';

void log(String content,
    [String title = "debug", LogLevel level = LogLevel.info]) {
  // 已弃用，使用 Log.d, Log.i, Log.w, Log.e 替代
  switch (level) {
    case LogLevel.debug:
      Log.d('$title $content');
      break;
    case LogLevel.info:
      Log.i('$title $content');
      break;
    case LogLevel.warning:
      Log.w('$title $content');
      break;
    case LogLevel.error:
      Log.e('$title $content');
      break;
  }
}

final excludePaths = [
  'package:pica_comic/foundation/log.dart',
];
final excludeMethods = <String>[];
final logMemoryOut = MemoryOutput(
  bufferSize: 500,
);
final logger = Logger(
  level: kReleaseMode ? Level.info : Level.trace,
  output: MultiOutput([
    ConsoleOutput(),
    MAdvancedFileOutput(
      path: '${App.dataPath}/logger.txt',
      overrideExisting: true,
      level: Level.info,
    ),
    logMemoryOut,
  ]),
  printer: LoggerPrettyPrinter(
      methodCount: 1,
      printEmojis: false,
      lineLength: 160,
      printTime: true,
      colors: !Platform.isIOS,
      excludePaths: [],
      excludeFilter: (method, segment) {
        if (excludeMethods.contains(method)) {
          return true;
        }

        /// segment: package:app/src/log/log.dart:96:15
        if (excludePaths.any((e) => segment.contains(e))) {
          return true;
        }
        return false;
      }),
);

class LogManager {
  static final List<Log> _logs = <Log>[];

  static List<Log> get logs => _logs;

  static const maxLogLength = 3000;

  static const maxLogNumber = 500;

  static bool ignoreLimitation = false;

  static void printWarning(String text) {
    print('\x1B[33m$text\x1B[0m');
  }

  static void printError(String text) {
    print('\x1B[31m$text\x1B[0m');
  }

  static void addLog(LogLevel level, String title, String content,
      {StackTrace? stackTrace}) {
    // if (!ignoreLimitation && content.length > maxLogLength) {
    //   content = "${content.substring(0, maxLogLength)}...";
    // }
    //
    // if (kDebugMode) {
    //   switch (level) {
    //     case LogLevel.error:
    //       //printError("$title: $content");
    //       logger.e('$title: $content', stackTrace: stackTrace);
    //       break;
    //     case LogLevel.warning:
    //       logger.w("$title: $content");
    //       break;
    //     case LogLevel.info:
    //       logger.i("$title: $content");
    //       break;
    //     case LogLevel.debug:
    //       logger.d("$title: $content");
    //       break;
    //   }
    // }
    //
    // var newLog = Log(level, title, content);
    //
    // if (newLog == _logs.lastOrNull) {
    //   return;
    // }
    // if (level == LogLevel.debug) {
    //   return;
    // }
    //
    // _logs.add(newLog);
    // writeLog(level, title, content);
    // if (_logs.length > maxLogNumber) {
    //   var res = _logs.remove(
    //       _logs.firstWhereOrNull((element) => element.level == LogLevel.info));
    //   if (!res) {
    //     _logs.removeAt(0);
    //   }
    // }
  }

  static void clear() => _logs.clear();

  @override
  String toString() {
    var res = "Logs\n\n";
    for (var log in _logs) {
      res += log.toString();
    }
    return res;
  }

  static void init() async {
    File? logFile = File("${App.dataPath}/log.txt");
    if (App.isAndroid) {
      var externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        logFile = File("${externalDirectory.path}/log.txt");
      }
    }
    if (App.isIOS) {
      logFile = null;
    }
    if (logFile?.existsSync() ?? false) {
      await logFile?.delete();
    }
    print("Log file: ${logFile?.path}");
    _logFile = logFile;
  }

  static File? _logFile;
  static IOSink? _logSink;

  static bool _isWriting = false;

  static void writeLog(LogLevel level, String title, String content) {
    IOSink? logSink = _logSink ??= _logFile?.openWrite(mode: FileMode.append);
    if (logSink == null) {
      return;
    }
    logSink.writeln(
        '${DateTime.now().toIso8601String()} ${level.name}\n$title: $content\n');
    // if (!_isWriting) {
    //   /// 延迟1秒写入文件
    //   Future.delayed(const Duration(seconds: 1), () {
    //     logSink.flush();
    //     _isWriting = false;
    //   });
    // }
  }
}

class Log {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time = DateTime.now();

  @override
  toString() => "${level.name} $title $time \n$content\n\n";

  Log(this.level, this.title, this.content);

  /// Log a message at level [Level.debug].
  ///
  /// Corresponds to [Logger.d].
  static void d(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.info].
  ///
  /// Corresponds to [Logger.i].
  static void i(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.warning].
  ///
  /// Corresponds to [Logger.w].
  static void w(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.error].
  ///
  /// Corresponds to [Logger.e].
  static void e(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.e(message, error: error, stackTrace: stackTrace);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Log) return false;
    return other.level == level &&
        other.title == title &&
        other.content == content;
  }

  @override
  int get hashCode => level.hashCode ^ title.hashCode ^ content.hashCode;
}

enum LogLevel { error, warning, info, debug }

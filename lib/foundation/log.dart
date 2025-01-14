import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:pica_comic/tools/extensions.dart';

import 'logger_pretty_printer.dart';

void log(String content,
    [String title = "debug", LogLevel level = LogLevel.info]) {
  LogManager.addLog(level, title, content);
}

final excludePaths = [
  'package:pica_comic/foundation/log.dart',
];
final excludeMethods = <String>[];
final logger = Logger(
  level: Level.trace,
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
      }
  ),
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

  static void addLog(LogLevel level, String title, String content, {StackTrace? stackTrace}) {
    if (!ignoreLimitation && content.length > maxLogLength) {
      content = "${content.substring(0, maxLogLength)}...";
    }

    if (kDebugMode) {
      switch (level) {
        case LogLevel.error:
          //printError("$title: $content");
          logger.e('$title: $content', stackTrace: stackTrace);
          break;
        case LogLevel.warning:
          logger.w("$title: $content");
          break;
        case LogLevel.info:
          logger.i("$title: $content");
          break;
        case LogLevel.debug:
          logger.d("$title: $content");
          break;
      }
    }

    var newLog = Log(level, title, content);

    if (newLog == _logs.lastOrNull) {
      return;
    }
    if (level == LogLevel.debug) {
      return;
    }

    _logs.add(newLog);
    writeLog(level, title, content);
    if (_logs.length > maxLogNumber) {
      var res = _logs.remove(
          _logs.firstWhereOrNull((element) => element.level == LogLevel.info));
      if (!res) {
        _logs.removeAt(0);
      }
    }
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

  static File? logFile;

  static void writeLog(LogLevel level, String title, String content) {
    if(logFile != null) {
      logFile!.writeAsString(
        "${DateTime.now().toIso8601String()} ${level.name}\n$title: $content\n\n",
        mode: FileMode.append,
      );
    }
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

  static void debug(String title, String message) {
    LogManager.addLog(LogLevel.debug, title, message);
  }

  static void info(String title, String message) {
    LogManager.addLog(LogLevel.info, title, message);
  }

  static void warning(String title, String message) {
    LogManager.addLog(LogLevel.warning, title, message);
  }

  static void error(String title, String message, {StackTrace? stackTrace}) {
    LogManager.addLog(LogLevel.error, title, message, stackTrace: stackTrace);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Log)  return false;
    return other.level == level && other.title == title && other.content == content;
  }

  @override
  int get hashCode => level.hashCode ^ title.hashCode ^ content.hashCode;
}

enum LogLevel { error, warning, info, debug }

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';

extension _NumExt on num {
  String toDigits(int digits) => toString().padLeft(digits, '0');
}

/// Accumulates logs in a buffer to reduce frequent disk, writes while optionally
/// switching to a new log file if it reaches a certain size.
///
/// [AdvancedFileOutput] offer various improvements over the original
/// [FileOutput]:
/// * Managing an internal buffer which collects the logs and only writes
/// them after a certain period of time to the disk.
/// * Dynamically switching log files instead of using a single one specified
/// by the user, when the current file reaches a specified size limit (optionally).
///
/// The buffered output can significantly reduce the
/// frequency of file writes, which can be beneficial for (micro-)SD storage
/// and other types of low-cost storage (e.g. on IoT devices). Specific log
/// levels can trigger an immediate flush, without waiting for the next timer
/// tick.
///
/// New log files are created when the current file reaches the specified size
/// limit. This is useful for writing "archives" of telemetry data and logs
/// while keeping them structured.
class MAdvancedFileOutput extends LogOutput {
  /// Creates a buffered file output.
  ///
  /// By default, the log is buffered until either the [maxBufferSize] has been
  /// reached, the timer controlled by [maxDelay] has been triggered or an
  /// [OutputEvent] contains a [writeImmediately] log level.
  ///
  /// [maxFileSizeKB] controls the log file rotation. The output automatically
  /// switches to a new log file as soon as the current file exceeds it.
  /// Use -1 to disable log rotation.
  ///
  /// [maxDelay] describes the maximum amount of time before the buffer has to be
  /// written to the file.
  ///
  /// Any log levels that are specified in [writeImmediately] trigger an immediate
  /// flush to the disk ([Level.warning], [Level.error] and [Level.fatal] by default).
  ///
  /// [path] is either treated as directory for rotating or as target file name,
  /// depending on [maxFileSizeKB].
  ///
  /// [maxRotatedFilesCount] controls the number of rotated files to keep. By default
  /// is null, which means no limit.
  /// If set to a positive number, the output will keep the last
  /// [maxRotatedFilesCount] files. The deletion step will be executed by sorting
  /// files following the [fileSorter] ascending strategy and keeping the last files.
  /// The [latestFileName] will not be counted. The default [fileSorter] strategy is
  /// sorting by last modified date, beware that could be not reliable in some
  /// platforms and/or filesystems.
  ///
  /// [maxTotalSizeKB] 限制 [path] 目录内日志文件的总大小。
  /// 当前写入的 [latestFileName] 会被保留，超过限制时优先删除最旧的轮转日志。
  MAdvancedFileOutput({
    required String path,
    bool overrideExisting = false,
    Encoding encoding = utf8,
    List<Level>? writeImmediately,
    Duration maxDelay = const Duration(seconds: 2),
    int maxBufferSize = 2000,
    int maxFileSizeKB = 1024,
    String latestFileName = 'latest.log',
    String Function(DateTime timestamp)? fileNameFormatter,
    int? maxRotatedFilesCount,
    int? maxTotalSizeKB,
    Comparator<File>? fileSorter,
    Level? level,
  }) : _path = path,
       _level = level,
       _overrideExisting = overrideExisting,
       _encoding = encoding,
       _maxDelay = maxDelay,
       _maxFileSizeKB = maxFileSizeKB,
       _maxBufferSize = maxBufferSize,
       _fileNameFormatter = fileNameFormatter ?? _defaultFileNameFormat,
       _writeImmediately =
           writeImmediately ??
           [
             Level.error,
             Level.fatal,
             Level.warning,
             // ignore: deprecated_member_use_from_same_package
             Level.wtf,
           ],
       _maxRotatedFilesCount = maxRotatedFilesCount,
       _maxTotalSizeKB = maxTotalSizeKB,
       _fileSorter = fileSorter ?? _defaultFileSorter,
       _file = maxFileSizeKB > 0 ? File('$path/$latestFileName') : File(path);

  /// Logs directory path by default, particular log file path if [_maxFileSizeKB] is 0.
  final String _path;
  final Level? _level;

  final bool _overrideExisting;
  final Encoding _encoding;

  final List<Level> _writeImmediately;
  final Duration _maxDelay;
  final int _maxFileSizeKB;
  final int _maxBufferSize;
  final String Function(DateTime timestamp) _fileNameFormatter;
  final int? _maxRotatedFilesCount;
  final int? _maxTotalSizeKB;
  final Comparator<File> _fileSorter;

  final File _file;
  IOSink? _sink;
  Timer? _bufferFlushTimer;
  Timer? _targetFileUpdater;

  final List<OutputEvent> _buffer = [];

  bool get _rotatingFilesMode => _maxFileSizeKB > 0;

  /// Formats the file with a full date string.
  ///
  /// Example:
  /// * `2024-01-01-10-05-02-123.log`
  static String _defaultFileNameFormat(DateTime t) {
    return '${t.year}-${t.month.toDigits(2)}-${t.day.toDigits(2)}'
        '-${t.hour.toDigits(2)}-${t.minute.toDigits(2)}-${t.second.toDigits(2)}'
        '-${t.millisecond.toDigits(3)}.log';
  }

  /// Sort files by their last modified date.
  /// This behaviour is inspired by the Log4j PathSorter.
  ///
  /// This method fulfills the requirements of the [Comparator] interface.
  static int _defaultFileSorter(File a, File b) {
    return a.lastModifiedSync().compareTo(b.lastModifiedSync());
  }

  @override
  Future<void> init() async {
    if (_rotatingFilesMode) {
      final dir = Directory(_path);
      // We use sync directory check to avoid losing potential initial boot logs
      // in early crash scenarios.
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _targetFileUpdater = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _updateTargetFile(),
      );
    }

    _bufferFlushTimer = Timer.periodic(_maxDelay, (_) => _flushBuffer());
    await _openSink();
    if (_rotatingFilesMode) {
      await _updateTargetFile(); // Run first check without waiting for timer tick
      await _deleteRotatedFiles();
    }
  }

  @override
  void output(OutputEvent event) {
    final level = _level;
    if (level != null && event.level.index < level.index) {
      return;
    }
    _buffer.add(event);
    // If event level is present in writeImmediately, flush the complete buffer
    // along with any other possible elements that accumulated since
    // the last timer tick. Additionally, if the buffer is full.
    if (_buffer.length > _maxBufferSize ||
        _writeImmediately.contains(event.level)) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    if (_sink == null) return; // Wait until _sink becomes available
    for (final event in _buffer) {
      final List<String> lines = event.lines;
      _sink?.writeAll(lines, Platform.isWindows ? '\r\n' : '\n');
      _sink?.writeln();
    }
    _buffer.clear();
  }

  Future<void> _updateTargetFile() async {
    try {
      if (await _file.exists() &&
          await _file.length() > _maxFileSizeKB * 1024) {
        // Rotate the log file
        await _closeSink();
        await _file.rename('$_path/${_fileNameFormatter(DateTime.now())}');
        await _deleteRotatedFiles();
        await _openSink();
      }
    } catch (e, s) {
      print(e);
      print(s);
      // Try creating another file and working with it
      await _closeSink();
      await _openSink();
    }
  }

  Future<void> _openSink() async {
    _sink = _file.openWrite(
      mode: _overrideExisting ? FileMode.writeOnly : FileMode.writeOnlyAppend,
      encoding: _encoding,
    );
  }

  Future<void> _closeSink() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null; // Explicitly set null until assigned again
  }

  Future<void> _deleteRotatedFiles() async {
    final dir = Directory(_path);
    if (!dir.existsSync()) {
      return;
    }

    final files = _listRotatedLogFiles(dir);
    files.sort(_fileSorter);

    final maxRotatedFilesCount = _maxRotatedFilesCount;
    if (maxRotatedFilesCount != null && files.length > maxRotatedFilesCount) {
      final filesToDelete = files.sublist(
        0,
        files.length - maxRotatedFilesCount,
      );
      for (final file in filesToDelete) {
        await _deleteFile(file);
      }
    }

    final maxTotalSizeKB = _maxTotalSizeKB;
    if (maxTotalSizeKB == null || maxTotalSizeKB <= 0) {
      return;
    }

    final maxTotalSizeBytes = maxTotalSizeKB * 1024;
    var totalSize = _getLogFilesTotalSize(dir);
    final rotatedFiles = _listRotatedLogFiles(dir)..sort(_fileSorter);
    for (final file in rotatedFiles) {
      if (totalSize <= maxTotalSizeBytes) {
        break;
      }

      final fileSize = await _getFileLength(file);
      await _deleteFile(file);
      totalSize -= fileSize;
    }
  }

  List<File> _listRotatedLogFiles(Directory dir) {
    return dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path != _file.path)
        .where((file) => file.path.endsWith('.log'))
        .toList();
  }

  int _getLogFilesTotalSize(Directory dir) {
    var totalSize = 0;
    final files = dir.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.log'),
    );
    for (final file in files) {
      totalSize += _getFileLengthSync(file);
    }
    return totalSize;
  }

  int _getFileLengthSync(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  Future<int> _getFileLength(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      // 忽略文件状态读取失败，下一次轮转时会重新计算。
      return 0;
    }
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // 忽略删除失败，避免日志清理影响正常写入。
    }
  }

  @override
  Future<void> destroy() async {
    _bufferFlushTimer?.cancel();
    _targetFileUpdater?.cancel();
    try {
      _flushBuffer();
    } catch (e, s) {
      print('Failed to flush buffer before closing the logger: $e');
      print(s);
    }
    await _closeSink();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/io_extensions.dart';
import 'package:pica_comic/tools/type_util.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';

/// 缓存记录数据类
class CacheRecord {
  final String key;
  final String dir;
  final String name;
  final int expires;
  final String? type;

  String get filePath => path.join(CacheManager.cachePath, dir, name);

  File get file => File(filePath);

  CacheRecord({
    required this.key,
    required this.dir,
    required this.name,
    required this.expires,
    this.type,
  });

  /// 从数据库查询结果创建CacheRecord对象
  factory CacheRecord.fromMap(Map<String, dynamic> map) {
    return CacheRecord(
      key: TypeUtil.parseString(map[CacheManager.columnKey]),
      dir: TypeUtil.parseString(map[CacheManager.columnDir]),
      name: TypeUtil.parseString(map[CacheManager.columnName]),
      expires: TypeUtil.parseInt(map[CacheManager.columnExpires]),
      type: TypeUtil.parseString(map[CacheManager.columnType]),
    );
  }

  /// 转换为数据库插入用的Map
  Map<String, dynamic> toMap() {
    return {
      CacheManager.columnKey: key,
      CacheManager.columnDir: dir,
      CacheManager.columnName: name,
      CacheManager.columnExpires: expires,
      CacheManager.columnType: type,
    };
  }
}

class CacheManager {
  static String get cachePath => '${App.cachePath}/cache';

  static CacheManager? instance;

  Database? _db;
  final _lock = Lock(); // 用于确保数据库初始化的锁
  bool _initialized = false;

  int? _currentSize;

  /// size in bytes
  int get currentSize => _currentSize ?? 0;

  int dir = 0;

  int _limitSize = 2 * 1024 * 1024 * 1024;

  int get limitSize => _limitSize;

  // 数据库版本号
  static const int _databaseVersion = 1;
  static const String _databaseName = 'cache.db';
  
  // 表名和字段名常量
  static const String tableCache = 'cache';
  static const String columnKey = 'key';
  static const String columnDir = 'dir';
  static const String columnName = 'name';
  static const String columnExpires = 'expires';
  static const String columnType = 'type';

  CacheManager._create(){
    Directory(cachePath).createSync(recursive: true);
    // 初始化 sqflite_common_ffi
    databaseFactory = databaseFactoryFfi;
  }

  /// 确保数据库已初始化
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _lock.synchronized(() async {
      if (_initialized) return;
      await _initDatabase();
    });
  }

  Future<void> _initDatabase() async {
    final databasesPath = App.dataPath;
    final path = '$databasesPath/$_databaseName';
    Log.debug('CacheManager', "Cache database path: $path");
    
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    
    _initialized = true;
    
    compute((path) => Directory(path).size, cachePath)
        .then((value) => _currentSize = value);
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 使用 IF NOT EXISTS 避免表已存在时出错
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableCache (
        $columnKey TEXT PRIMARY KEY NOT NULL,
        $columnDir TEXT NOT NULL,
        $columnName TEXT NOT NULL,
        $columnExpires INTEGER NOT NULL,
        $columnType TEXT
      )
    ''');
  }

  /// 升级数据库表
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    
    // 可以在这里添加更多版本升级逻辑
    // 示例：
    // if (oldVersion < 2) {
    //   // 在版本2中的更改
    //   await db.execute('ALTER TABLE $tableCache ADD COLUMN new_field TEXT');
    // }
  }

  factory CacheManager() => instance ??= CacheManager._create();

  /// set cache size limit in MB
  void setLimitSize(int size){
    _limitSize = size * 1024 * 1024;
  }

  void setType(String key, String? type) async {
    await _ensureInitialized();
    await _db!.update(
      tableCache,
      {columnType: type},
      where: '$columnKey = ?',
      whereArgs: [key],
    );
  }

  Future<String?> getType(String key) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      columns: [columnType],
      where: '$columnKey = ?',
      whereArgs: [key],
    );
    if(res.isEmpty){
      return null;
    }
    return TypeUtil.parseString(res.first[columnType]);
  }

  Future<void> writeCache(String key, Uint8List data, [int duration = 7 * 24 * 60 * 60 * 1000]) async{
    await _ensureInitialized();
    this.dir++;
    this.dir %= 100;
    var dir = this.dir;
    var name = md5.convert(Uint8List.fromList(key.codeUnits)).toString();
    var file = File('$cachePath/$dir/$name');
    // while(await file.exists()){
    //   name = md5.convert(Uint8List.fromList(name.codeUnits)).toString();
    //   file = File('$cachePath/$dir/$name');
    // }
    await file.create(recursive: true);
    await file.writeAsBytes(data);
    var expires = DateTime.now().millisecondsSinceEpoch + duration;
    
    await _db!.insert(
      tableCache,
      {
        columnKey: key,
        columnDir: dir.toString(),
        columnName: name,
        columnExpires: expires,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    if(_currentSize != null) {
      _currentSize = _currentSize! + data.length;
    }
    if(_currentSize != null && _currentSize! > _limitSize){
      await checkCache();
    }
  }

  Future<CachingFile> openWrite(String key) async{
    await _ensureInitialized();
    this.dir++;
    this.dir %= 100;
    var dir = this.dir;
    var name = md5.convert(Uint8List.fromList(key.codeUnits)).toString();
    var file = File('$cachePath/$dir/$name');
    // while(await file.exists()){
    //   name = md5.convert(Uint8List.fromList(name.codeUnits)).toString();
    //   file = File('$cachePath/$dir/$name');
    // }
    await file.create(recursive: true);
    return CachingFile._(key, dir.toString(), name, file);
  }


  Future<void> writeString(String key, String data) async {
    try {
      Log.debug('CacheManager', 'writeString $key');
      final bytes = Uint8List.fromList(utf8.encode(data));
      await writeCache(key, bytes, const Duration(days: 180).inMilliseconds);
    } catch (e) {
      Log.error('CacheManager', 'writeString error: $e');
    }
  }

  Future<T?> findCacheModel<T>(String key, T Function(Map<String, dynamic> map) factory) async{
    await _ensureInitialized();
    final cache = await findCache(key);
    final filePath = cache?.filePath;
    Log.debug('CacheManager', 'findCacheModel $key, $filePath');
    if (filePath != null) {
      final file = File(filePath);
      Log.debug('CacheManager', 'findCache $key, $filePath');
      if (file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          final dataStr = utf8.decode(bytes);
          Log.debug('CacheManager', dataStr);
          final map = TypeUtil.parseMap(dataStr);
          if (map.isNotEmpty) {
            return factory(map);
          }
        } catch (e) {
          Log.error('CacheManager', 'read cache error: $e');
        }
      }
    }
    return null;
  }


  Future<CacheRecord?> findCache(String key) async {
    await _ensureInitialized();
    final record = await _findRecord(key);
    if(record == null){
      return null;
    }
    var file = record.file;
    if(await file.exists()){
      return record;
    }
    return null;
  }

  /// 查找缓存记录
  Future<CacheRecord?> _findRecord(String key) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      where: '$columnKey = ?',
      whereArgs: [key],
    );
    if(res.isEmpty){
      return null;
    }
    return CacheRecord.fromMap(res.first);
  }

  bool _isChecking = false;

  Future<void> checkCache() async{
    await _ensureInitialized();
    if(_isChecking){
      return;
    }
    _isChecking = true;
    
    var now = DateTime.now().millisecondsSinceEpoch;
    var records = await getAllExpiredRecords(now);
    
    for(var record in records){
      var file = File('$cachePath/${record.dir}/${record.name}');
      if(await file.exists()){
        await file.delete();
      }
    }
    
    await deleteExpiredRecords(now);

    int count = await getRecordCount();

    compute((path) => Directory(path).size, cachePath)
        .then((value) => _currentSize = value);

    while((_currentSize != null && _currentSize! > _limitSize) ||  count > 200000){
      var records = await getOldestRecords(10);
      
      for(var record in records){
        var file = File('$cachePath/${record.dir}/${record.name}');
        if(await file.exists()){
          var size = await file.length();
          await file.delete();
          await deleteRecord(record.key);
          _currentSize = _currentSize! - size;
          if(_currentSize! <= _limitSize){
            break;
          }
        } else {
          await deleteRecord(record.key);
        }
        count--;
      }
    }
    _isChecking = false;
  }

  /// 获取所有过期的记录
  Future<List<CacheRecord>> getAllExpiredRecords(int timestamp) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      where: '$columnExpires < ?',
      whereArgs: [timestamp],
    );
    
    return res.map((row) => CacheRecord.fromMap(row)).toList();
  }

  /// 删除过期记录
  Future<void> deleteExpiredRecords(int timestamp) async {
    await _ensureInitialized();
    await _db!.delete(
      tableCache,
      where: '$columnExpires < ?',
      whereArgs: [timestamp],
    );
  }

  /// 获取记录总数
  Future<int> getRecordCount() async {
    await _ensureInitialized();
    var res = await _db!.rawQuery('''
      SELECT COUNT(*) FROM $tableCache
    ''');
    if(res.isNotEmpty){
      return TypeUtil.parseInt(res.first.values.first);
    }
    return 0;
  }

  /// 获取最旧的记录
  Future<List<CacheRecord>> getOldestRecords(int limit) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      orderBy: '$columnExpires ASC',
      limit: limit,
    );
    
    return res.map((row) => CacheRecord.fromMap(row)).toList();
  }

  /// 删除记录
  Future<void> deleteRecord(String key) async {
    await _ensureInitialized();
    await _db!.delete(
      tableCache,
      where: '$columnKey = ?',
      whereArgs: [key],
    );
  }

  Future<void> delete(String key) async{
    await _ensureInitialized();
    final record = await _findRecord(key);
    if(record == null){
      return;
    }
    
    var file = File('$cachePath/${record.dir}/${record.name}');
    var fileSize = 0;
    if(await file.exists()){
      fileSize = await file.length();
      await file.delete();
    }
    Log.debug('CacheManager', 'delete $key, filePath: ${file.path}, size: $fileSize');
    await deleteRecord(key);
    if(_currentSize != null) {
      _currentSize = _currentSize! - fileSize;
    }
  }

  Future<void> clear() async {
    await _ensureInitialized();
    await Directory(cachePath).delete(recursive: true);
    Directory(cachePath).createSync(recursive: true);
    await _db!.delete(tableCache);
    _currentSize = 0;
  }

  Future<void> deleteKeyword(String keyword) async{
    await _ensureInitialized();
    var records = await getRecordsByKeyPattern('%$keyword%');
    
    for(var record in records){
      var file = File('$cachePath/${record.dir}/${record.name}');
      var fileSize = 0;
      if(await file.exists()){
        fileSize = await file.length();
        try {
          await file.delete();
        }
        finally {}
      }
      await deleteRecord(record.key);
      if(_currentSize != null) {
        _currentSize = _currentSize! - fileSize;
      }
    }
  }

  /// 根据关键字模式获取记录
  Future<List<CacheRecord>> getRecordsByKeyPattern(String pattern) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      where: '$columnKey LIKE ?',
      whereArgs: [pattern],
    );
    
    return res.map((row) => CacheRecord.fromMap(row)).toList();
  }

  Future<void> deleteByType(String type) async {
    await _ensureInitialized();
    var records = await getRecordsByType(type);
    
    for(var record in records){
      var file = File('$cachePath/${record.dir}/${record.name}');
      var fileSize = 0;
      if(await file.exists()){
        fileSize = await file.length();
        try {
          await file.delete();
        } catch (e) {
          continue;
        }
      }
      await deleteRecord(record.key);
      if(_currentSize != null) {
        _currentSize = _currentSize! - fileSize;
      }
    }
  }

  /// 根据类型获取记录
  Future<List<CacheRecord>> getRecordsByType(String type) async {
    await _ensureInitialized();
    var res = await _db!.query(
      tableCache,
      where: '$columnType = ?',
      whereArgs: [type],
    );
    
    return res.map((row) => CacheRecord.fromMap(row)).toList();
  }
  
  /// 插入或更新记录（供CachingFile使用）
  Future<void> insertRecord(CacheRecord record) async {
    await _ensureInitialized();
    await _db!.insert(
      tableCache,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class CachingFile{
  CachingFile._(this.key, this.dir, this.name, this.file);

  final String key;

  final String dir;

  final String name;

  final File file;

  final List<int> _buffer = [];

  String? fileType;

  Future<void> writeBytes(List<int> data) async{
    _buffer.addAll(data);
    if(_buffer.length > 1024 * 1024){
      await file.writeAsBytes(_buffer, mode: FileMode.append);
      _buffer.clear();
    }
  }

  Future<void> close() async{
    if(_buffer.isNotEmpty){
      await file.writeAsBytes(_buffer, mode: FileMode.append);
    }
    
    final expires = DateTime.now().millisecondsSinceEpoch + 7 * 24 * 60 * 60 * 1000;
    final record = CacheRecord(
      key: key,
      dir: dir,
      name: name,
      expires: expires,
      type: fileType,
    );
    
    final cacheManager = CacheManager();
    await cacheManager.insertRecord(record);
    await cacheManager.checkCache();
  }

  Future<void> cancel() async{
    await file.deleteIgnoreError();
  }

  void reset() {
    _buffer.clear();
    if(file.existsSync()) {
      file.deleteSync();
    }
  }
}
import 'dart:convert';
import 'dart:io';

import 'package:pica_comic/tools/prefs_helper.dart';

/// 存储库信息
class RepositoryInfo {
  /// 存储库名称（唯一标识符，不可更改）
  final String name;

  /// 存储库路径
  final String path;

  /// 存储库标题（可更改，用于显示）
  String title;

  RepositoryInfo({required this.name, required this.path, String? title})
    : title = title ?? name;

  Map<String, dynamic> toMap() => {'name': name, 'path': path, 'title': title};

  factory RepositoryInfo.fromMap(Map<String, dynamic> map) {
    return RepositoryInfo(
      name: map['name'] as String,
      path: map['path'] as String,
      title: map['title'] as String?,
    );
  }
}

/// 本地漫画存储库管理器
class LocalRepositoryManager {
  static LocalRepositoryManager? _instance;

  factory LocalRepositoryManager() =>
      _instance ??= LocalRepositoryManager._internal();

  LocalRepositoryManager._internal() {
    _loadRepositories();
  }

  static const String _prefsKey = 'local_comic_repositories';

  /// 缓存的存储库列表
  List<RepositoryInfo> _repositories = [];

  /// 加载存储库列表（同步方法）
  void _loadRepositories() {
    final jsonStr = PrefsHelper.getString(_prefsKey, '[]');
    try {
      final list = jsonDecode(jsonStr) as List;
      _repositories = list
          .map((item) => RepositoryInfo.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _repositories = [];
    }
  }

  /// 获取所有存储库（同步方法）
  List<RepositoryInfo> getAllRepositoriesSync() {
    return List.unmodifiable(_repositories);
  }

  /// 获取所有存储库（异步方法，保持向后兼容）
  Future<List<RepositoryInfo>> getAllRepositories() async {
    return getAllRepositoriesSync();
  }

  /// 添加存储库
  Future<bool> addRepository(String name, String path) async {
    // 验证路径是否存在
    final dir = Directory(path);
    if (!await dir.exists()) {
      return false;
    }

    // 检查名称是否已存在
    if (_repositories.any((r) => r.name == name)) {
      return false;
    }

    _repositories.add(RepositoryInfo(name: name, path: path));
    await _saveRepositories(_repositories);
    return true;
  }

  /// 删除存储库
  Future<bool> removeRepository(String name) async {
    _repositories.removeWhere((r) => r.name == name);
    await _saveRepositories(_repositories);
    return true;
  }

  /// 更新存储库（只能更新路径和标题，不能更改名称）
  Future<bool> updateRepository(
    String name,
    String newPath,
    String? newTitle,
  ) async {
    // 验证路径是否存在
    final dir = Directory(newPath);
    if (!await dir.exists()) {
      return false;
    }

    final index = _repositories.indexWhere((r) => r.name == name);
    if (index == -1) {
      return false;
    }

    // 更新路径和标题，名称保持不变
    final repo = _repositories[index];
    _repositories[index] = RepositoryInfo(
      name: repo.name,
      path: newPath,
      title: newTitle ?? repo.title,
    );
    await _saveRepositories(_repositories);
    return true;
  }

  /// 更新存储库标题
  Future<bool> updateRepositoryTitle(String name, String newTitle) async {
    final index = _repositories.indexWhere((r) => r.name == name);
    if (index == -1) {
      return false;
    }

    final repo = _repositories[index];
    _repositories[index] = RepositoryInfo(
      name: repo.name,
      path: repo.path,
      title: newTitle,
    );
    await _saveRepositories(_repositories);
    return true;
  }

  /// 根据名称获取存储库路径（同步方法）
  String? getRepositoryPathSync(String name) {
    try {
      final repo = _repositories.firstWhere((r) => r.name == name);
      return repo.path;
    } catch (e) {
      return null;
    }
  }

  /// 根据名称获取存储库路径（异步方法，保持向后兼容）
  Future<String?> getRepositoryPath(String name) async {
    return getRepositoryPathSync(name);
  }

  /// 保存存储库列表
  Future<void> _saveRepositories(List<RepositoryInfo> repositories) async {
    final maps = repositories.map((r) => r.toMap()).toList();
    final jsonStr = jsonEncode(maps);
    await PrefsHelper.setString(_prefsKey, jsonStr);
    // 更新缓存
    _repositories = repositories;
  }
}

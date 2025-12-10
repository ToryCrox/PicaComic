import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:pica_comic/tools/prefs_helper.dart';

/// 存储库信息
class RepositoryInfo {
  final String name;
  final String path;

  RepositoryInfo({required this.name, required this.path});

  Map<String, String> toMap() => {
        'name': name,
        'path': path,
      };

  factory RepositoryInfo.fromMap(Map<String, dynamic> map) {
    return RepositoryInfo(
      name: map['name'] as String,
      path: map['path'] as String,
    );
  }
}

/// 本地漫画存储库管理器
class LocalRepositoryManager {
  static LocalRepositoryManager? _instance;

  factory LocalRepositoryManager() =>
      _instance ??= LocalRepositoryManager._internal();

  LocalRepositoryManager._internal();

  static const String _prefsKey = 'local_comic_repositories';

  /// 获取所有存储库
  Future<List<RepositoryInfo>> getAllRepositories() async {
    final jsonStr = PrefsHelper.getString(_prefsKey, '[]');
    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((item) => RepositoryInfo.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 添加存储库
  Future<bool> addRepository(String name, String path) async {
    // 验证路径是否存在
    final dir = Directory(path);
    if (!await dir.exists()) {
      return false;
    }

    final repositories = await getAllRepositories();
    // 检查名称是否已存在
    if (repositories.any((r) => r.name == name)) {
      return false;
    }

    repositories.add(RepositoryInfo(name: name, path: path));
    await _saveRepositories(repositories);
    return true;
  }

  /// 删除存储库
  Future<bool> removeRepository(String name) async {
    final repositories = await getAllRepositories();
    repositories.removeWhere((r) => r.name == name);
    await _saveRepositories(repositories);
    return true;
  }

  /// 更新存储库
  Future<bool> updateRepository(
    String oldName,
    String newName,
    String newPath,
  ) async {
    // 验证路径是否存在
    final dir = Directory(newPath);
    if (!await dir.exists()) {
      return false;
    }

    final repositories = await getAllRepositories();
    final index = repositories.indexWhere((r) => r.name == oldName);
    if (index == -1) {
      return false;
    }

    // 检查新名称是否与其他存储库冲突
    if (oldName != newName &&
        repositories.any((r) => r.name == newName && r.name != oldName)) {
      return false;
    }

    repositories[index] = RepositoryInfo(name: newName, path: newPath);
    await _saveRepositories(repositories);
    return true;
  }

  /// 根据名称获取存储库路径
  Future<String?> getRepositoryPath(String name) async {
    final repositories = await getAllRepositories();
    try {
      final repo = repositories.firstWhere((r) => r.name == name);
      return repo.path;
    } catch (e) {
      return null;
    }
  }

  /// 保存存储库列表
  Future<void> _saveRepositories(List<RepositoryInfo> repositories) async {
    final maps = repositories.map((r) => r.toMap()).toList();
    final jsonStr = jsonEncode(maps);
    await PrefsHelper.setString(_prefsKey, jsonStr);
  }
}


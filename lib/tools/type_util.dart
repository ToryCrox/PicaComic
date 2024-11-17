import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

/// 一些数据转换工具，主要确保安全
class TypeUtil {
  TypeUtil._();

  /// 基本类型
  static const _primitiveTypes = {'int', 'double', 'num', 'bool'};

  static const DeepCollectionEquality _equality = DeepCollectionEquality();

  /// 是否为原始类型
  static bool isPrimitiveType(String type) {
    return _primitiveTypes.contains(type);
  }

  /// 深度比较两个对象是否相等，支持List, Map, Set, Iterable, Object
  static bool equal(Object? a, Object? b) {
    return _equality.equals(a, b);
  }

  /// 是否为空
  /// Map 为空，Iterable 为空，Set 为空，num 为0，bool 为false，其他为true
  static bool isEmpty(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.isEmpty;
    if (value is Iterable) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    if (value is Set) return value.isEmpty;
    if (value is num) return value == 0;
    if (value is bool) return value == false;
    return false;
  }

  /// 转换成int
  /// 如果value是bool，则true转换成1， false为0
  static int parseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value == 'null') return defaultValue;

    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        if (e is FormatException &&
            e.toString().contains('Invalid radix-10 number')) {
          try {
            return double.parse(value).toInt();
          } catch (e) {
            return defaultValue;
          }
        }
        return defaultValue;
      }
    }
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is bool) return value ? 1 : 0;
    return defaultValue;
  }

  /// 解析bool类型
  /// - 如果为bool类型，则直接返回
  /// - 如果为num类型，则为0表示false，否则为true
  /// - 如果为String类型，则'true'表示true，否则转换Int类型， 判断是否为0
  static bool parseBool(dynamic value, [bool defaultValue = false]) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      return parseInt(value) != 0;
    }
    return defaultValue;
  }

  /// 转换成String
  /// 如果value是bool，则true转换成'1'， false为'0'
  /// 如果value是Map或List, Set，则转换成json字符串
  static String parseString(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value == 'null') return defaultValue;
    if (value is Map || value is Iterable) return jsonEncode(value);
    return '$value';
  }

  /// 转换成String
  /// 如果value是bool，则true转换成'1'， false为'0'
  /// 如果value是Map或List, Set，则转换成json字符串
  static String parseJsonString(
    dynamic value, {
    String defaultValue = '',
    bool isPretty = false,
  }) {
    if (value == null) return defaultValue;
    if (value == 'null') return defaultValue;
    if (value is Map || value is Iterable) {
      if (isPretty) {
        const encoder = JsonEncoder.withIndent('  ', _toEncodableFallback);
        return encoder.convert(value);
      } else {
        return jsonEncode(value);
      }
    }
    return '$value';
  }

  /// 转换成double
  /// 如果value是bool，则true转换成1.0， false为0.0
  /// 如果value是String，则转换成double
  /// 如果value是int，则转换成double
  /// 如果value是double，则直接返回
  /// 如果value是其他类型，则返回0.0
  static double parseDouble(dynamic value, [double defaultValue = 0.0]) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  /// 解析list， value可以为字符串数组
  /// 如果value是字符串，则尝试解析成json数组
  /// 如果value是数组，则直接返回
  /// 如果value是null，则返回空数组
  /// 如果value是其他类型，则返回空数组
  /// 如果value是空字符串，则返回空数组
  static List<T> parseList<T>(dynamic value, T Function(dynamic e) f) {
    if (value == null) return [];
    List list = [];
    if (value is String && value.isNotEmpty && value != 'null') {
      try {
        list = jsonDecode(value);
      } catch (e) {
        list = [];
      }
    } else if (value is List) {
      list = value;
    }

    if (list.isNotEmpty) {
      return list.map((e) => f(e)).toList();
    } else {
      return [];
    }
  }

  static List<dynamic> parseDynamicList(dynamic value) {
    if (value is List<dynamic>) return value;
    return parseList(value, (e) => e);
  }

  static List<String> parseStringList(dynamic value) {
    if (value is List<String>) return value;
    return parseList(value, (e) => parseString(e));
  }

  static List<int> parseIntList(dynamic value) {
    if (value is List<int>) return value;
    return parseList(value, (e) => parseInt(e));
  }

  static List<Map<String, dynamic>> parseMapList(dynamic value) {
    if (value is List<Map<String, dynamic>>) return value;
    return parseList(value, (e) => parseMap(e));
  }

  /// value解析，确保不会报错
  static Map<String, dynamic> parseMap(
    dynamic value, {
    Map<String, dynamic> defaultValue = const {},
  }) {
    if (value == null) return defaultValue;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    if (value is String && value.isNotEmpty && value != 'null') {
      try {
        return jsonDecode(value);
      } catch (e) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  /// 解析Color, 支持#ffffff, #ffffffff, 0xffffffff, 0xffffff, 0xff, 0xffffffff, 0xffffff, 0xff
  /// 如果解析失败，则返回透明色
  static Color parseColor(dynamic value,
      [Color defaultValue = Colors.transparent]) {
    if (value == null) return defaultValue;
    if (value is Color) return value;
    if (value is String) {
      if (!value.startsWith('#') && !value.startsWith('0x')) {
        return defaultValue;
      }
      try {
        return Color(int.parse(value.replaceAll('#', '0xff')));
      } catch (e) {
        return defaultValue;
      }
    }
    if (value is int) return Color(value);
    return defaultValue;
  }

  static bool validList(dynamic value) {
    return (value is List && value.isNotEmpty);
  }

  /// 压缩map，移除空值
  static Map<K, V> shrinkMap<K, V>(Map<K, V> map, {bool copy = false}) {
    if (map.isEmpty) return map;
    final newMap = copy ? Map.of(map) : map;
    newMap.removeWhere((key, value) {
      if (value is Map) {
        shrinkMap(value);
        return value.isEmpty;
      } else if (value is Iterable) {
        // 如果是list， 递归压缩里面的map，但是不要删除map，这样会导致list数量减少
        value.forEach((element) {
          if (element is Map) {
            shrinkMap(element);
          }
        });
        return value.isEmpty;
      } else {
        return isEmpty(value);
      }
    });
    return newMap;
  }

}

Object? _toEncodableFallback(dynamic object) {
  return object.toString();
}


import 'dart:convert';

import 'type_util.dart';


/// map扩展
extension ExtendedMap on Map<dynamic, dynamic> {

  /// 获取int类型的值
  /// 如果key不存在，则返回默认值
  int optInt(String key, [int defaultValue = 0]) {
    return TypeUtil.parseInt(this[key], defaultValue);
  }

  /// 获取double类型的值
  /// 如果key不存在，则返回默认值
  double optDouble(String key, [double defaultValue = 0]) {
    return TypeUtil.parseDouble(this[key], defaultValue);
  }

  /// 获取bool类型的值
  bool optBool(String key, [bool  defaultValue = false]) {
    return TypeUtil.parseBool(this[key], defaultValue);
  }

  /// 获取String类型的值
  String optString(String key, [String  defaultValue = '']) {
    return TypeUtil.parseString(this[key], defaultValue: defaultValue);
  }

  /// 获取List类型的值
  List<T> optList<T>(String key, T Function(dynamic e) f) {
    return TypeUtil.parseList(this[key], f);
  }

  List<dynamic> optDynamicList(String key) {
    return TypeUtil.parseDynamicList(this[key]);
  }

  /// 获取List类型的值
  List<int> optIntList(String key) {
    return TypeUtil.parseIntList(this[key]);
  }

  /// 获取List类型的值
  List<String> optStringList(String key) {
    return TypeUtil.parseStringList(this[key]);
  }

  List<Map<String, dynamic>> optMayList(String key) {
    return TypeUtil.parseMapList(this[key]);
  }

  /// 获取Map类型的值
  Map<String, dynamic> optMap(String key) {
    return TypeUtil.parseMap(this[key]);
  }

  /// 转换成json字符串
  String toJsonString([bool pretty = false]) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ', _toEncodableFallback).convert(this);
    } else {
      return const JsonEncoder(_toEncodableFallback).convert(this);
    }
  }

  Map shrink({bool copy = false}) {
    return TypeUtil.shrinkMap(this, copy: copy);
  }
}

Object? _toEncodableFallback(dynamic object) {
  return object.toString();
}
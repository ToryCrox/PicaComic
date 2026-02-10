import 'package:flutter/material.dart';

enum DownloadColorTag {
  none(null, "无"),
  red(Colors.red, "红"),
  orange(Colors.orange, "橙"),
  yellow(Colors.yellow, "黄"),
  green(Colors.green, "绿"),
  blue(Colors.blue, "蓝"),
  purple(Colors.purple, "紫"),
  grey(Colors.grey, "灰");

  final Color? color;
  final String label;

  const DownloadColorTag(this.color, this.label);

  static DownloadColorTag fromString(String? value) {
    if (value == null) return DownloadColorTag.none;
    try {
      return DownloadColorTag.values.firstWhere((e) => e.name == value);
    } catch (e) {
      return DownloadColorTag.none;
    }
  }
}

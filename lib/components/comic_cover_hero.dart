import 'package:flutter/material.dart';

/// 飞行期间使用列表里的实际封面，避免详情尚未加载时闪成占位图。
Widget comicCoverFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final source = direction == HeroFlightDirection.push
      ? fromHeroContext.widget as Hero
      : toHeroContext.widget as Hero;
  return Material(type: MaterialType.transparency, child: source.child);
}

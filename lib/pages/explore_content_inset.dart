import 'package:flutter/widgets.dart';

/// 向支持覆盖式探索标签栏的页面传递可滚动内容的顶部留白。
class ExploreContentInset extends InheritedWidget {
  const ExploreContentInset({
    required this.inset,
    required super.child,
    super.key,
  });

  final double inset;

  /// 在探索页外使用时无需额外留白。
  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ExploreContentInset>()
          ?.inset ??
      0;

  @override
  bool updateShouldNotify(ExploreContentInset oldWidget) =>
      inset != oldWidget.inset;
}

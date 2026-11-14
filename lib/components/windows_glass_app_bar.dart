import 'package:flutter/material.dart';

/// 兼容已有标题栏调用，使用普通 Material 背景。
class WindowsGlassHeader extends StatelessWidget {
  const WindowsGlassHeader({
    required this.child,
    required this.fallback,
    super.key,
  });
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => fallback;
}

/// 保留原生 AppBar 的尺寸和行为。
class WindowsGlassAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const WindowsGlassAppBar({required this.child, super.key});
  final AppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => child;
}

/// 保留原生 SliverAppBar 的滚动和固定行为。
class WindowsGlassSliverAppBar extends StatelessWidget {
  const WindowsGlassSliverAppBar({required this.child, super.key});
  final SliverAppBar child;

  @override
  Widget build(BuildContext context) => child;
}

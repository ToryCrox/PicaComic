import 'package:flutter/material.dart';

/// 兼容旧调用的面板，统一使用调用方提供的 Material 界面。
class WindowsGlassPanel extends StatelessWidget {
  const WindowsGlassPanel({
    required this.child,
    required this.fallback,
    this.radius = 16,
    this.margin = EdgeInsets.zero,
    this.background,
    this.tintColor,
    super.key,
  });

  final Widget child;
  final Widget fallback;
  final double radius;
  final EdgeInsetsGeometry margin;
  final Widget? background;
  final Color? tintColor;

  @override
  Widget build(BuildContext context) => fallback;
}

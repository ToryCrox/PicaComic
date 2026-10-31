import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../foundation/app.dart';
import '../foundation/app_settings_provider.dart';

/// 着色器初始化成功后才允许渲染玻璃。
bool windowsGlassAvailable = false;

/// 统一的 Windows 玻璃面板，其他平台和关闭状态使用原有界面。
class WindowsGlassPanel extends ConsumerWidget {
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

  /// 自定义面板的基础色，透明度由效果强度控制。
  final Color? tintColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!App.isWindows || !windowsGlassAvailable) return fallback;
    final enabled = ref.watch(
      appSettingProvider(AppSettingKeys.liquidGlassEnabled),
    );
    if (enabled != '1' || MediaQuery.highContrastOf(context)) return fallback;
    final raw = ref.watch(
      appSettingProvider(AppSettingKeys.liquidGlassStrength),
    );
    final strength = (int.tryParse(raw) ?? 1).clamp(0, 2);
    final blur = [4.0, 7.0, 10.0][strength];
    final alpha = [0.88, 0.78, 0.68][strength];
    final baseColor = tintColor ?? Theme.of(context).colorScheme.surface;
    final color = baseColor.withValues(alpha: alpha);
    final borderRadius = BorderRadius.circular(radius);
    final panel = Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: GlassContainer(
          shape: LiquidRoundedRectangle(borderRadius: radius),
          quality: GlassQuality.standard,
          useOwnLayer: true,
          settings: LiquidGlassSettings(
            blur: blur,
            glassColor: color,
            lightIntensity: [0.25, 0.4, 0.6][strength],
          ),
          child: Material(color: Colors.transparent, child: child),
        ),
      ),
    );
    if (background == null) return panel;
    return Stack(
      children: [
        Positioned.fill(child: background!),
        panel,
      ],
    );
  }
}

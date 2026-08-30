import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';

/// 为桌面端提供轻量悬浮反馈的卡片表面。
///
/// 组件仅在 [enabled] 为 `true` 时响应鼠标悬浮，并在系统要求减少动画时
/// 自动禁用缩放，保留颜色和描边反馈。
class HoverScaleCard extends StatefulWidget {
  const HoverScaleCard({
    required this.child,
    super.key,
    this.enabled = true,
    this.scale = 1.015,
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.clipBehavior = Clip.antiAlias,
    this.duration = const Duration(milliseconds: 160),
  });

  /// 卡片内容。
  final Widget child;

  /// 是否启用鼠标悬浮反馈。
  final bool enabled;

  /// 鼠标悬浮时的缩放比例。
  final double scale;

  /// 卡片外边距。
  final EdgeInsetsGeometry margin;

  /// 卡片圆角。
  final BorderRadius borderRadius;

  /// 内容裁剪方式。
  final Clip clipBehavior;

  /// 悬浮动画时长。
  final Duration duration;

  @override
  State<HoverScaleCard> createState() => _HoverScaleCardState();
}

class _HoverScaleCardState extends State<HoverScaleCard> {
  bool _isHovered = false;

  @override
  void didUpdateWidget(covariant HoverScaleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _isHovered = false;
    }
  }

  void _setHovered(bool value) {
    if ((!widget.enabled && value) || _isHovered == value) {
      return;
    }
    setState(() => _isHovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isHovered = widget.enabled && _isHovered;
    final scale = isHovered && !disableAnimations ? widget.scale : 1.0;
    final backgroundColor = isHovered
        ? Color.lerp(
            colorScheme.surfaceContainerLow,
            colorScheme.primary,
            0.055,
          )!
        : colorScheme.surfaceContainerLow;
    final borderColor = isHovered
        ? colorScheme.primary.withValues(alpha: 0.34)
        : colorScheme.outlineVariant.withValues(alpha: 0.28);
    final shadows = <BoxShadow>[
      BoxShadow(
        color: colorScheme.shadow.withValues(alpha: isHovered ? 0.18 : 0.05),
        blurRadius: isHovered ? 14 : 3,
        offset: Offset(0, isHovered ? 4 : 1),
      ),
    ];

    return Padding(
      padding: widget.margin,
      child: MouseRegion(
        cursor: widget.enabled
            ? appClickableMouseCursor
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: AnimatedScale(
          scale: scale,
          duration: widget.duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: widget.duration,
            curve: Curves.easeOutCubic,
            clipBehavior: widget.clipBehavior,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: widget.borderRadius,
              border: Border.all(color: borderColor),
              boxShadow: shadows,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

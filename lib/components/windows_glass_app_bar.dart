import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/app.dart';
import '../foundation/app_settings_provider.dart';
import 'windows_glass_panel.dart';

/// 判断标题栏是否应使用 Windows 玻璃效果。
bool _glassEnabled(BuildContext context, WidgetRef ref) {
  if (!App.isWindows ||
      !windowsGlassAvailable ||
      MediaQuery.highContrastOf(context)) {
    return false;
  }
  return ref.watch(appSettingProvider(AppSettingKeys.liquidGlassEnabled)) ==
      '1';
}

/// 覆盖标题栏的整个区域，让顶部窗口安全区与工具栏使用同一背景。
class WindowsGlassHeader extends ConsumerWidget {
  const WindowsGlassHeader({
    required this.child,
    required this.fallback,
    super.key,
  });

  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_glassEnabled(context, ref)) return fallback;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const Positioned.fill(child: _GlassBackground()),
        child,
      ],
    );
  }
}

/// 玻璃绘制范围略超出可视区域，避免边缘高光形成分隔线。
class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    return const ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: -16,
            right: -16,
            top: -16,
            bottom: -16,
            child: IgnorePointer(
              child: WindowsGlassPanel(
                radius: 0,
                fallback: SizedBox.expand(),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 为常规 AppBar 添加玻璃背景，并保留原始高度和工具栏行为。
class WindowsGlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const WindowsGlassAppBar({required this.child, super.key});
  final AppBar child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_glassEnabled(context, ref) ||
        child.backgroundColor != null ||
        child.flexibleSpace != null) {
      return child;
    }
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        const Positioned.fill(child: _GlassBackground()),
        Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

/// 可滚动页面的标题栏在固定时允许内容从玻璃背后经过。
class WindowsGlassSliverAppBar extends ConsumerWidget {
  const WindowsGlassSliverAppBar({required this.child, super.key});
  final SliverAppBar child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_glassEnabled(context, ref) || child.flexibleSpace != null) {
      return child;
    }
    return SliverAppBar(
      leading: child.leading,
      automaticallyImplyLeading: child.automaticallyImplyLeading,
      title: child.title,
      actions: child.actions,
      automaticallyImplyActions: child.automaticallyImplyActions,
      flexibleSpace: const _GlassBackground(),
      bottom: child.bottom,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: child.shadowColor,
      surfaceTintColor: Colors.transparent,
      forceElevated: child.forceElevated,
      backgroundColor: Colors.transparent,
      foregroundColor: child.foregroundColor,
      iconTheme: child.iconTheme,
      actionsIconTheme: child.actionsIconTheme,
      primary: child.primary,
      centerTitle: child.centerTitle,
      excludeHeaderSemantics: child.excludeHeaderSemantics,
      titleSpacing: child.titleSpacing,
      collapsedHeight: child.collapsedHeight,
      expandedHeight: child.expandedHeight,
      floating: child.floating,
      pinned: child.pinned,
      snap: child.snap,
      stretch: child.stretch,
      stretchTriggerOffset: child.stretchTriggerOffset,
      onStretchTrigger: child.onStretchTrigger,
      shape: child.shape,
      toolbarHeight: child.toolbarHeight,
      leadingWidth: child.leadingWidth,
      toolbarTextStyle: child.toolbarTextStyle,
      titleTextStyle: child.titleTextStyle,
      systemOverlayStyle: child.systemOverlayStyle,
      forceMaterialTransparency: true,
      useDefaultSemanticsOrder: child.useDefaultSemanticsOrder,
      clipBehavior: child.clipBehavior,
      actionsPadding: child.actionsPadding,
    );
  }
}

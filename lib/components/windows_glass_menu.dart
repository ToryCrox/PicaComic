import 'package:flutter/material.dart';

/// 使用原生 Material 菜单并保留已有调用接口。
Future<T?> showWindowsGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  BoxConstraints? constraints,
  Color? color,
}) {
  if (items.isEmpty) return Future<T?>.value();
  return showMenu<T>(
    context: context,
    position: position,
    items: items,
    initialValue: initialValue,
    constraints: constraints,
    color: color,
  );
}

/// 保留菜单项、选择回调和提示文本。
class WindowsGlassPopupMenuButton<T> extends StatelessWidget {
  const WindowsGlassPopupMenuButton({
    required this.itemBuilder,
    this.icon,
    this.tooltip,
    this.position,
    this.initialValue,
    this.onSelected,
    super.key,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final Widget? icon;
  final String? tooltip;
  final PopupMenuPosition? position;
  final T? initialValue;
  final PopupMenuItemSelected<T>? onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    itemBuilder: itemBuilder,
    icon: icon,
    tooltip: tooltip,
    position: position,
    initialValue: initialValue,
    onSelected: onSelected,
  );
}

/// 使用原生 MenuAnchor 展示菜单。
class WindowsGlassMenuAnchor extends StatelessWidget {
  const WindowsGlassMenuAnchor({
    required this.menuChildren,
    required this.builder,
    super.key,
  });
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;

  @override
  Widget build(BuildContext context) =>
      MenuAnchor(menuChildren: menuChildren, builder: builder);
}

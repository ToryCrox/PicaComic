import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../foundation/app.dart';
import '../foundation/app_settings_provider.dart';
import 'windows_glass_panel.dart';

/// 判断当前窗口是否可以使用玻璃菜单。
bool windowsGlassMenusEnabled(BuildContext context, WidgetRef ref) {
  if (!App.isWindows ||
      !windowsGlassAvailable ||
      MediaQuery.highContrastOf(context)) {
    return false;
  }
  return ref.watch(appSettingProvider(AppSettingKeys.liquidGlassEnabled)) ==
      '1';
}

/// 保留 Flutter 菜单项的值、点击行为和禁用状态，在 Windows 使用玻璃面板。
Future<T?> showWindowsGlassMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  T? initialValue,
  BoxConstraints? constraints,
  Color? color,
}) {
  if (items.isEmpty) return Future<T?>.value();
  final canUseGlass =
      App.isWindows &&
      windowsGlassAvailable &&
      !MediaQuery.highContrastOf(context) &&
      ProviderScope.containerOf(
            context,
            listen: false,
          ).read(appSettingProvider(AppSettingKeys.liquidGlassEnabled)) ==
          '1';
  final supported = items.every(
    (item) =>
        item.runtimeType ==
            PopupMenuItem<T>(child: const SizedBox.shrink()).runtimeType ||
        item.runtimeType == CheckedPopupMenuItem<T>().runtimeType ||
        item is PopupMenuDivider,
  );
  if (!canUseGlass || !supported) {
    return showMenu<T>(
      context: context,
      position: position,
      items: items,
      initialValue: initialValue,
      constraints: constraints,
      color: color,
    );
  }
  final navigator = Navigator.of(context);
  return navigator.push<T>(
    _WindowsGlassMenuRoute<T>(
      position: position,
      items: items,
      initialValue: initialValue,
      constraints: constraints,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      dismissLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// 复用原生菜单项的桌面玻璃按钮；关闭玻璃时使用 Flutter 原生按钮。
class WindowsGlassPopupMenuButton<T> extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (!windowsGlassMenusEnabled(context, ref)) {
      return PopupMenuButton<T>(
        itemBuilder: itemBuilder,
        icon: icon,
        tooltip: tooltip,
        position: position,
        initialValue: initialValue,
        onSelected: onSelected,
      );
    }
    return Builder(
      builder: (buttonContext) => IconButton(
        tooltip:
            tooltip ?? MaterialLocalizations.of(buttonContext).showMenuTooltip,
        icon: icon ?? const Icon(Icons.more_vert),
        onPressed: () async {
          final box = buttonContext.findRenderObject() as RenderBox;
          final overlay =
              Navigator.of(buttonContext).overlay!.context.findRenderObject()
                  as RenderBox;
          final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
          final rect = topLeft & box.size;
          final anchor = position == PopupMenuPosition.under
              ? rect.bottomLeft
              : rect.topLeft;
          final selected = await showWindowsGlassMenu<T>(
            context: buttonContext,
            position: RelativeRect.fromLTRB(
              anchor.dx,
              anchor.dy,
              overlay.size.width - anchor.dx,
              overlay.size.height - anchor.dy,
            ),
            items: itemBuilder(buttonContext),
            initialValue: initialValue,
          );
          if (selected != null) onSelected?.call(selected);
        },
      ),
    );
  }
}

/// 为 MenuAnchor 的菜单内容提供统一玻璃背景。
class WindowsGlassMenuAnchor extends ConsumerWidget {
  const WindowsGlassMenuAnchor({
    required this.menuChildren,
    required this.builder,
    super.key,
  });
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!windowsGlassMenusEnabled(context, ref)) {
      return MenuAnchor(menuChildren: menuChildren, builder: builder);
    }
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        WindowsGlassPanel(
          fallback: Material(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: menuChildren,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: menuChildren),
        ),
      ],
      builder: builder,
    );
  }
}

/// 保持菜单项位于原 Navigator 路由中，确保点击先关闭菜单再执行回调。
class _WindowsGlassMenuRoute<T> extends PopupRoute<T> {
  _WindowsGlassMenuRoute({
    required this.position,
    required this.items,
    required this.initialValue,
    required this.constraints,
    required this.themes,
    required this.dismissLabel,
  });
  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final T? initialValue;
  final BoxConstraints? constraints;
  final CapturedThemes themes;
  final String dismissLabel;
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: _initialScrollOffset(),
  );
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => dismissLabel;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  /// 长菜单首次打开时将当前选择滚动到可见范围。
  double _initialScrollOffset() {
    if (initialValue == null) return 0;
    var offset = 0.0;
    for (final item in items) {
      if (item.represents(initialValue)) return offset;
      offset += item.height;
    }
    return 0;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      Builder(
        builder: (context) {
          final menu = Semantics(
            explicitChildNodes: true,
            scopesRoute: true,
            namesRoute: true,
            label: MaterialLocalizations.of(context).popupMenuLabel,
            child: WindowsGlassPanel(
              fallback: Material(
                color: Theme.of(context).colorScheme.surface,
                child: _content(context),
              ),
              child: _content(context),
            ),
          );
          return CustomSingleChildLayout(
            delegate: _MenuPosition(position, constraints),
            child: FadeTransition(
              opacity: animation,
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.arrowDown):
                      DirectionalFocusIntent(TraversalDirection.down),
                  SingleActivator(LogicalKeyboardKey.arrowUp):
                      DirectionalFocusIntent(TraversalDirection.up),
                },
                child: FocusScope(
                  autofocus: true,
                  child: FocusTraversalGroup(child: menu),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context) => SingleChildScrollView(
    controller: _scrollController,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items
            .asMap()
            .entries
            .map(
              (entry) => _buildItem(
                context,
                entry.value,
                autofocus: entry.key == _focusIndex(),
              ),
            )
            .toList(),
      ),
    ),
  );

  int _focusIndex() {
    final selected = items.indexWhere(
      (item) =>
          item is PopupMenuItem<T> &&
          item.enabled &&
          initialValue != null &&
          item.represents(initialValue),
    );
    if (selected >= 0) return selected;
    return items.indexWhere((item) => item is PopupMenuItem<T> && item.enabled);
  }

  /// 将标准 Flutter 菜单项转换成独立的可访问交互项。
  Widget _buildItem(
    BuildContext context,
    PopupMenuEntry<T> entry, {
    required bool autofocus,
  }) {
    if (entry is PopupMenuDivider) return Divider(height: entry.height);
    final item = entry as PopupMenuItem<T>;
    final selected = initialValue != null && entry.represents(initialValue);
    final theme = Theme.of(context);
    final style = item.textStyle ?? theme.textTheme.labelLarge;
    Widget content = item.child ?? const SizedBox.shrink();
    if (item is CheckedPopupMenuItem<T>) {
      content = Row(
        children: [
          SizedBox(
            width: 24,
            child: item.checked ? const Icon(Icons.check, size: 18) : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: item.enabled,
      selected: selected,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          canRequestFocus: item.enabled,
          autofocus: autofocus,
          onTap: item.enabled
              ? () {
                  Navigator.pop<T>(context, item.value);
                  item.onTap?.call();
                }
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: item.height),
            child: Padding(
              padding:
                  item.padding ?? const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DefaultTextStyle(
                  style: (style ?? const TextStyle()).copyWith(
                    color: item.enabled
                        ? theme.colorScheme.onSurface
                        : theme.disabledColor,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(opacity: item.enabled ? 1 : 0.38),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.position, this.constraints);
  final RelativeRect position;
  final BoxConstraints? constraints;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints parent) {
    final available = BoxConstraints(
      maxWidth: math.max(0, parent.maxWidth - 16),
      maxHeight: math.max(0, parent.maxHeight - 16),
    );
    return (constraints ?? const BoxConstraints(minWidth: 112, maxWidth: 320))
        .enforce(available);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = position.left <= position.right
        ? position.left
        : size.width - position.right - childSize.width;
    final y = position.top + childSize.height <= size.height - 8
        ? position.top
        : size.height - position.bottom - childSize.height;
    return Offset(
      x.clamp(8.0, math.max(8.0, size.width - childSize.width - 8)),
      y.clamp(8.0, math.max(8.0, size.height - childSize.height - 8)),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition oldDelegate) =>
      position != oldDelegate.position ||
      constraints != oldDelegate.constraints;
}

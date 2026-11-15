part of 'components.dart';

class PaneItemEntry {
  String label;

  IconData icon;

  IconData activeIcon;

  PaneItemEntry({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class PaneActionEntry {
  String label;

  IconData icon;

  VoidCallback onTap;

  PaneActionEntry({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class NaviPane extends StatefulWidget {
  const NaviPane({
    required this.paneItems,
    required this.paneActions,
    required this.pageBuilder,
    this.initialPage = 0,
    this.onPageChange,
    required this.observer,
    super.key,
  });

  final List<PaneItemEntry> paneItems;

  final List<PaneActionEntry> paneActions;

  final Widget Function(int page) pageBuilder;

  final void Function(int index)? onPageChange;

  final int initialPage;

  final NaviObserver observer;

  @override
  State<NaviPane> createState() => _NaviPaneState();
}

class _NaviPaneState extends State<NaviPane>
    with SingleTickerProviderStateMixin {
  late int _currentPage = widget.initialPage;

  int get currentPage => _currentPage;

  set currentPage(int value) {
    if (value == _currentPage) return;
    _currentPage = value;
    widget.onPageChange?.call(value);
  }

  late AnimationController controller;

  static const _kBottomBarHeight = 58.0;

  /// 侧栏宽度。比 Material 3 NavigationRail 默认的 80 更窄，只放图标。
  static const _kRailWidth = 64.0;

  static const _kTopBarHeight = 48.0;

  /// 移动端布局模式。
  static const _kPaneModeMobile = 0.0;

  /// 窄屏顶部导航布局模式。
  static const _kPaneModeTopBar = 1.0;

  /// 侧栏布局模式（仅图标）。
  static const _kPaneModeRail = 2.0;

  double get bottomBarHeight =>
      _kBottomBarHeight + MediaQuery.paddingOf(context).bottom;

  void onNavigatorStateChange() {
    // Navigator 可能在创建路由的构建阶段通知，布局更新放到当前帧结束。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onRebuild(context);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      lowerBound: _kPaneModeMobile,
      upperBound: _kPaneModeRail,
      vsync: this,
    );
    widget.observer.addListener(onNavigatorStateChange);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    controller.value = targetFormContext(context);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    controller.dispose();
    widget.observer.removeListener(onNavigatorStateChange);
    super.dispose();
  }

  double targetFormContext(BuildContext context) {
    var width = MediaQuery.of(context).size.width;
    double target = _kPaneModeMobile;
    if (widget.observer.pageCount > 1) {
      target = _kPaneModeTopBar;
    }
    if (width > changePoint) {
      target = _kPaneModeRail;
    }
    return target;
  }

  double? animationTarget;

  void onRebuild(BuildContext context) {
    double target = targetFormContext(context);
    if (controller.value != target || animationTarget != target) {
      if (controller.isAnimating) {
        if (animationTarget == target) {
          return;
        } else {
          controller.stop();
        }
      }
      if (target == _kPaneModeTopBar) {
        controller.value = target;
      } else if (controller.value == _kPaneModeTopBar &&
          target == _kPaneModeMobile) {
        controller.value = target;
      } else {
        controller.animateTo(
          target,
          // 与主题动画时长保持一致，布局切换时页面留白和侧栏宽度同步过渡。
          duration: kThemeAnimationDuration,
          curve: Curves.easeInOut,
        );
      }
      animationTarget = target;
    }
  }

  @override
  Widget build(BuildContext context) {
    onRebuild(context);
    return _NaviPopScope(
      action: () {
        if (App.mainNavigatorKey!.currentState!.canPop()) {
          App.mainNavigatorKey!.currentState!.pop();
        } else {
          SystemNavigator.pop();
        }
      },
      popGesture: App.isIOS && !UiMode.m1(context),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final value = controller.value;
          final mediaQuery = MediaQuery.of(context);
          final pageTop =
              (_kTopBarHeight * ((1 - value).clamp(0, 1)) +
                      mediaQuery.padding.top *
                          (value == _kPaneModeTopBar ? 0 : 1))
                  .toDouble();
          final removePageTopPadding =
              value >= _kPaneModeRail || value == _kPaneModeMobile;
          final pageMediaQuery = mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(
              top:
                  pageTop + (removePageTopPadding ? 0 : mediaQuery.padding.top),
            ),
          );
          // 页面向右避让侧栏，随顶部栏 → 侧栏的动画插值。
          final pageInset =
              _kRailWidth * ((value - _kPaneModeTopBar).clamp(0, 1));
          return _NaviLayout(
            withPadding: targetFormContext(context) == _kPaneModeTopBar,
            child: Stack(
              children: [
                if (!App.isWindows)
                  Positioned(
                    left:
                        _kRailWidth *
                        ((value - _kPaneModeRail).clamp(-1.0, 0.0)),
                    top: 0,
                    bottom: 0,
                    child: buildLeft(),
                  ),
                Positioned(
                  // Windows 的标题栏是覆盖层，页面背景从窗口顶部开始绘制；
                  // 原本的避让空间转移到页面的 MediaQuery 顶部 padding。
                  top: App.isWindows ? 0 : pageTop,
                  left: App.isWindows ? 0 : pageInset,
                  right: 0,
                  bottom: bottomBarHeight * ((1 - value).clamp(0, 1)),
                  child: App.isWindows
                      ? MediaQuery(
                          data: pageMediaQuery,
                          child: Material(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Padding(
                              padding: EdgeInsets.only(left: pageInset),
                              child: widget.pageBuilder(currentPage),
                            ),
                          ),
                        )
                      : MediaQuery.removePadding(
                          removeTop: removePageTopPadding,
                          context: context,
                          child: Material(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: widget.pageBuilder(currentPage),
                          ),
                        ),
                ),
                if (App.isWindows)
                  Positioned(
                    left:
                        _kRailWidth *
                        ((value - _kPaneModeRail).clamp(-1.0, 0.0)),
                    top: 0,
                    bottom: 0,
                    child: buildLeft(),
                  ),
                // 导航栏覆盖在页面背景之上，避免页面背景遮住窄屏导航栏内容。
                if (value <= _kPaneModeTopBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomBarHeight * (0 - value),
                    child: buildBottom(),
                  ),
                if (value <= _kPaneModeTopBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    top:
                        _kTopBarHeight * (0 - value) +
                        MediaQuery.paddingOf(context).top * (1 - value),
                    child: buildTop(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildTop() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 16),
        height: _kTopBarHeight,
        width: double.infinity,
        child: Row(
          children: [
            Text(
              widget.paneItems[currentPage].label,
              style: const TextStyle(fontSize: 18),
            ),
            const Spacer(),
            for (var action in widget.paneActions)
              Tooltip(
                message: action.label,
                child: IconButton(
                  icon: Icon(action.icon),
                  onPressed: action.onTap,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildBottom() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      textStyle: Theme.of(context).textTheme.labelSmall,
      elevation: 0,
      child: Container(
        height: _kBottomBarHeight + MediaQuery.paddingOf(context).bottom,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: Row(
            children: List<Widget>.generate(
              widget.paneItems.length,
              (index) => Expanded(
                child: _SingleBottomNaviWidget(
                  enabled: currentPage == index,
                  entry: widget.paneItems[index],
                  onTap: () {
                    setState(() {
                      currentPage = index;
                    });
                  },
                  key: ValueKey(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildLeft() {
    final colors = Theme.of(context).colorScheme;

    return NavigationRail(
      // 只显示图标的窄侧栏，尺寸/指示器/配色全部由主题默认值决定。
      extended: false,
      labelType: NavigationRailLabelType.none,
      minWidth: _kRailWidth,
      selectedIndex: currentPage,
      onDestinationSelected: (index) => setState(() => currentPage = index),
      backgroundColor: colors.surfaceContainerLow,
      scrollable: true,
      trailingAtBottom: true,
      destinations: [
        for (final entry in widget.paneItems)
          NavigationRailDestination(
            icon: _railIcon(entry.icon, entry.label),
            selectedIcon: _railIcon(entry.activeIcon, entry.label),
            label: Text(entry.label),
          ),
      ],
      trailing: widget.paneActions.isEmpty
          ? null
          : _RailActions(entries: widget.paneActions),
    );
  }

  /// 不显示文字，用 Tooltip 提供名称。
  ///
  /// Material 的 InkWell 在桌面端使用箭头指针，这里套一层 [MouseRegion] 保持
  /// 应用统一的手型指针，尺寸与 Material 3 指示器一致。
  Widget _railIcon(IconData icon, String label) {
    return MouseRegion(
      cursor: appClickableMouseCursor,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 56,
          height: 32,
          child: Center(child: Icon(icon)),
        ),
      ),
    );
  }
}

/// 侧栏底部的工具入口集合。
class _RailActions extends StatelessWidget {
  const _RailActions({required this.entries});

  final List<PaneActionEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        for (final entry in entries) _RailActionTile(entry: entry),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 工具入口，只显示图标，名称放在 Tooltip 里。
class _RailActionTile extends StatelessWidget {
  const _RailActionTile({required this.entry});

  final PaneActionEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: entry.label,
      child: Semantics(
        button: true,
        label: entry.label,
        child: InkWell(
          mouseCursor: appClickableMouseCursor,
          onTap: entry.onTap,
          child: SizedBox(
            width: _NaviPaneState._kRailWidth,
            height: 44,
            child: Center(
              child: Icon(entry.icon, size: 24, color: colors.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleBottomNaviWidget extends StatefulWidget {
  const _SingleBottomNaviWidget({
    required this.enabled,
    required this.entry,
    required this.onTap,
    super.key,
  });

  final bool enabled;

  final PaneItemEntry entry;

  final VoidCallback onTap;

  @override
  State<_SingleBottomNaviWidget> createState() =>
      _SingleBottomNaviWidgetState();
}

class _SingleBottomNaviWidgetState extends State<_SingleBottomNaviWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  bool isHovering = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SingleBottomNaviWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        controller.forward(from: 0);
      } else {
        controller.reverse(from: 1);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      value: widget.enabled ? 1 : 0,
      vsync: this,
      duration: _fastAnimationDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: CurvedAnimation(parent: controller, curve: Curves.ease),
      builder: (context, child) {
        return MouseRegion(
          cursor: appClickableMouseCursor,
          onEnter: (details) => setState(() => isHovering = true),
          onExit: (details) => setState(() => isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            child: buildContent(),
          ),
        );
      },
    );
  }

  Widget buildContent() {
    final value = controller.value;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.enabled
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: widget.enabled,
      label: widget.entry.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Color.lerp(
                isHovering ? colorScheme.surfaceContainer : Colors.transparent,
                colorScheme.secondaryContainer,
                value,
              ),
            ),
            child: Icon(
              widget.enabled ? widget.entry.activeIcon : widget.entry.icon,
              size: 21,
              color: foreground,
            ),
          ),
          const SizedBox(height: 2),
          ExcludeSemantics(
            child: Text(
              widget.entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                fontWeight: widget.enabled ? FontWeight.w600 : FontWeight.w400,
                color: widget.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NaviObserver extends NavigatorObserver implements Listenable {
  var routes = Queue<Route>();

  int get pageCount => routes.length;

  @override
  void didPop(Route route, Route? previousRoute) {
    routes.removeLast();
    notifyListeners();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    routes.addLast(route);
    notifyListeners();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    routes.remove(route);
    notifyListeners();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute != null) {
      routes.add(newRoute);
    }
    notifyListeners();
  }

  List<VoidCallback> listeners = [];

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners.remove(listener);
  }

  void notifyListeners() {
    for (var listener in listeners) {
      listener();
    }
  }
}

class _NaviPopScope extends StatelessWidget {
  const _NaviPopScope({
    required this.child,
    this.popGesture = false,
    required this.action,
  });

  final Widget child;
  final bool popGesture;
  final VoidCallback action;

  static bool panStartAtEdge = false;

  @override
  Widget build(BuildContext context) {
    Widget res = App.isIOS
        ? child
        : PopScope(
            canPop: App.isAndroid ? false : true,
            onPopInvokedWithResult: (value, result) {
              action();
            },
            child: child,
          );
    if (popGesture) {
      res = GestureDetector(
        onPanStart: (details) {
          if (details.globalPosition.dx < 64) {
            panStartAtEdge = true;
          }
        },
        onPanEnd: (details) {
          if (details.velocity.pixelsPerSecond.dx < 0 ||
              details.velocity.pixelsPerSecond.dx > 0) {
            if (panStartAtEdge) {
              action();
            }
          }
          panStartAtEdge = false;
        },
        child: res,
      );
    }
    return res;
  }
}

/// 当前导航布局的派生值，按组件树隔离不同导航实例。
class _NaviLayout extends InheritedWidget {
  const _NaviLayout({required this.withPadding, required super.child});

  final bool withPadding;

  @override
  bool updateShouldNotify(_NaviLayout oldWidget) =>
      withPadding != oldWidget.withPadding;
}

/// 根页面在窄屏二级导航布局下避让顶部和底部工具栏。
class NaviPaddingWidget extends StatelessWidget {
  const NaviPaddingWidget({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final withPadding =
        context
            .dependOnInheritedWidgetOfExactType<_NaviLayout>()
            ?.withPadding ??
        false;
    return Padding(
      padding: withPadding
          ? EdgeInsets.only(
              top: _NaviPaneState._kTopBarHeight + context.padding.top,
              bottom: _NaviPaneState._kBottomBarHeight + context.padding.bottom,
            )
          : EdgeInsets.zero,
      child: child,
    );
  }
}

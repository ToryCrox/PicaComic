import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';

import '../../components/components.dart';
import '../../components/window_frame.dart';
import '../../foundation/app.dart';
import '../../foundation/state_controller.dart';
import '../../tools/translations.dart';
import 'reader_logic.dart';
import 'reading_settings.dart';
import 'reading_type.dart';

const _kMaxTapOffset = 4.0;

/// Control scroll when readingMethod is [ReadingMethod.topToBottomContinuously]
/// and the image has been enlarge
class ScrollManager {
  ComicReaderLogic logic;

  ScrollManager(this.logic);

  Offset? tapLocation;

  int? startTime;

  Offset? moveOffset;

  int get fingers => TapController.fingers;

  void tapDown(PointerDownEvent details) {
    moveOffset = Offset.zero;
    startTime = DateTime.now().millisecondsSinceEpoch;
    var temp = logic.state.noScroll;
    logic.setNoScroll(TapController.fingers >= 2);
  }

  void tapUp(PointerUpEvent details) {
    logic.setNoScroll(TapController.fingers >= 2);
    tapLocation = null;

    if (moveOffset != null && moveOffset != Offset.zero) {
      if (moveOffset!.dx * moveOffset!.dx + moveOffset!.dy * moveOffset!.dy >
          400) {
        final offset =
            moveOffset! /
            (DateTime.now().millisecondsSinceEpoch - startTime!).toDouble() *
            100;
        logic.photoViewController.animatePosition?.call(
          logic.photoViewController.position,
          logic.photoViewController.position + offset,
        );
      }
    }
    moveOffset = null;
    startTime = null;
    if (logic.state.fabValue < 58) {
      logic.setFabValue(0);
    } else if (logic.state.fabValue >= 58) {
      logic.setFabValue(0);
      logic.jumpToNextChapter();
    }
  }

  /// handle pointer move event
  void addOffset(Offset value) {
    if (logic.scrollController.offset ==
            logic.scrollController.position.maxScrollExtent &&
        logic.photoViewController.scale == 1 &&
        logic.state.showFloatingButtonValue == 1) {
      logic.setFabValue(logic.state.fabValue - value.dy / 3);
      return;
    }
    if (logic.photoViewController.scale == 1) {
      return;
    }
    if (moveOffset != null) {
      moveOffset = moveOffset! + value;
    }
    if (logic.scrollController.offset !=
            logic.scrollController.position.maxScrollExtent &&
        logic.scrollController.offset !=
            logic.scrollController.position.minScrollExtent) {
      value = Offset(value.dx, 0);
    }
    logic.photoViewController.updateMultiple(
      position: logic.photoViewController.position + value,
    );
    return;
  }
}

class _TapDownPointer {
  int id;
  Offset offset;

  double getDistance() {
    return offset.dx * offset.dx + offset.dy * offset.dy;
  }

  _TapDownPointer(this.id) : offset = const Offset(0, 0);
}

class TapController {
  static ComicReaderLogic? _currentLogic;
  static String? _sessionId;

  static void attach(ComicReaderLogic logic, String sessionId) {
    _currentLogic = logic;
    _sessionId = sessionId;
  }

  static void detach() {
    _currentLogic = null;
    _sessionId = null;
  }

  static Offset? _tapOffset;

  static DateTime lastScrollTime = DateTime(2023);

  static bool ignoreNextTap = false;

  static bool longTimePressScale = false;

  static _TapDownPointer? _tapDownPointer;

  static void Function(PointerUpEvent event)? onTapUpReplacement;

  static int fingers = 0;

  static void onTapCancel(PointerCancelEvent event) {
    fingers--;
  }

  static void onTapDown(PointerDownEvent event) {
    if (event.buttons == kSecondaryMouseButton) {
      handleSecondaryTapUp(event);
      return;
    }
    fingers++;
    if (ignoreNextTap) {
      ignoreNextTap = false;
      return;
    }
    var logic = _currentLogic!;

    if (appdata.settings[55] == "1") {
      _tapDownPointer = _TapDownPointer(event.pointer);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (event.pointer == _tapDownPointer?.id) {
          onTapUpReplacement = _handleLongPressEnd;
          _handleLongPressStart(event.position);
        }
      });
    }

    if (appdata.settings[9] == "4") {
      logic.scrollManager!.tapDown(event);
    }

    if (logic.state.toolsVisible &&
        (event.position.dy <
                MediaQuery.of(App.globalContext!).padding.top + 50 ||
            MediaQuery.of(App.globalContext!).size.height - event.position.dy <
                105 + MediaQuery.of(App.globalContext!).padding.bottom)) {
      return;
    }

    if (event.buttons == kSecondaryMouseButton) {
      if (logic.state.showSettings) {
        logic.hideSettings();
        return;
      }
      logic.toggleTools();
      if (logic.state.toolsVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      }
      return;
    }

    if (!logic.scrollController.hasClients) {
      _tapOffset = event.position;
    } else if (logic.scrollController.hasClients &&
        DateTime.now().difference(lastScrollTime).inMilliseconds > 50) {
      _tapOffset = event.position;
    }
  }

  static void Function(PointerUpEvent detail)? _doubleClickRecognizer;

  static void handleSecondaryTapUp(PointerDownEvent detail) {
    var logic = _currentLogic!;
    showContextMenu(
      context: App.globalContext!,
      globalPosition: detail.position,
      items: [
        popupMenuItem<void>(
          text: "设置".tl,
          icon: Icons.settings_outlined,
          onTap: () => showSettings(App.globalContext!, _sessionId!),
        ),
        if (App.isDesktop)
          popupMenuItem<void>(
            text: "全屏".tl,
            icon: Icons.fullscreen,
            onTap: logic.fullscreen,
          ),
        popupMenuItem<void>(
          text: "自动翻页".tl,
          icon: Icons.play_arrow,
          onTap: () {
            if (!logic.state.isFullScreen && App.isDesktop) {
              logic.fullscreen();
            }
            final newVal = !logic.state.runningAutoPageTurning;
            if (newVal) {
              logic.startAutoPageTurning();
            } else {
              logic.stopAutoPageTurning();
              logic.setToolsVisible(false);
            }
          },
        ),
        if (App.isDesktop)
          popupMenuItem<void>(
            text: "限制最大宽度".tl,
            icon: Icons.width_full,
            onTap: () {
              appdata.settings[43] = appdata.settings[43] == '0' ? "1" : "0";
              appdata.updateSettings();
              Future.microtask(() => logic.notifySettingsChanged());
            },
          ),
        if (App.isDesktop)
          popupMenuItem<void>(
            text: logic.state.isShowOriginSize ? '限制大小' : "显示原图大小".tl,
            icon: Icons.photo_size_select_large_outlined,
            onTap: () {
              logic.toggleShowOriginSize();
            },
          ),
        popupMenuItem<void>(
          text: "收藏图片".tl,
          icon: Icons.favorite_border,
          onTap: () => logic.favoriteCurrentImage(position: detail.position),
        ),
        popupMenuItem<void>(
          text: "退出".tl,
          icon: Icons.exit_to_app,
          onTap: App.globalBack,
        ),
        if (logic.readingData.hasEp)
          popupMenuItem<void>(
            text: "章节".tl,
            icon: Icons.list_alt,
            onTap: logic.openEpsView,
          ),
      ],
    );
  }

  static void onTapUp(PointerUpEvent detail) async {
    fingers--;
    if (onTapUpReplacement != null) {
      onTapUpReplacement!(detail);
      onTapUpReplacement = null;
      return;
    }

    var logic = _currentLogic!;

    _tapDownPointer = null;

    if (appdata.settings[9] == "4") {
      logic.scrollManager!.tapUp(detail);
    }

    if (_tapOffset != null) {
      var distance = (detail.position - _tapOffset!).distanceSquared;
      if (distance > _kMaxTapOffset || distance < -_kMaxTapOffset) {
        return;
      }
      _tapOffset = null;
    } else {
      return;
    }

    if (appdata.settings[49] == "1") {
      if (_doubleClickRecognizer == null) {
        bool flag = false;
        _doubleClickRecognizer = (another) {
          var d = detail.delta - another.delta;
          if (d.dx.abs() < 30 && d.dy.abs() < 30) {
            flag = true;
          }
        };
        await Future.delayed(const Duration(milliseconds: 200));
        _doubleClickRecognizer = null;
        if (flag) {
          _handleDoubleClick(detail.position);
          return;
        }
      } else {
        _doubleClickRecognizer!.call(detail);
        return;
      }
    }

    _handleClick(detail, logic, App.globalContext!);
  }

  static void onPointerMove(PointerMoveEvent event) {
    final logic = _currentLogic!;
    if (event.pointer == _tapDownPointer?.id) {
      _tapDownPointer!.offset += event.delta;
      if (_tapDownPointer!.getDistance() > 1) {
        _tapDownPointer = null;
      }
    }
    if (appdata.settings[9] == "4" && logic.scrollManager!.fingers != 2) {
      logic.scrollManager!.addOffset(event.delta);
    }
  }

  static void _handleClick(
    PointerUpEvent detail,
    ComicReaderLogic logic,
    BuildContext context,
  ) {
    bool flag = false;
    bool flag2 = false;
    final range = int.parse(appdata.settings[40]) / 100;
    if (appdata.settings[0] == "1" && !logic.state.toolsVisible) {
      void updatePageWithSetting(bool next) {
        if (appdata.settings[70] == "1") {
          next = !next;
        }
        next ? logic.jumpToNextPage() : logic.jumpToLastPage();
      }

      switch (appdata.settings[9]) {
        case "1":
        case "5":
          detail.position.dx > MediaQuery.of(context).size.width * (1 - range)
              ? updatePageWithSetting(true)
              : flag = true;
          detail.position.dx < MediaQuery.of(context).size.width * range
              ? updatePageWithSetting(false)
              : flag2 = true;
          break;
        case "2":
        case "6":
          detail.position.dx > MediaQuery.of(context).size.width * (1 - range)
              ? updatePageWithSetting(false)
              : flag = true;
          detail.position.dx < MediaQuery.of(context).size.width * range
              ? updatePageWithSetting(true)
              : flag2 = true;
          break;
        case "3":
          detail.position.dy > MediaQuery.of(context).size.height * (1 - range)
              ? updatePageWithSetting(true)
              : flag = true;
          detail.position.dy < MediaQuery.of(context).size.height * range
              ? updatePageWithSetting(false)
              : flag2 = true;
          break;
        case "4":
          detail.position.dy > MediaQuery.of(context).size.height * (1 - range)
              ? logic.jumpToNextPage()
              : flag = true;
          detail.position.dy < MediaQuery.of(context).size.height * range
              ? logic.jumpToLastPage()
              : flag2 = true;
          break;
      }
    } else {
      flag = flag2 = true;
    }
    if (flag && flag2) {
      logic.toggleTools();
      if (logic.state.toolsVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        StateController.findOrNull<WindowFrameController>()?.resetTheme();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        if (appdata.settings[81] == "1") {
          StateController.findOrNull<WindowFrameController>()?.setDarkTheme();
        }
      }
    }
  }

  static void _handleDoubleClick(Offset position) async {
    var logic = _currentLogic!;
    var controller = logic.photoViewController;
    double target;
    if (controller.scale == null ||
        controller.getInitialScale?.call() == null) {
      return;
    }
    if (!logic.state.readingMethod.useComicImage) {
      controller.onDoubleClick?.call();
      return;
    }
    if (controller.scale != controller.getInitialScale?.call()) {
      target = controller.getInitialScale!.call()!;
    } else {
      target = controller.getInitialScale!.call()! * 1.75;
    }
    var size = MediaQuery.of(App.globalContext!).size;
    controller.animateScale?.call(
      target,
      Offset(size.width / 2 - position.dx, size.height / 2 - position.dy),
    );
  }

  static void _handleLongPressStart(Offset position) {
    var logic = _currentLogic!;
    var controller = logic.photoViewController;
    if (controller.scale != controller.getInitialScale?.call() ||
        controller.scale == null ||
        controller.getInitialScale?.call() == null) {
      return;
    }
    final target = controller.getInitialScale!.call()! * 1.75;
    var size = MediaQuery.of(App.globalContext!).size;
    controller.animateScale?.call(
      target,
      Offset(size.width / 2 - position.dx, size.height / 2 - position.dy),
    );
    controller.updateState?.call(null);
  }

  static void _handleLongPressEnd(PointerUpEvent event) {
    var logic = _currentLogic!;
    var controller = logic.photoViewController;
    if (controller.scale == controller.getInitialScale?.call() ||
        controller.scale == null) {
      return;
    }
    final target = controller.getInitialScale?.call();
    controller.animateScale?.call(target ?? 1);
    controller.updateState?.call(null);
  }
}

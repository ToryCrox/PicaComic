import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../components/components.dart';
import '../../foundation/app.dart';
import '../../foundation/log.dart';
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
    if (logic.continuousReading) {
      logic.continuousScrollEnd();
      return;
    }
    if (logic.snapshot.fabValue < 58) {
      logic.setFabValue(0);
    } else if (logic.snapshot.fabValue >= 58) {
      logic.setFabValue(0);
      logic.jumpToNextChapter();
    }
  }

  /// handle pointer move event
  void addOffset(Offset value) {
    if (!logic.continuousReading &&
        logic.scrollController.offset ==
            logic.scrollController.position.maxScrollExtent &&
        logic.photoViewController.scale == 1 &&
        logic.snapshot.showFloatingButtonValue == 1) {
      logic.setFabValue(logic.snapshot.fabValue - value.dy / 3);
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

/// 静态触控回调通过当前阅读会话读取类型化配置，不直接依赖设置存储。
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
    final settings = logic.readerSettings;

    if (settings.longPressZoom) {
      _tapDownPointer = _TapDownPointer(event.pointer);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (event.pointer == _tapDownPointer?.id) {
          onTapUpReplacement = _handleLongPressEnd;
          _handleLongPressStart(event.position);
        }
      });
    }

    if (settings.readingMode == 4) {
      logic.scrollManager!.tapDown(event);
    }

    if (logic.snapshot.toolsVisible &&
        (event.position.dy <
                MediaQuery.of(App.globalContext!).padding.top + 50 ||
            MediaQuery.of(App.globalContext!).size.height - event.position.dy <
                105 + MediaQuery.of(App.globalContext!).padding.bottom)) {
      return;
    }

    if (event.buttons == kSecondaryMouseButton) {
      if (logic.snapshot.showSettings) {
        logic.hideSettings();
        return;
      }
      logic.toggleTools();
      if (logic.snapshot.toolsVisible) {
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

  /// 按右键命中的图片查询收藏状态，并固定本次菜单的操作目标。
  static Future<void> handleSecondaryTapUp(PointerDownEvent detail) async {
    final logic = _currentLogic;
    final sessionId = _sessionId;
    final context = App.globalContext;
    if (logic == null || sessionId == null || context == null) return;
    final image = logic.imageAtPosition(detail.position);
    var isFavorited = false;
    try {
      if (image != null) isFavorited = await logic.isImageFavorited(image);
    } catch (error, stack) {
      Log.e('读取图片收藏状态失败', error: error, stackTrace: stack);
      showToast(message: '图片收藏操作失败'.tl);
      return;
    }
    if (!context.mounted || _currentLogic != logic || _sessionId != sessionId) {
      return;
    }
    await showContextMenu(
      context: context,
      globalPosition: detail.position,
      items: [
        popupMenuItem<void>(
          text: "设置".tl,
          icon: Icons.settings_outlined,
          onTap: () => showSettings(context, sessionId),
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
            if (!logic.snapshot.isFullScreen && App.isDesktop) {
              logic.fullscreen();
            }
            final newVal = !logic.snapshot.runningAutoPageTurning;
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
            onTap: logic.toggleImageWidthLimit,
          ),
        if (App.isDesktop)
          popupMenuItem<void>(
            text: logic.snapshot.isShowOriginSize ? '限制大小' : "显示原图大小".tl,
            icon: Icons.photo_size_select_large_outlined,
            onTap: () {
              logic.toggleShowOriginSize();
            },
          ),
        popupMenuItem<void>(
          text: isFavorited ? "取消收藏".tl : "收藏图片".tl,
          icon: isFavorited ? Icons.favorite : Icons.favorite_border,
          enabled: image != null,
          onTap: () => logic.favoriteCurrentImage(image: image),
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
    final settings = logic.readerSettings;

    _tapDownPointer = null;

    if (settings.readingMode == 4) {
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

    if (settings.doubleTapZoom) {
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
    final settings = logic.readerSettings;
    if (event.pointer == _tapDownPointer?.id) {
      _tapDownPointer!.offset += event.delta;
      if (_tapDownPointer!.getDistance() > 1) {
        _tapDownPointer = null;
      }
    }
    if (settings.readingMode == 4 && logic.scrollManager!.fingers != 2) {
      logic.scrollManager!.addOffset(event.delta);
    }
  }

  static void _handleClick(
    PointerUpEvent detail,
    ComicReaderLogic logic,
    BuildContext context,
  ) {
    final settings = logic.readerSettings;
    bool flag = false;
    bool flag2 = false;
    final range = settings.tapRange / 100;
    if (settings.flipWithTap && !logic.snapshot.toolsVisible) {
      void updatePageWithSetting(bool next) {
        if (settings.reverseTap) {
          next = !next;
        }
        next ? logic.jumpToNextPage() : logic.jumpToLastPage();
      }

      switch (settings.readingMode.toString()) {
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
      if (logic.snapshot.toolsVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        logic.setWindowDarkTheme(false);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
        if (settings.readerDarkBackground) {
          logic.setWindowDarkTheme(true);
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
    if (!logic.snapshot.readingMethod.useComicImage) {
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

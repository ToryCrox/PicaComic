import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pica_comic/base.dart';

import '../../components/components.dart';
import '../../components/custom_slider.dart';
import '../../foundation/app.dart';
import '../../foundation/widget_utils.dart';
import '../../tools/iterable_extension.dart';
import '../../tools/translations.dart';
import 'reader_logic.dart';
import 'reading_data.dart';
import 'reading_settings.dart';
import 'reading_type.dart';

bool _isReversed() =>
    appdata.settings[9] == "2" || appdata.settings[9] == "6";

/// 构建底部工具栏
Widget buildBottomToolBar(
  ComicReaderLogic logic,
  BuildContext context, {
  required bool showEps,
  required bool useDarkBackground,
  required void Function() openEpsDrawer,
  required void Function() onShare,
  required void Function() onSaveCurrentImage,
}) {
  return Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: Builder(
      builder: (context) {
        var text = "E${logic.state.currentEpisode} : P${logic.state.currentPage}";
        if (logic.state.currentEpisode == 0) {
          text = "P${logic.state.currentPage}";
        }

        Widget child = SizedBox(
          height: 105 + MediaQuery.of(context).padding.bottom,
          child: Column(
            children: [
              const SizedBox(
                height: 8,
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 8,
                  ),
                  IconButton.filledTonal(
                      onPressed: () => !_isReversed()
                          ? logic.jumpToLastChapter()
                          : logic.jumpToNextChapter(),
                      icon: const Icon(Icons.first_page)),
                  Expanded(
                    child: buildSlider(logic),
                  ),
                  IconButton.filledTonal(
                      onPressed: () => !_isReversed()
                          ? logic.jumpToNextChapter()
                          : logic.jumpToLastChapter(),
                      icon: const Icon(Icons.last_page)),
                  const SizedBox(
                    width: 8,
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                  ),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(text),
                  ),
                  const Spacer(),
                  if (App.isDesktop)
                    Tooltip(
                      message: "${"全屏".tl}(F12)",
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen),
                        onPressed: () {
                          logic.fullscreen();
                        },
                      ),
                    ),
                  if (App.isAndroid && appdata.settings[76] == "0")
                    Tooltip(
                      message: "屏幕方向".tl,
                      child: IconButton(
                        icon: () {
                          if (logic.state.rotation == null) {
                            return const Icon(Icons.screen_rotation_alt);
                          } else if (logic.state.rotation == false) {
                            return const Icon(Icons.screen_lock_portrait);
                          } else {
                            return const Icon(Icons.screen_lock_landscape);
                          }
                        }.call(),
                        onPressed: () {
                          if (logic.state.rotation == null) {
                            logic.state = logic.state.copyWith(rotation: false);
                            SystemChrome.setPreferredOrientations([
                              DeviceOrientation.portraitUp,
                              DeviceOrientation.portraitDown,
                            ]);
                          } else if (logic.state.rotation == false) {
                            logic.state = logic.state.copyWith(rotation: true);
                            SystemChrome.setPreferredOrientations([
                              DeviceOrientation.landscapeLeft,
                              DeviceOrientation.landscapeRight
                            ]);
                          } else {
                            logic.state = logic.state.copyWith(rotation: null);
                            SystemChrome.setPreferredOrientations(
                                DeviceOrientation.values);
                          }
                        },
                      ),
                    ),
                  Tooltip(
                    message: "收藏图片".tl,
                    child: IconButton(
                      icon: const Icon(Icons.favorite_outline),
                      onPressed: () => logic.favoriteCurrentImage(),
                    ),
                  ),
                  Tooltip(
                    message: "自动翻页".tl,
                    child: IconButton(
                      icon: logic.state.runningAutoPageTurning
                          ? const Icon(Icons.timer)
                          : const Icon(Icons.timer_sharp),
                      onPressed: () {
                        final newVal = !logic.state.runningAutoPageTurning;
                        logic.state = logic.state.copyWith(
                            runningAutoPageTurning: newVal);
                        logic.autoPageTurning();
                      },
                    ),
                  ),
                  if (showEps)
                    Tooltip(
                      message: "章节".tl,
                      child: IconButton(
                        icon: const Icon(Icons.format_list_numbered),
                        onPressed: openEpsDrawer,
                      ),
                    ),
                  Tooltip(
                    message: "保存图片".tl,
                    child: IconButton(
                      icon: const Icon(Icons.save_alt),
                      onPressed: onSaveCurrentImage,
                    ),
                  ),
                  Tooltip(
                    message: "分享".tl,
                    child: IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: onShare,
                    ),
                  ),
                  const SizedBox(
                    width: 5,
                  )
                ],
              )
            ],
          ),
        );

        child = Material(
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
          elevation: 3,
          child: child,
        );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          reverseDuration: const Duration(milliseconds: 150),
          switchInCurve: Curves.fastOutSlowIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
            var tween = Tween<Offset>(
                begin: const Offset(0, 1), end: const Offset(0, 0));
            return SlideTransition(
              position: tween.animate(animation),
              child: child,
            );
          },
          child: logic.state.toolsVisible
              ? child
              : const SizedBox(
                  width: 0,
                  height: 0,
                ),
        );
      },
    ),
  );
}

Widget buildSlider(ComicReaderLogic logic) {
  if (logic.state.toolsVisible &&
      logic.state.currentPage != 0 &&
      logic.state.currentPage != logic.state.urls.length + 1) {
    return CustomSlider(
      value: logic.state.currentPage.toDouble(),
      min: 1,
      reversed: _isReversed(),
      max: logic.state.urls.length.toDouble(),
      divisions: logic.state.urls.length - 1,
      onChanged: (i) {
        if (logic.state.readingMethod == ReadingMethod.topToBottomContinuously) {
          logic.jumpToPage(i.toInt());
          logic.state = logic.state.copyWith(currentPage: i.toInt());
        } else {
          logic.state = logic.state.copyWith(currentPage: i.toInt());
          logic.jumpToPage(i.toInt());
        }
      },
    );
  } else {
    return const SizedBox(
      height: 0,
    );
  }
}

Iterable<Widget> buildButtons(
    ComicReaderLogic logic, BuildContext context) sync* {
  if (context.width > context.height &&
      appdata.appSettings.showButtonsInReader) {
    if (appdata.settings[9] != "4" &&
        logic.state.readingMethod != ReadingMethod.topToBottom) {
      yield Positioned(
        left: 12,
        top: MediaQuery.sizeOf(context).height / 2 - 25,
        child: Button.icon(
          icon: const Icon(Icons.keyboard_arrow_left),
          onPressed: () {
            if (appdata.appSettings.flipPageWithClick) {
              return;
            }
            switch (logic.state.readingMethod) {
              case ReadingMethod.rightToLeft:
              case ReadingMethod.twoPageReversed:
                logic.jumpToNextPage();
              default:
                logic.jumpToLastPage();
            }
          },
          size: 24,
        ),
      );
    }
    if (appdata.settings[9] != "4" &&
        logic.state.readingMethod != ReadingMethod.topToBottom) {
      yield Positioned(
        right: 12,
        top: MediaQuery.sizeOf(context).height / 2 - 25,
        child: Button.icon(
          icon: const Icon(Icons.keyboard_arrow_right),
          onPressed: () {
            if (appdata.settings[0] == "1") {
              return;
            }
            switch (logic.state.readingMethod) {
              case ReadingMethod.rightToLeft:
              case ReadingMethod.twoPageReversed:
                logic.jumpToLastPage();
              default:
                logic.jumpToNextPage();
            }
          },
          size: 24,
        ),
      );
    }
  }
  yield Positioned(
    left: 4,
    top: 4 + MediaQuery.paddingOf(context).top,
    child: IconButton(
      iconSize: 24,
      icon: const Icon(Icons.close),
      onPressed: () => App.globalBack(),
    ),
  );
}

/// 构建顶部工具栏
Widget buildTopToolBar(
    ComicReaderLogic logic, BuildContext context,
    {required ReadingData readingData, required bool useDarkBackground}) {
  return Positioned(
    top: 0,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 150),
      switchInCurve: Curves.fastOutSlowIn,
      child: logic.state.toolsVisible
          ? Material(
              surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
              elevation: 3,
              shadowColor:
                  Theme.of(context).colorScheme.shadow.withOpacity(0.3),
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: Tooltip(
                        message: "返回".tl,
                        child: IconButton(
                          iconSize: 25,
                          icon: const Icon(Icons.arrow_back_outlined),
                          onPressed: () => App.globalBack(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 50,
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width - 75),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            readingData.title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      child: Tooltip(
                        message: "阅读设置".tl,
                        child: IconButton(
                          iconSize: 25,
                          icon: const Icon(Icons.settings),
                          onPressed: () => showSettings(context, logic),
                        ),
                      ),
                    ),
                  ],
                ),
              ).paddingTop(MediaQuery.of(context).padding.top),
            )
          : const SizedBox(
              width: 0,
              height: 0,
            ),
      transitionBuilder: (Widget child, Animation<double> animation) {
        var tween = Tween<Offset>(
            begin: const Offset(0, -1), end: const Offset(0, 0));
        return SlideTransition(
          position: tween.animate(animation),
          child: child,
        );
      },
    ),
  );
}

/// 显示当前的章节和页面位置
Widget buildPageInfoText(
    ComicReaderLogic logic, BuildContext context,
    {required ReadingData readingData, required bool useDarkBackground}) {
  return Positioned(
    bottom: 13,
    left: 25,
    child: Builder(
      builder: (context) {
        var epName = readingData.eps?.values
                .elementAtOrNull(logic.state.currentEpisode - 1) ??
            "E1";
        if (epName.length > 18) {
          epName = "${epName.substring(0, 18)}...";
        }
        var text = readingData.hasEp
            ? "$epName : ${logic.state.currentPage}/${logic.state.urls.length}"
            : "${logic.state.currentPage}/${logic.state.urls.length}";
        return Stack(
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.4
                  ..color = (useDarkBackground ||
                          Theme.of(context).brightness == Brightness.dark)
                      ? Colors.black
                      : Colors.white,
              ),
            ),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: useDarkBackground ? Colors.white : null,
              ),
            ),
          ],
        );
      },
    ),
  );
}

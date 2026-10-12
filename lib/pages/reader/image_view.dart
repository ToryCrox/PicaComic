import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../components/scrollable_list/src/scrollable_positioned_list.dart';
import '../../foundation/app.dart';
import '../../foundation/image_manager.dart';
import '../../foundation/log.dart';
import '../../foundation/theme/app_mouse_cursor.dart';
import 'image.dart';
import 'chapter_separator.dart';
import 'continuous_reader_data.dart';
import 'reader_logic.dart';
import 'reading_data.dart';
import 'reading_type.dart';
import 'touch_control.dart';

extension ScrollExtension on ScrollController {
  /// 鼠标滚轮滚动时直接跳转到目标位置，不使用动画，使滚动更跟手
  void smoothTo(double value) {
    final targetPosition = (position.pixels + value).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    jumpTo(targetPosition);
  }
}

const Set<PointerDeviceKind> _kTouchLikeDeviceTypes = <PointerDeviceKind>{
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
  PointerDeviceKind.unknown,
};

/// 构建漫画阅读视图。
Widget buildComicView(
  ReaderPageState state,
  ComicReaderLogic logic,
  BuildContext context,
  String target,
  ReadingData readingData,
  bool useDarkBackground, {
  bool isShowSelectImage = false,
}) {
  return _ComicViewBuilder(
    state,
    logic,
    context,
    target,
    readingData,
    useDarkBackground,
    isShowSelectImage,
  ).build();
}

/// 按阅读方式构建视图，手势和滚动通知独立处理。
class _ComicViewBuilder {
  const _ComicViewBuilder(
    this.state,
    this.logic,
    this.context,
    this.target,
    this.readingData,
    this.useDarkBackground,
    this.isShowSelectImage,
  );

  final ReaderPageState state;
  final ComicReaderLogic logic;
  final BuildContext context;
  final String target;
  final ReadingData readingData;
  final bool useDarkBackground;
  final bool isShowSelectImage;

  BoxDecoration get decoration => BoxDecoration(
    color: useDarkBackground
        ? Colors.black
        : Theme.of(context).colorScheme.surface,
  );

  /// 构建阅读方式及触摸交互。
  Widget build() {
    Widget body;

    if (state.readingMethod.index < 3) {
      body = _buildSinglePageGallery();
    } else if (state.readingMethod == ReadingMethod.topToBottomContinuously) {
      logic.photoViewControllers[0] ??= PhotoViewController();
      body = PhotoView.customChild(
        backgroundDecoration: decoration,
        key: Key(logic.readerViewIdentity),
        minScale: 1.0,
        maxScale: 2.5,
        strictScale: true,
        controller: logic.photoViewControllers[0],
        onScaleEnd: (context, detail, value) {
          logic.setCurrentScale(value.scale ?? 1.0);
          if (!logic.readerSettings.limitImageWidth) {
            return false;
          }
          return updateLocation(context, logic.photoViewController);
        },
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: Builder(
            builder: (viewportContext) {
              logic.readerViewportContext = viewportContext;
              return _buildContinuousList();
            },
          ),
        ),
      );
    } else {
      body = _buildTwoPageGallery();
    }

    return Positioned.fill(
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomUpdate: (event) {},
        onPointerDown: (details) {
          logic.internalMouseScroll = false;
          logic.userInteracting = true;
          logic.pauseAutoPageTurning();
          logic.notifySettingsChanged();
        },
        onPointerUp: (details) {
          logic.userInteracting = false;

          if (state.readingMethod == ReadingMethod.topToBottomContinuously &&
              logic.scrollRecords.length >= 2) {
            final secondLast =
                logic.scrollRecords[logic.scrollRecords.length - 2];
            final last = logic.scrollRecords.last;
            final timeDiff = (last.timestamp - secondLast.timestamp) / 1000.0;

            if (timeDiff > 0) {
              final positionDiff = last.position - secondLast.position;
              logic.releaseVelocity = positionDiff / timeDiff;
              Log.d(
                () =>
                    "onPointerUp velocity: ${logic.releaseVelocity} (timeDiff: ${timeDiff}s, positionDiff: $positionDiff)",
              );
            }
          }

          // Only resume immediately if there was no real drag (e.g. tap).
          // If the user actually dragged, let ScrollEndNotification handle it
          // to avoid conflicting with the upcoming ballistic scroll.
          if (logic.releaseVelocity == null &&
              (!logic.scrollController.hasClients ||
                  !logic.scrollController.position.isScrollingNotifier.value)) {
            logic.resumeAutoPageTurning();
          }
        },
        onPointerCancel: (details) {
          logic.userInteracting = false;
          if (!logic.scrollController.hasClients ||
              !logic.scrollController.position.isScrollingNotifier.value) {
            logic.resumeAutoPageTurning();
          }
        },
        child: NotificationListener<ScrollNotification>(
          child: body,
          onNotification: _onScrollNotification,
        ),
      ),
    );
  }

  /// 构建带章节分隔的连续图片列表。
  Widget _buildContinuousList() {
    final initialPage = state.currentPage
        .clamp(1, max(1, state.urls.length))
        .toInt();
    var initialIndex = initialPage - 1;
    if (state.continuousReading) {
      initialIndex = state.readingItems.indexWhere(
        (item) =>
            item.isImage &&
            item.episode == state.currentEpisode &&
            item.page == initialPage - 1,
      );
    }
    return ScrollablePositionedList.builder(
      initialScrollIndex: initialIndex < 0 ? 0 : initialIndex,
      itemScrollController: logic.itemScrollController,
      itemPositionsListener: logic.itemScrollListener,
      itemCount: state.continuousReading
          ? state.readingItems.length
          : state.urls.length,
      itemKeyBuilder: state.continuousReading
          ? (index) => state.readingItems[index].identity
          : null,
      maintainVisibleContentPosition: state.continuousReading,
      addSemanticIndexes: false,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      scrollController: logic.scrollController,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
        dragDevices: _kTouchLikeDeviceTypes,
      ),
      physics: (state.noScroll || logic.isCtrlPressed || logic.mouseScroll)
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemBuilder: (context, index) {
        ReaderItem? readerItem;
        if (state.continuousReading) {
          readerItem = state.readingItems[index];
          if (!readerItem.isImage) {
            final episode = readerItem.episode;
            final titles = readingData.eps!.values.toList();
            return ChapterSeparator(
              key: ValueKey(readerItem.identity),
              item: readerItem,
              title: titles[episode - 1],
              previousTitle: episode > 1 ? titles[episode - 2] : null,
              onRetry: () => logic.retryContinuousChapter(episode),
              onSkip: () => logic.skipContinuousChapter(
                episode,
                episode < state.currentEpisode ? -1 : 1,
              ),
            );
          }
          precacheContinuousImages(state, logic, context, index, readingData);
        }
        final mediaQuery = MediaQuery.of(context);
        double width = mediaQuery.size.width;
        double height = mediaQuery.size.height;

        double imageWidth = width;
        double imageHeight = imageWidth * 1.2;
        BoxFit imageFit = BoxFit.cover;
        bool showOriginSize = false;

        bool hasOriginSize = false;
        if (state.isShowOriginSize) {
          final url = readerItem?.url ?? state.urls[index];
          final size = logic.imageSize[url];
          if (size != null && size.height > 0 && size.width > 0) {
            final originWidth = size.width / mediaQuery.devicePixelRatio;
            final originHeight = size.height / mediaQuery.devicePixelRatio;
            final oRadio = size.height / size.width;
            if (oRadio <= 1) {
              if (originWidth > width) {
                imageWidth = width;
              } else {
                imageWidth = originWidth;
              }
            } else if (oRadio > 1) {
              final mmWidth = (2560 / mediaQuery.devicePixelRatio);
              final maxWidth = mmWidth > width ? width : mmWidth;
              if (originWidth > maxWidth) {
                imageWidth = maxWidth;
              } else {
                imageWidth = originWidth;
              }
            } else if (originWidth > width) {
              imageWidth = width;
            } else {
              imageWidth = originWidth;
            }
            hasOriginSize = true;
            imageHeight = imageWidth * (originHeight / originWidth);
            imageFit = BoxFit.contain;
            showOriginSize = true;
          } else {
            hasOriginSize = false;
          }
        }
        if (!hasOriginSize &&
            height / width < 1 &&
            logic.readerSettings.limitImageWidth) {
          imageWidth = min(height / 0.8, 2160 / mediaQuery.devicePixelRatio);
        }

        if (!state.continuousReading) {
          precacheComicImage(
            state,
            logic,
            context,
            index + 1,
            target,
            readingData,
          );
        }
        ImageProvider image;
        if (readerItem != null) {
          image = readingData.createImageProvider(
            readerItem.episode,
            readerItem.page,
            readerItem.url,
          );
        } else {
          image = createImageProvider(state, index, target, readingData);
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            ComicImage(
              key: readerItem == null ? null : ValueKey(readerItem.identity),
              filterQuality: FilterQuality.medium,
              image: image,
              width: imageWidth,
              height: imageHeight,
              fit: imageFit,
              isShowOriginSize: showOriginSize,
            ),
            if (isShowSelectImage)
              Positioned.fill(
                top: 20,
                bottom: 20,
                child: Container(
                  color: Colors.grey.withOpacity(0.6),
                  alignment: Alignment.center,
                  child: Text(
                    logic.imageLabel(index),
                    style: const TextStyle(color: Colors.white, fontSize: 40),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 构建单页画廊和原有手动跨章入口。
  Widget _buildSinglePageGallery() {
    return PhotoViewGallery.builder(
      backgroundDecoration: decoration,
      key: Key(state.readingMethod.index.toString()),
      reverse: logic.readerSettings.readingMode == 2,
      scrollDirection: logic.readerSettings.readingMode != 3
          ? Axis.horizontal
          : Axis.vertical,
      itemCount: state.urls.length + 2,
      builder: (BuildContext context, int index) {
        ImageProvider? imageProvider;
        if (index != 0 && index != state.urls.length + 1) {
          imageProvider = createImageProvider(
            state,
            index - 1,
            target,
            readingData,
          );
        } else {
          return PhotoViewGalleryPageOptions.customChild(
            scaleStateController: PhotoViewScaleStateController(),
            child: const SizedBox(),
          );
        }

        precacheComicImage(state, logic, context, index, target, readingData);

        BoxFit getFit() {
          switch (logic.readerSettings.imageLayout) {
            case 1:
              return BoxFit.fitWidth;
            case 2:
              return BoxFit.fitHeight;
            default:
              return BoxFit.contain;
          }
        }

        logic.photoViewControllers[index] ??= PhotoViewController();

        return PhotoViewGalleryPageOptions(
          filterQuality: FilterQuality.medium,
          imageProvider: imageProvider,
          fit: getFit(),
          controller: logic.photoViewControllers[index],
          errorBuilder: (_, error, s, retry) {
            return Center(
              child: SizedBox(
                height: 300,
                width: 400,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          error.toString(),
                          style: TextStyle(
                            color: logic.readerSettings.readerDarkBackground
                                ? Colors.white
                                : null,
                          ),
                          maxLines: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    MouseRegion(
                      cursor: appClickableMouseCursor,
                      child: Listener(
                        onPointerDown: (details) {
                          TapController.ignoreNextTap = true;
                          retry();
                        },
                        child: const SizedBox(
                          width: 84,
                          height: 36,
                          child: Center(
                            child: Text(
                              "Retry",
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
          heroAttributes: PhotoViewHeroAttributes(
            tag: "$index/${state.urls.length}",
          ),
        );
      },
      pageController: logic.pageController,
      loadingBuilder: (context, event) => Center(
        child: SizedBox(
          width: 20.0,
          height: 20.0,
          child: CircularProgressIndicator(
            backgroundColor: context.colorScheme.surfaceContainerHigh,
            value: event == null || event.expectedTotalBytes == null
                ? null
                : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
          ),
        ),
      ),
      onPageChanged: (i) {
        if (i == 0) {
          if (!readingData.hasEp) {
            logic.jumpByDeviceType(1);
            return;
          }
          logic.jumpToLastChapter();
        } else if (i == state.urls.length + 1) {
          if (!readingData.hasEp) {
            logic.jumpByDeviceType(i - 1);
            return;
          }
          logic.jumpToNextChapter();
        } else {
          logic.setCurrentPage(i);
          logic.notifyIndexChange(i);
        }
      },
    );
  }

  /// 构建双页模式中的单张图片。
  Widget _buildComicImageOrEmpty({
    required int imageIndex,
    required BoxFit fit,
    required Alignment alignment,
  }) {
    if (imageIndex < 0 || imageIndex >= state.urls.length) {
      return const SizedBox();
    }

    return ComicImage(
      key: ValueKey(imageIndex),
      image: createImageProvider(state, imageIndex, target, readingData),
      fit: fit,
      alignment: alignment,
    );
  }

  /// 构建双页画廊，保持原有章内配对规则。
  Widget _buildTwoPageGallery() {
    int calcItemCount() {
      int count = state.urls.length ~/ 2;
      if (state.urls.length % 2 != 0) {
        count++;
      } else if (logic.singlePageForFirstScreen) {
        count++;
      }
      return count + 2;
    }

    return PhotoViewGallery.builder(
      key: Key(state.readingMethod.index.toString()),
      backgroundDecoration: decoration,
      itemCount: calcItemCount(),
      reverse: state.readingMethod == ReadingMethod.twoPageReversed,
      builder: (BuildContext context, int index) {
        if (index == 0 || index == calcItemCount() - 1) {
          return PhotoViewGalleryPageOptions.customChild(
            child: const SizedBox(),
          );
        }
        precacheComicImage(
          state,
          logic,
          context,
          index * 2 + 1,
          target,
          readingData,
        );

        logic.photoViewControllers[index] ??= PhotoViewController();

        int firstImage = index * 2 - 2;
        if (firstImage % 2 != 0) {
          firstImage++;
        }
        if (logic.singlePageForFirstScreen) {
          firstImage--;
        }
        var images = <int>[firstImage, firstImage + 1];
        if (state.readingMethod == ReadingMethod.twoPageReversed) {
          images = images.reversed.toList();
        }

        return PhotoViewGalleryPageOptions.customChild(
          controller: logic.photoViewControllers[index],
          child: Row(
            children: [
              Expanded(
                child: _buildComicImageOrEmpty(
                  imageIndex: images[0],
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                ),
              ),
              Expanded(
                child: _buildComicImageOrEmpty(
                  imageIndex: images[1],
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
              ),
            ],
          ),
        );
      },
      pageController: logic.pageController,
      onPageChanged: (i) {
        if (i == 0) {
          if (!readingData.hasEp || state.currentEpisode == 1) {
            logic.pageController.jumpByDeviceType(1, logic);
            return;
          }
          logic.jumpToLastChapter();
        } else if (i == calcItemCount() - 1) {
          if (!readingData.hasEp ||
              state.currentEpisode == readingData.eps?.length) {
            logic.pageController.jumpByDeviceType(
              logic.pageController.page!.round() - 1,
              logic,
            );
            return;
          }
          logic.jumpToNextChapter();
        } else {
          final newPage = logic.singlePageForFirstScreen
              ? (i * 2 - 2).clamp(1, state.urls.length)
              : i * 2 - 1;
          logic.setCurrentPage(newPage);
          logic.notifyIndexChange(newPage);
        }
      },
    );
  }

  /// 处理滚轮方向与连续阅读边界。
  void _onPointerSignal(PointerSignalEvent pointerSignal) {
    logic.internalMouseScroll = pointerSignal.kind == PointerDeviceKind.mouse;
    if (pointerSignal is PointerScrollEvent && !logic.isCtrlPressed) {
      logic.wheelScroll();
      if (state.readingMethod != ReadingMethod.topToBottomContinuously) {
        pointerSignal.scrollDelta.dy > 0
            ? logic.jumpToNextPage()
            : logic.jumpToLastPage();
      } else {
        if (!logic.continuousReading &&
            ((logic.scrollController.position.pixels ==
                        logic.scrollController.position.minScrollExtent &&
                    pointerSignal.scrollDelta.dy < 0) ||
                (logic.scrollController.position.pixels ==
                        logic.scrollController.position.maxScrollExtent &&
                    pointerSignal.scrollDelta.dy > 0))) {
          logic.photoViewController.updateMultiple(
            position:
                logic.photoViewController.position -
                Offset(0, pointerSignal.scrollDelta.dy),
          );
        } else if (!App.isMacOS) {
          logic.scrollController.smoothTo(pointerSignal.scrollDelta.dy);
        }
      }
    }
  }

  /// 处理滚动进度、预加载和自动翻页的暂停恢复。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      logic.pauseAutoPageTurning();
    }
    if (notification is ScrollUpdateNotification) {
      TapController.lastScrollTime = DateTime.now();

      if (state.readingMethod == ReadingMethod.topToBottomContinuously &&
          logic.scrollController.hasClients) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final position = logic.scrollController.position.pixels;

        logic.scrollRecords.add(PageScrollRecord(position, now));

        if (logic.scrollRecords.length > 3) {
          logic.scrollRecords.removeAt(0);
        }
      }

      if (logic.continuousReading) {
        logic.continuousScrollUpdate(notification.scrollDelta);
        return false;
      }
      var length = readingData.eps?.length ?? 1;
      if (!logic.scrollController.hasClients) return false;
      if (logic.scrollController.position.pixels -
                  logic.scrollController.position.minScrollExtent <=
              0 &&
          state.currentEpisode != 0) {
        logic.showFloatingButton(-1);
      } else if (logic.scrollController.position.pixels -
                  logic.scrollController.position.maxScrollExtent >=
              0 &&
          state.currentEpisode < length) {
        logic.showFloatingButton(1);
      } else {
        logic.showFloatingButton(0);
      }

      return true;
    }
    if (notification is ScrollEndNotification) {
      if (logic.continuousReading) logic.continuousScrollEnd();
      if (state.readingMethod == ReadingMethod.topToBottomContinuously) {
        Log.d(
          () =>
              "ScrollEndNotification releaseVelocity: ${logic.releaseVelocity}",
        );

        if (logic.releaseVelocity != null) {
          final velocity = logic.releaseVelocity!;
          const velocityThreshold = 500.0;

          if (velocity > velocityThreshold && !state.runningAutoPageTurning) {
            Future.microtask(() => logic.startAutoPageTurning());
            Log.d(() => "启动自动翻页 (velocity: $velocity)");
          } else if (velocity < -velocityThreshold &&
              state.runningAutoPageTurning) {
            Future.microtask(() => logic.stopAutoPageTurning());
            Log.d(() => "关闭自动翻页 (velocity: $velocity)");
          }

          logic.releaseVelocity = null;
        }

        logic.scrollRecords.clear();
      }
      logic.resumeAutoPageTurning();
    }
    return false;
  }
}

/// Create an image provider for the given page.
ImageProvider createImageProvider(
  ReaderPageState state,
  int index,
  String target,
  ReadingData readingData,
) {
  return readingData.createImageProvider(
    state.currentEpisode,
    index,
    state.urls[index],
  );
}

/// Check current location of [PageView], update location when it is out of range.
bool updateLocation(BuildContext context, PhotoViewController controller) {
  final width = MediaQuery.of(context).size.width;
  final height = MediaQuery.of(context).size.height;
  if (width / height < 1.2) {
    return false;
  }
  final currentLocation = controller.position;
  final scale = controller.scale ?? 1;
  final imageWidth = height / 1.2;
  final showWidth = width / scale;
  if (showWidth >= imageWidth && currentLocation.dx != 0) {
    controller.updateMultiple(
      position: Offset(controller.initial.position.dx, currentLocation.dy),
    );
    return true;
  }
  if (showWidth < imageWidth) {
    final lEdge = (width - imageWidth) / 2;
    final rEdge = width - lEdge;
    final showLEdge =
        (0 - currentLocation.dx) / scale - showWidth / 2 + width / 2;
    final showREdge =
        (0 - currentLocation.dx) / scale + showWidth / 2 + width / 2;
    final updateValue = (width / 2 - (rEdge - showWidth / 2)) * scale;
    if (lEdge > showLEdge) {
      controller.updateMultiple(
        position: Offset(0 - updateValue, currentLocation.dy),
      );
      return true;
    } else if (rEdge < showREdge) {
      controller.updateMultiple(
        position: Offset(updateValue, currentLocation.dy),
      );
      return true;
    }
  }
  return false;
}

/// Preload images.
void precacheComicImage(
  ReaderPageState state,
  ComicReaderLogic logic,
  BuildContext context,
  int index,
  String target,
  ReadingData readingData,
) {
  logic.loadImageSizes(index);
  if (logic.requestedLoadingItems.length != logic.length) {
    logic.requestedLoadingItems = List.filled(logic.length + 1, false);
  }
  int precacheNum = logic.readerSettings.preloadPages + index;
  for (; index < precacheNum; index++) {
    if (index >= state.urls.length || logic.requestedLoadingItems[index]) {
      return;
    }
    precacheImage(
      createImageProvider(state, index, target, readingData),
      context,
    );
  }
  if (!ImageManager.haveTask) {
    precacheNum += 3;
    for (; index < precacheNum; index++) {
      if (index >= state.urls.length || logic.requestedLoadingItems[index]) {
        return;
      }
      precacheImage(
        createImageProvider(state, index, target, readingData),
        context,
      );
    }
  }
}

/// 图片预加载按条目自身章节定位，并沿实际滚动方向跨越分隔条。
void precacheContinuousImages(
  ReaderPageState state,
  ComicReaderLogic logic,
  BuildContext context,
  int index,
  ReadingData readingData,
) {
  final count = logic.readerSettings.preloadPages;
  final candidates = <ReaderItem>[];
  var cursor = index;
  while (cursor >= 0 &&
      cursor < state.readingItems.length &&
      candidates.length <= count) {
    final item = state.readingItems[cursor];
    if (item.isImage) candidates.add(item);
    cursor += logic.preloadDirection;
  }
  logic.loadImageSizesForUrls(candidates.map((item) => item.url).toList());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted || logic.isDispose || !logic.continuousReading) return;
    for (final item in candidates) {
      final key = '${item.identity}:${item.url}';
      if (!logic.requestedImageKeys.add(key)) continue;
      precacheImage(
        readingData.createImageProvider(item.episode, item.page, item.url),
        context,
        onError: (_, _) => logic.requestedImageKeys.remove(key),
      );
    }
  });
}

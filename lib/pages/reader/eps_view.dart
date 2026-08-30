import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/scrollable_list/src/scrollable_positioned_list.dart';
import '../../foundation/app.dart';
import '../../foundation/state_controller.dart';
import '../../foundation/theme/app_mouse_cursor.dart';
import '../../foundation/def.dart';
import '../../tools/translations.dart';
import '../jm/jm_comments_page.dart';
import 'reader_logic.dart';
import 'reading_data.dart';
import 'reading_type.dart';

class EpsView extends ConsumerStatefulWidget {
  const EpsView(this.data, this.sessionId, {Key? key}) : super(key: key);
  final ReadingData data;
  final String sessionId;

  @override
  ConsumerState<EpsView> createState() => _EpsViewState();
}

class _EpsViewState extends ConsumerState<EpsView> {
  var controller = ItemScrollController();
  var value = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comicReaderLogicProvider(widget.sessionId));
    final logic = ref.read(comicReaderLogicProvider(widget.sessionId).notifier);
    var type = widget.data.type;
    var data = widget.data;
    var epsWidgets = <Widget>[];

    return Container(
      constraints: const BoxConstraints(
        maxHeight: 500,
        minHeight: 200,
        maxWidth: 600,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(
                  Icons.format_list_numbered,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text("章节".tl, style: const TextStyle(fontSize: 18)),
                const Spacer(),
                if (type == ReadingType.jm)
                  IconButton(
                    icon: Icon(
                      Icons.comment_outlined,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    onPressed: () {
                      showComments(
                        context,
                        data.eps!.keys.elementAt(state.currentEpisode - 1),
                        (logic.readingData as JmReadingData).commentsLength ??
                            9999,
                      );
                    },
                  ),
                IconButton(
                  icon: Icon(
                    Icons.my_location_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 23,
                  ),
                  onPressed: () {
                    var length = data.eps!.length;
                    if (!value) {
                      controller.jumpTo(index: state.currentEpisode - 1);
                    } else {
                      controller.jumpTo(index: length - state.currentEpisode);
                    }
                  },
                ),
                Text(" 倒序".tl),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: value,
                    onChanged: (b) => setState(() {
                      value = !value;
                    }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: state.currentEpisode - 1,
              itemCount: data.eps!.length,
              itemBuilder: (context, index) {
                if (value) {
                  index = data.eps!.length - index - 1;
                }
                String title = data.eps!.values.elementAt(index);

                return InkWell(
                  mouseCursor: appClickableMouseCursor,
                  onTap: () {
                    Navigator.pop(App.globalContext!);
                    logic.jumpToChapter(index + 1);
                  },
                  child: SizedBox(
                    height: 60,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        if (data.downloadedEps.contains(index))
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(5),
                              ),
                            ),
                            margin: const EdgeInsets.all(5),
                            padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
                            child: Text(
                              "已下载".tl,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (state.currentEpisode == index + 1)
                          Container(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(5),
                              ),
                            ),
                            margin: const EdgeInsets.all(5),
                            padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
                            child: Text(
                              "当前".tl,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              scrollController: ScrollController(),
              itemScrollController: controller,
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

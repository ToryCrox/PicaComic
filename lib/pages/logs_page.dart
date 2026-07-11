import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/io_tools.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  @override
  Widget build(BuildContext context) {
    final logs = logMemoryOut.buffer.toList();
    final colorSchema = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Logs"),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              final RelativeRect position = RelativeRect.fromLTRB(
                MediaQuery.of(context).size.width,
                MediaQuery.of(context).padding.top + kToolbarHeight,
                0.0,
                0.0,
              );
              showMenu(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(
                    child: Text("清空".tl),
                    onTap: () => setState(() => LogManager.clear()),
                  ),
                  PopupMenuItem(
                    child: Text("禁用长度限制".tl),
                    onTap: () {
                      LogManager.ignoreLimitation = true;
                      showToast(message: "仅在本次运行时有效".tl);
                    },
                  ),
                  PopupMenuItem(
                    child: Text("导出".tl),
                    onTap: () => saveLog(LogManager().toString()),
                  ),
                ],
              );
            }),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: ListView.builder(
        reverse: true,
        controller: ScrollController(),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          index = logs.length - index - 1;
          final logItem = logs[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Container(
                      //   decoration: BoxDecoration(
                      //     color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      //     borderRadius: const BorderRadius.all(Radius.circular(16)),
                      //   ),
                      //   child: Padding(
                      //     padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                      //     child: Text(LogManager.logs[index].title),
                      //   ),
                      // ),
                      const SizedBox(width: 3),
                      Container(
                        decoration: BoxDecoration(
                          color:
                              {
                                Level.error: colorSchema.error,
                                Level.warning: colorSchema.errorContainer,
                                Level.debug: colorSchema.primaryContainer,
                              }[logItem.level] ??
                              colorSchema.primaryContainer,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(16),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 0, 5, 1),
                          child: Text(
                            logItem.level.name,
                            style: TextStyle(
                              color: logItem.level == Level.error
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  //Text(LogManager.logs[index].content),
                  for (final line in logItem.lines) Text(line),
                  Text(
                    logItem.origin.time.toString().replaceAll(
                      RegExp(r"\.\w+"),
                      "",
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: logItem.lines.join('\n')),
                      );
                    },
                    child: Text("复制".tl),
                  ),
                  const Divider(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

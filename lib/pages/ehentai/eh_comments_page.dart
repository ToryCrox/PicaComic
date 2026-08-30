import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/theme/app_mouse_cursor.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pica_comic/foundation/pica_image_manager.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/app_links.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'eh_comments_page_logic.dart';

export 'eh_comments_page_logic.dart';

class _EhCommentWidget extends StatefulWidget {
  const _EhCommentWidget({
    required this.comment,
    required this.uploader,
    required this.onVote,
  });

  final Comment comment;

  final String uploader;

  final Future<Res<int>> Function(bool isUp) onVote;

  @override
  State<_EhCommentWidget> createState() => _EhCommentWidgetState();
}

class _EhCommentWidgetState extends State<_EhCommentWidget> {
  Comment get comment => widget.comment;

  String get uploader => widget.uploader;

  bool isVoteUp = false;

  bool isVoteDown = false;

  void voteUp() async {
    if (isVoteUp || isVoteDown) {
      return;
    }
    setState(() {
      isVoteUp = true;
    });
    var res = await widget.onVote(true);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        isVoteUp = false;
      });
    } else {
      setState(() {
        isVoteUp = false;
      });
      showToast(message: res.errorMessageWithoutNull);
    }
  }

  void voteDown() async {
    if (isVoteUp || isVoteDown) {
      return;
    }
    setState(() {
      isVoteDown = true;
    });
    var res = await widget.onVote(false);
    if (!mounted) return;
    if (res.success) {
      setState(() {
        isVoteDown = false;
      });
    } else {
      setState(() {
        isVoteDown = false;
      });
      showToast(message: res.errorMessageWithoutNull);
    }
  }

  @override
  Widget build(BuildContext context) {
    var upColor = context.colorScheme.outline;
    bool darkMode = context.colorScheme.brightness == Brightness.dark;
    if (comment.voteUP == true) {
      upColor = darkMode ? Colors.red.shade200 : Colors.red.shade600;
    }
    var downColor = context.colorScheme.outline;
    if (comment.voteUP == false) {
      downColor = darkMode ? Colors.blue.shade200 : Colors.blue.shade600;
    }

    var isUploader = uploader == comment.name;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      elevation: 0,
      color: isUploader
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "${isUploader ? "(上传者)" : ""}${comment.name}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  TimeExtension.parseEhTime(comment.time).toCompareString,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _EhComment(comment.content),
            const SizedBox(height: 4),
            if (comment.id != "0")
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Button.icon(
                        isLoading: isVoteUp,
                        icon: const Icon(Icons.arrow_upward),
                        size: 18,
                        color: upColor,
                        onPressed: voteUp,
                      ),
                      const SizedBox(width: 4),
                      Text(comment.score.toString()),
                      const SizedBox(width: 4),
                      Button.icon(
                        isLoading: isVoteDown,
                        icon: const Icon(Icons.arrow_downward),
                        size: 18,
                        color: downColor,
                        onPressed: voteDown,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CommentsPage extends ConsumerStatefulWidget {
  const CommentsPage(this.url, this.uploader, this.auth, {super.key});

  final String url;
  final String uploader;
  final Map<String, String> auth;

  @override
  ConsumerState<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends ConsumerState<CommentsPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ehCommentsProvider(widget.url);
    final pageState = ref.watch(provider);
    final logic = ref.read(provider.notifier);
    final body = pageState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => NetworkError(
        message: _errorMessage(error),
        retry: () => ref.invalidate(provider),
        withAppbar: false,
      ),
      data: (data) => Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    childCount: data.comments.length,
                    (context, index) {
                      final comment = data.comments[index];
                      return _EhCommentWidget(
                        comment: comment,
                        uploader: widget.uploader,
                        onVote: (isUp) =>
                            logic.voteComment(widget.auth, comment.id, isUp),
                      );
                    },
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(App.globalContext!).padding.bottom,
                  ),
                ),
              ],
            ),
          ),
          _buildBottom(context, data, logic),
        ],
      ),
    );

    return body;
  }

  Widget _buildBottom(
    BuildContext context,
    EhCommentsState state,
    EhComments logic,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        child: Material(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withAlpha(160),
              borderRadius: const BorderRadius.all(Radius.circular(30)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: "评论".tl,
                      ),
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                state.sending
                    ? const Padding(
                        padding: EdgeInsets.all(8.5),
                        child: SizedBox(
                          width: 23,
                          height: 23,
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : IconButton(
                        onPressed: () => _sendComment(logic),
                        icon: Icon(
                          Icons.send,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendComment(EhComments logic) async {
    final content = _controller.text;
    if (content.isEmpty) {
      showToast(message: "请输入评论".tl);
      return;
    }
    final res = await logic.sendComment(content);
    if (!mounted) return;
    if (res.success) {
      _controller.clear();
    } else {
      showToast(message: res.errorMessageWithoutNull);
    }
  }

  String _errorMessage(Object error) {
    if (error is EhCommentsException) return error.message;
    return "网络错误".tl;
  }
}

void showComments(
  BuildContext context,
  String url,
  String uploader,
  Map<String, String> auth,
) {
  showSideBar(context, CommentsPage(url, uploader, auth), title: "评论".tl);
}

class _EhComment extends StatelessWidget {
  const _EhComment(this.html);

  final String html;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(child: Column(children: _parse(html).toList()));
  }

  void onLink(String link) {
    if (canHandle(link)) {
      App.globalBack();
      handleAppLinks(Uri.parse(link));
    } else {
      launchUrlString(link);
    }
  }

  Iterable<Widget> _parse(String html) sync* {
    html = html.replaceAll("\r\n", "\n");
    html = html.replaceAll("<br>", "\n");
    var lines = html.split("\n");
    for (var line in lines) {
      yield SizedBox(width: double.infinity, child: _buildLine(line));
    }
  }

  TextStyle _mergeStyleByTagName(TextStyle style, String tagName) {
    var richTextStyle = RichTextStyle.defaultStyle;
    switch (tagName) {
      case 'strong':
        style = style.merge(richTextStyle.strong!);
      case 'em':
        style = style.merge(richTextStyle.em!);
      case 'h1':
        style = style.merge(richTextStyle.h1!);
      case 'h2':
        style = style.merge(richTextStyle.h2!);
      case 'h3':
        style = style.merge(richTextStyle.h3!);
      case 'h4':
        style = style.merge(richTextStyle.h4!);
      case 'h5':
        style = style.merge(richTextStyle.h5!);
      case 'h6':
        style = style.merge(richTextStyle.h6!);
      default:
        style = style.merge(richTextStyle.paragraph!);
    }
    return style;
  }

  Widget _buildLine(String htmlText) {
    htmlText = htmlText.replaceAll('\n', '');
    var html = html_parser.parseFragment(htmlText);

    var widgets = <Widget>[];

    List<TextSpan> spans = [];

    void parse(
      dom.Node node,
      TextStyle style, [
      TapGestureRecognizer? recognizer,
    ]) {
      if (node is dom.Element) {
        if (node.localName == 'a') {
          recognizer = TapGestureRecognizer()
            ..onTap = () {
              onLink(node.attributes['href']!);
            };
        } else if (node.localName == 'img') {
          widgets.add(Text.rich(TextSpan(children: spans)));
          spans = [];
          Widget widget = Image(
            image: CachedNetworkImageProvider(
              node.attributes['src']!,
              cacheManager: picaImageManager,
            ),
          );
          if (recognizer != null) {
            widget = MouseRegion(
              cursor: appClickableMouseCursor,
              child: GestureDetector(onTap: recognizer.onTap, child: widget),
            );
          }
          widgets.add(widget);
        } else {
          style = _mergeStyleByTagName(style, node.localName ?? '');
        }
        for (var child in node.nodes) {
          parse(child, style, recognizer);
        }
      } else if (node is dom.Text) {
        var text = node.text;
        var splits = text.split(' ');
        String buffer = '';
        for (var part in splits) {
          if (part.isURL) {
            if (buffer.isNotEmpty) {
              spans.add(TextSpan(text: buffer, style: style));
              buffer = '';
            }
            spans.add(
              TextSpan(
                text: part,
                style: style.copyWith(
                  color: RichTextStyle.defaultStyle.link!.color,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    onLink(part);
                  },
              ),
            );
          } else {
            buffer += '$part ';
          }
        }
        if (buffer.isNotEmpty) {
          spans.add(TextSpan(text: buffer, style: style));
        }
      }
    }

    for (var node in html.nodes) {
      parse(node, const TextStyle());
    }

    if (spans.isNotEmpty) {
      widgets.add(Text.rich(TextSpan(children: spans)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class RichTextStyle {
  final TextStyle? h1;
  final TextStyle? h2;
  final TextStyle? h3;
  final TextStyle? h4;
  final TextStyle? h5;
  final TextStyle? h6;
  final TextStyle? paragraph;
  final TextStyle? link;
  final TextStyle? strong;
  final TextStyle? em;
  final Color? contentColor;

  const RichTextStyle._({
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.h5,
    required this.h6,
    required this.paragraph,
    required this.link,
    required this.strong,
    required this.em,
  }) : contentColor = null;

  static const RichTextStyle defaultStyle = RichTextStyle._(
    h1: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    h2: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    h3: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
    h4: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    h5: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    h6: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    paragraph: TextStyle(
      fontSize: 16,
      wordSpacing: 1,
      letterSpacing: 0.2,
      height: 1.2,
      color: Color.fromARGB(255, 0, 0, 0),
    ),
    link: TextStyle(color: Color.fromARGB(255, 0, 140, 255)),
    strong: TextStyle(fontWeight: FontWeight.bold),
    em: TextStyle(fontStyle: FontStyle.italic),
  );
}

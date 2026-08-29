import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/comment.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/tools/translations.dart';

import 'jm_comments_page_logic.dart';

export 'jm_comments_page_logic.dart';

/// JM 评论页面。
class JmCommentsPage extends ConsumerStatefulWidget {
  const JmCommentsPage(
    this.id,
    this.totalComments, {
    this.mode,
    this.popUp = false,
    Key? key,
  }) : super(key: key);

  final String id;
  final bool popUp;
  final String? mode;
  final int totalComments;

  @override
  ConsumerState<JmCommentsPage> createState() => _JmCommentsPageState();
}

class _JmCommentsPageState extends ConsumerState<JmCommentsPage> {
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
    final provider = jmCommentsProvider((widget.id, widget.totalComments));
    final pageState = ref.watch(provider);
    final logic = ref.read(provider.notifier);
    final body = pageState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => NetworkError(
        message: _errorMessage(error),
        retry: () => ref.invalidate(provider),
      ),
      data: (data) => _buildContent(context, data, logic),
    );

    if (widget.popUp) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: Text("评论".tl)),
      body: body,
    );
  }

  Widget _buildContent(
    BuildContext context,
    JmCommentsState state,
    JmComments logic,
  ) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: state.comments.length,
                  (context, index) {
                    if (index == state.comments.length - 1) {
                      _scheduleLoadMore(logic);
                    }
                    final comment = state.comments[index];
                    return CommentTile(
                      avatarUrl: comment.avatar,
                      name: comment.name,
                      content: comment.content,
                      comments: comment.reply.length,
                      onTap: () => showReply(context, comment.reply, comment),
                      time: comment.time,
                    );
                  },
                ),
              ),
              if (state.totalComments > state.comments.length)
                const SliverToBoxAdapter(child: ListLoadingIndicator()),
              SliverPadding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(App.globalContext!).padding.bottom,
                ),
              ),
            ],
          ),
        ),
        _buildBottom(context, state, logic),
      ],
    );
  }

  void _scheduleLoadMore(JmComments logic) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(logic.loadMore());
    });
  }

  Widget _buildBottom(
    BuildContext context,
    JmCommentsState state,
    JmComments logic,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceTint.withAlpha(0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
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
    );
  }

  Future<void> _sendComment(JmComments logic) async {
    showToast(message: "正在发送评论".tl);
    final res = await logic.sendComment(_controller.text);
    if (!mounted) return;
    if (res.error) {
      showToast(message: res.errorMessageWithoutNull);
    } else {
      showToast(message: "成功发表评论".tl);
      _controller.clear();
    }
  }

  String _errorMessage(Object error) {
    if (error is JmCommentsException) return error.message;
    return "网络错误".tl;
  }
}

void showReply(BuildContext context, List<Comment> comments, Comment replyTo) {
  if (comments.isEmpty) return;
  showSideBar(
    context,
    SingleChildScrollView(
      child: Column(
        children: [
          CommentTile(
            avatarUrl: replyTo.avatar,
            name: replyTo.name,
            content: replyTo.content,
            time: replyTo.time,
          ),
          const Divider(),
          for (int index = 0; index < comments.length; index++)
            CommentTile(
              avatarUrl: comments[index].avatar,
              name: comments[index].name,
              content: comments[index].content,
              time: comments[index].time,
            ),
        ],
      ),
    ),
    title: "回复".tl,
    showBarrier: false,
  );
}

void showComments(
  BuildContext context,
  String id,
  int totalComments, [
  String? mode,
]) {
  showSideBar(
    context,
    JmCommentsPage(id, totalComments, popUp: true, mode: mode),
    title: "评论".tl,
  );
}

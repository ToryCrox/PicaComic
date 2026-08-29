import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/components/comment.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/tools/translations.dart';

import 'comments_page_logic.dart';

export 'comments_page_logic.dart';

/// PicaCG 评论页面。
class CommentsPage extends ConsumerStatefulWidget {
  const CommentsPage(
    this.id, {
    Key? key,
    this.type = "comics",
    this.popUp = false,
  }) : super(key: key);

  final String id;
  final String type;
  final bool popUp;

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
    final provider = picacgCommentsProvider((widget.id, widget.type));
    final pageState = ref.watch(provider);
    final logic = ref.read(provider.notifier);
    final body = pageState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => NetworkError(
        message: _errorMessage(error),
        retry: () => ref.invalidate(provider),
        withAppbar: false,
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
    PicacgCommentsState state,
    PicacgComments logic,
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
                    final subInfo =
                        "${comment.time.substring(0, 10)}  ${comment.time.substring(11, 19)}";
                    return CommentTile(
                      avatarUrl: comment.avatarUrl,
                      name: comment.name,
                      content: comment.text,
                      slogan: comment.slogan,
                      level: comment.level,
                      time: subInfo,
                      like: () => logic.toggleLike(comment.id),
                      likes: comment.likes,
                      liked: comment.isLiked,
                      comments: comment.reply,
                      onTap: () => showReply(context, comment.id, comment),
                    );
                  },
                ),
              ),
              if (state.loaded < state.pages && state.pages != 1)
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

  void _scheduleLoadMore(PicacgComments logic) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(logic.loadMore());
    });
  }

  Widget _buildBottom(
    BuildContext context,
    PicacgCommentsState state,
    PicacgComments logic,
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

  Future<void> _sendComment(PicacgComments logic) async {
    final content = _controller.text;
    if (content.length < 2) {
      showToast(message: "评论至少需要2个字".tl);
      return;
    }
    final success = await logic.sendComment(content);
    if (!mounted) return;
    if (success) {
      _controller.clear();
    } else {
      showToast(message: "网络错误".tl);
    }
  }

  String _errorMessage(Object error) {
    if (error is PicacgCommentsException) return error.message.tl;
    return "网络错误".tl;
  }
}

/// PicaCG 回复页面。
class ReplyPage extends ConsumerStatefulWidget {
  const ReplyPage(this.id, this.replyTo, {this.popUp = false, Key? key})
    : super(key: key);

  final String id;
  final Comment replyTo;
  final bool popUp;

  @override
  ConsumerState<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends ConsumerState<ReplyPage> {
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
    final provider = picacgReplyProvider(widget.id);
    final pageState = ref.watch(provider);
    final logic = ref.read(provider.notifier);
    final body = pageState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => NetworkError(
        message: _errorMessage(error),
        retry: () => ref.invalidate(provider),
        withAppbar: false,
      ),
      data: (data) => _buildContent(context, data, logic),
    );

    if (widget.popUp) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: Text("回复".tl)),
      body: body,
    );
  }

  Widget _buildContent(
    BuildContext context,
    PicacgReplyState state,
    PicacgReply logic,
  ) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CommentTile(
                  avatarUrl: widget.replyTo.avatarUrl,
                  name: widget.replyTo.name,
                  content: widget.replyTo.text,
                  time:
                      "${widget.replyTo.time.substring(0, 10)}  ${widget.replyTo.time.substring(11, 19)}",
                  slogan: widget.replyTo.slogan,
                  level: widget.replyTo.level,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.all(2)),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Divider(),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  childCount: state.comments.length,
                  (context, index) {
                    if (index == state.comments.length - 1) {
                      _scheduleLoadMore(logic);
                    }
                    final comment = state.comments[index];
                    final subInfo =
                        "${comment.time.substring(0, 10)}  ${comment.time.substring(11, 19)}";
                    return CommentTile(
                      avatarUrl: comment.avatarUrl,
                      name: comment.name,
                      content: comment.text,
                      slogan: comment.slogan,
                      level: comment.level,
                      time: subInfo,
                      like: () => logic.toggleLike(comment.id),
                      likes: comment.likes,
                      liked: comment.isLiked,
                    );
                  },
                ),
              ),
              if (state.loaded < state.total && state.total != 1)
                const SliverToBoxAdapter(child: ListLoadingIndicator()),
              SliverPadding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(App.globalContext!).padding.bottom,
                ),
              ),
            ],
          ),
        ),
        _buildReplyBottom(context, state, logic),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
        ),
      ],
    );
  }

  void _scheduleLoadMore(PicacgReply logic) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(logic.loadMore());
    });
  }

  Widget _buildReplyBottom(
    BuildContext context,
    PicacgReplyState state,
    PicacgReply logic,
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
                        hintText: "回复".tl,
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
                        onPressed: () => _sendReply(logic),
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

  Future<void> _sendReply(PicacgReply logic) async {
    final content = _controller.text;
    if (content.length < 2) {
      showToast(message: "评论至少需要2个字".tl);
      return;
    }
    final success = await logic.sendReply(content);
    if (!mounted) return;
    if (success) {
      _controller.clear();
    } else {
      showToast(message: "网络错误".tl);
    }
  }

  String _errorMessage(Object error) {
    if (error is PicacgCommentsException) return error.message.tl;
    return "网络错误".tl;
  }
}

void showComments(BuildContext context, String id) {
  showSideBar(context, CommentsPage(id, popUp: true), title: "评论".tl);
}

void showReply(BuildContext context, String id, Comment replyTo) {
  showSideBar(
    context,
    ReplyPage(id, replyTo, popUp: true),
    title: "回复".tl,
    showBarrier: false,
  );
}

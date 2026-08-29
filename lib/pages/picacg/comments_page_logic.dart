import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/network/res.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'comments_page_logic.g.dart';

Duration? _noRetry(int _, Object __) => null;

/// PicaCG 评论网络仓库。
abstract interface class PicacgCommentsRepository {
  /// 获取评论列表。
  Future<Comments> getComments(String id, {required String type});

  /// 加载下一页评论。
  Future<Res<bool>> loadMoreComments(Comments comments, {required String type});

  /// 获取回复列表。
  Future<Reply> getReplies(String id);

  /// 加载下一页回复。
  Future<void> loadMoreReplies(Reply replies);

  /// 切换评论点赞状态。
  Future<bool> toggleLike(String commentId);

  /// 发送评论或回复。
  Future<bool> sendComment(
    String id,
    String text,
    bool isReply, {
    String type = "comics",
  });
}

class _PicacgCommentsRepository implements PicacgCommentsRepository {
  @override
  Future<Comments> getComments(String id, {required String type}) {
    return network.getCommends(id, type: type);
  }

  @override
  Future<Res<bool>> loadMoreComments(
    Comments comments, {
    required String type,
  }) {
    return network.loadMoreCommends(comments, type: type);
  }

  @override
  Future<Reply> getReplies(String id) => network.getReply(id);

  @override
  Future<void> loadMoreReplies(Reply replies) => network.getMoreReply(replies);

  @override
  Future<bool> toggleLike(String commentId) {
    return network.likeOrUnlikeComment(commentId);
  }

  @override
  Future<bool> sendComment(
    String id,
    String text,
    bool isReply, {
    String type = "comics",
  }) {
    return network.comment(id, text, isReply, type: type);
  }
}

/// PicaCG 评论网络仓库 Provider，默认使用现有网络实现。
final picacgCommentsRepositoryProvider = Provider<PicacgCommentsRepository>(
  (ref) => _PicacgCommentsRepository(),
);

/// PicaCG 评论加载异常。
class PicacgCommentsException implements Exception {
  const PicacgCommentsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// PicaCG 评论列表状态。
class PicacgCommentsState {
  const PicacgCommentsState({
    required this.comments,
    required this.pages,
    required this.loaded,
    this.loadingMore = false,
    this.sending = false,
  });

  final List<Comment> comments;
  final int pages;
  final int loaded;
  final bool loadingMore;
  final bool sending;

  /// 创建更新后的评论状态。
  PicacgCommentsState copyWith({
    List<Comment>? comments,
    int? pages,
    int? loaded,
    bool? loadingMore,
    bool? sending,
  }) {
    return PicacgCommentsState(
      comments: comments ?? this.comments,
      pages: pages ?? this.pages,
      loaded: loaded ?? this.loaded,
      loadingMore: loadingMore ?? this.loadingMore,
      sending: sending ?? this.sending,
    );
  }
}

/// PicaCG 回复列表状态。
class PicacgReplyState {
  const PicacgReplyState({
    required this.comments,
    required this.total,
    required this.loaded,
    this.loadingMore = false,
    this.sending = false,
  });

  final List<Comment> comments;
  final int total;
  final int loaded;
  final bool loadingMore;
  final bool sending;

  /// 创建更新后的回复状态。
  PicacgReplyState copyWith({
    List<Comment>? comments,
    int? total,
    int? loaded,
    bool? loadingMore,
    bool? sending,
  }) {
    return PicacgReplyState(
      comments: comments ?? this.comments,
      total: total ?? this.total,
      loaded: loaded ?? this.loaded,
      loadingMore: loadingMore ?? this.loadingMore,
      sending: sending ?? this.sending,
    );
  }
}

/// PicaCG 评论 Provider。
@Riverpod(
  keepAlive: false,
  retry: _noRetry,
  name: 'picacgCommentsProvider',
)
class PicacgComments extends _$PicacgComments {
  late (String, String) _key;
  late PicacgCommentsRepository _repository;
  bool _loadingMore = false;
  bool _sending = false;

  @override
  Future<PicacgCommentsState> build((String id, String type) key) async {
    _key = key;
    _repository = ref.watch(picacgCommentsRepositoryProvider);
    final comments = await _repository.getComments(key.$1, type: key.$2);
    if (comments.loaded == 0) {
      throw const PicacgCommentsException('网络错误');
    }
    return PicacgCommentsState(
      comments: List.unmodifiable(comments.comments),
      pages: comments.pages,
      loaded: comments.loaded,
    );
  }

  /// 加载下一页评论。
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || _loadingMore || current.loaded >= current.pages) {
      return;
    }

    _loadingMore = true;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final data = Comments(
        List<Comment>.from(current.comments),
        _key.$1,
        current.pages,
        current.loaded,
      );
      await _repository.loadMoreComments(data, type: _key.$2);
      if (!ref.mounted) return;
      state = AsyncData(
        PicacgCommentsState(
          comments: List.unmodifiable(data.comments),
          pages: data.pages,
          loaded: data.loaded,
        ),
      );
    } catch (_) {
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(loadingMore: false));
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// 切换评论点赞状态。
  void toggleLike(String commentId) {
    final current = state.value;
    if (current == null) return;
    final comments = List<Comment>.from(current.comments);
    final index = comments.indexWhere((comment) => comment.id == commentId);
    if (index < 0) return;

    final comment = comments[index];
    comment.isLiked = !comment.isLiked;
    comment.likes += comment.isLiked ? 1 : -1;
    state = AsyncData(current.copyWith(comments: List.unmodifiable(comments)));
    unawaited(_repository.toggleLike(commentId));
  }

  /// 发送评论并重新加载评论列表。
  Future<bool> sendComment(String text) async {
    final current = state.value;
    if (current == null || _sending) return false;

    _sending = true;
    state = AsyncData(current.copyWith(sending: true));
    try {
      final success = await _repository.sendComment(
        _key.$1,
        text,
        false,
        type: _key.$2,
      );
      if (!ref.mounted) return false;
      if (!success) {
        state = AsyncData(current.copyWith(sending: false));
        return false;
      }
      ref.invalidateSelf();
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(sending: false));
      }
      return false;
    } finally {
      _sending = false;
    }
  }
}

/// PicaCG 回复 Provider。
@Riverpod(
  keepAlive: false,
  retry: _noRetry,
  name: 'picacgReplyProvider',
)
class PicacgReply extends _$PicacgReply {
  late String _id;
  late PicacgCommentsRepository _repository;
  bool _loadingMore = false;
  bool _sending = false;

  @override
  Future<PicacgReplyState> build(String id) async {
    _id = id;
    _repository = ref.watch(picacgCommentsRepositoryProvider);
    final reply = await _repository.getReplies(id);
    if (reply.loaded == 0) {
      throw const PicacgCommentsException('网络错误');
    }
    return PicacgReplyState(
      comments: List.unmodifiable(reply.comments),
      total: reply.total,
      loaded: reply.loaded,
    );
  }

  /// 加载下一页回复。
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || _loadingMore || current.loaded >= current.total) {
      return;
    }

    _loadingMore = true;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final data = Reply(
        _id,
        current.loaded,
        current.total,
        List<Comment>.from(current.comments),
      );
      await _repository.loadMoreReplies(data);
      if (!ref.mounted) return;
      state = AsyncData(
        PicacgReplyState(
          comments: List.unmodifiable(data.comments),
          total: data.total,
          loaded: data.loaded,
        ),
      );
    } catch (_) {
      if (!ref.mounted) return;
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(loadingMore: false));
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// 切换回复点赞状态。
  void toggleLike(String commentId) {
    final current = state.value;
    if (current == null) return;
    final comments = List<Comment>.from(current.comments);
    final index = comments.indexWhere((comment) => comment.id == commentId);
    if (index < 0) return;

    final comment = comments[index];
    comment.isLiked = !comment.isLiked;
    comment.likes += comment.isLiked ? 1 : -1;
    state = AsyncData(current.copyWith(comments: List.unmodifiable(comments)));
    unawaited(_repository.toggleLike(commentId));
  }

  /// 发送回复并重新加载回复列表。
  Future<bool> sendReply(String text) async {
    final current = state.value;
    if (current == null || _sending) return false;

    _sending = true;
    state = AsyncData(current.copyWith(sending: true));
    try {
      final success = await _repository.sendComment(_id, text, true);
      if (!ref.mounted) return false;
      if (!success) {
        state = AsyncData(current.copyWith(sending: false));
        return false;
      }
      ref.invalidateSelf();
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(sending: false));
      }
      return false;
    } finally {
      _sending = false;
    }
  }
}

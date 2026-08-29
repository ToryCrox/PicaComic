import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/comic_source/built_in/ehentai.dart';
import 'package:pica_comic/network/eh_network/eh_main_network.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/res.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'eh_comments_page_logic.g.dart';

Duration? _noRetry(int _, Object __) => null;

/// E-Hentai 评论网络仓库。
abstract interface class EhCommentsRepository {
  /// 获取评论。
  Future<Res<List<Comment>>> getComments(String url);

  /// 发送评论。
  Future<Res<bool>> sendComment(String text, String url);

  /// 投票评论。
  Future<Res<int>> voteComment(
    Map<String, String> auth,
    String commentId,
    bool isUp,
  );

  /// 当前登录用户名。
  String get currentUserName;
}

class _EhCommentsRepository implements EhCommentsRepository {
  @override
  Future<Res<List<Comment>>> getComments(String url) {
    return EhNetwork().getComments(url);
  }

  @override
  Future<Res<bool>> sendComment(String text, String url) {
    return EhNetwork().comment(text, url);
  }

  @override
  Future<Res<int>> voteComment(
    Map<String, String> auth,
    String commentId,
    bool isUp,
  ) {
    return EhNetwork().voteComment(auth, commentId, isUp);
  }

  @override
  String get currentUserName => ehentai.data['name'] ?? '';
}

/// E-Hentai 评论网络仓库 Provider，默认使用现有网络实现。
final ehCommentsRepositoryProvider = Provider<EhCommentsRepository>(
  (ref) => _EhCommentsRepository(),
);

/// E-Hentai 评论加载异常。
class EhCommentsException implements Exception {
  const EhCommentsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// E-Hentai 评论页面状态。
class EhCommentsState {
  const EhCommentsState({required this.comments, this.sending = false});

  final List<Comment> comments;
  final bool sending;

  /// 创建更新后的评论状态。
  EhCommentsState copyWith({List<Comment>? comments, bool? sending}) {
    return EhCommentsState(
      comments: comments ?? this.comments,
      sending: sending ?? this.sending,
    );
  }
}

/// E-Hentai 评论 Provider。
@Riverpod(keepAlive: false, retry: _noRetry, name: 'ehCommentsProvider')
class EhComments extends _$EhComments {
  late String _url;
  late EhCommentsRepository _repository;
  bool _sending = false;

  @override
  Future<EhCommentsState> build(String url) async {
    _url = url;
    _repository = ref.watch(ehCommentsRepositoryProvider);
    final res = await _repository.getComments(url);
    if (res.error) {
      throw EhCommentsException(res.errorMessageWithoutNull);
    }
    return EhCommentsState(comments: List.unmodifiable(res.data));
  }

  /// 投票并更新对应评论的分数和投票状态。
  Future<Res<int>> voteComment(
    Map<String, String> auth,
    String commentId,
    bool isUp,
  ) async {
    try {
      final res = await _repository.voteComment(auth, commentId, isUp);
      if (!res.success || !ref.mounted) return res;

      final current = state.value;
      if (current == null) return res;
      final comments = List<Comment>.from(current.comments);
      final index = comments.indexWhere((comment) => comment.id == commentId);
      if (index < 0) return res;

      final comment = comments[index];
      final isCancel = comment.voteUP == isUp;
      comments[index] = comment.copyWith(
        voteUP: isCancel ? null : isUp,
        clearVoteUP: isCancel,
        score: res.data,
      );
      state = AsyncData(
        current.copyWith(comments: List.unmodifiable(comments)),
      );
      return res;
    } catch (error) {
      return Res.error(error.toString());
    }
  }

  /// 发送评论并刷新评论列表。
  Future<Res<bool>> sendComment(String text) async {
    final current = state.value;
    if (current == null || _sending) {
      return const Res.error('评论正在发送');
    }

    _sending = true;
    state = AsyncData(current.copyWith(sending: true));
    try {
      final res = await _repository.sendComment(text, _url);
      if (!ref.mounted) return res;
      if (res.error) {
        state = AsyncData(current.copyWith(sending: false));
        return res;
      }
      final latest = state.value ?? current;
      final comments = List<Comment>.from(latest.comments)
        ..add(
          Comment(
            name: _repository.currentUserName,
            content: text,
            time: DateTime.now().toIso8601String(),
          ),
        );
      state = AsyncData(
        latest.copyWith(comments: List.unmodifiable(comments), sending: false),
      );
      return res;
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(sending: false));
      }
      return Res.error(error.toString());
    } finally {
      _sending = false;
    }
  }
}

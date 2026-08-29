import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pica_comic/network/jm_network/jm_models.dart';
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'jm_comments_page_logic.g.dart';

Duration? _noRetry(int _, Object __) => null;

/// JM 评论网络仓库。
abstract interface class JmCommentsRepository {
  /// 获取指定页评论。
  Future<Res<List<Comment>>> getComments(String id, int page);

  /// 发送评论。
  Future<Res<dynamic>> sendComment(String id, String text);
}

class _JmCommentsRepository implements JmCommentsRepository {
  @override
  Future<Res<List<Comment>>> getComments(String id, int page) {
    return jmNetwork.getComment(id, page);
  }

  @override
  Future<Res<dynamic>> sendComment(String id, String text) {
    return jmNetwork.comment(id, text);
  }
}

/// JM 评论网络仓库 Provider，默认使用现有网络实现。
final jmCommentsRepositoryProvider = Provider<JmCommentsRepository>(
  (ref) => _JmCommentsRepository(),
);

/// JM 评论加载异常。
class JmCommentsException implements Exception {
  const JmCommentsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// JM 评论页面状态。
class JmCommentsState {
  const JmCommentsState({
    required this.comments,
    required this.page,
    required this.totalComments,
    this.loadingMore = false,
    this.sending = false,
  });

  final List<Comment> comments;
  final int page;
  final int totalComments;
  final bool loadingMore;
  final bool sending;

  /// 创建更新后的评论状态。
  JmCommentsState copyWith({
    List<Comment>? comments,
    int? page,
    int? totalComments,
    bool? loadingMore,
    bool? sending,
  }) {
    return JmCommentsState(
      comments: comments ?? this.comments,
      page: page ?? this.page,
      totalComments: totalComments ?? this.totalComments,
      loadingMore: loadingMore ?? this.loadingMore,
      sending: sending ?? this.sending,
    );
  }
}

/// JM 评论 Provider。
@Riverpod(
  keepAlive: false,
  retry: _noRetry,
  name: 'jmCommentsProvider',
)
class JmComments extends _$JmComments {
  late (String, int) _key;
  late JmCommentsRepository _repository;
  bool _loadingMore = false;
  bool _sending = false;

  @override
  Future<JmCommentsState> build((String id, int totalComments) key) async {
    _key = key;
    _repository = ref.watch(jmCommentsRepositoryProvider);
    final res = await _repository.getComments(key.$1, 1);
    if (res.error) {
      throw JmCommentsException(res.errorMessage ?? "未知错误");
    }
    final total = _readTotal(res.subData, key.$2);
    return JmCommentsState(
      comments: List.unmodifiable(res.data),
      page: 1,
      totalComments: total,
    );
  }

  int _readTotal(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  /// 加载下一页评论。
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        _loadingMore ||
        current.comments.length >= current.totalComments) {
      return;
    }

    _loadingMore = true;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final res = await _repository.getComments(_key.$1, current.page + 1);
      if (!ref.mounted) return;
      if (res.error) {
        state = AsyncData(current.copyWith(loadingMore: false));
        return;
      }

      final comments = List<Comment>.from(current.comments)..addAll(res.data);
      state = AsyncData(
        JmCommentsState(
          comments: List.unmodifiable(comments),
          page: current.page + 1,
          totalComments: _readTotal(res.subData, current.totalComments),
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

  /// 发送评论并重新加载评论列表。
  Future<Res<dynamic>> sendComment(String text) async {
    final current = state.value;
    if (current == null || _sending) {
      return const Res.error('评论正在发送');
    }

    _sending = true;
    state = AsyncData(current.copyWith(sending: true));
    try {
      final res = await _repository.sendComment(_key.$1, text);
      if (!ref.mounted) return res;
      if (res.error) {
        state = AsyncData(current.copyWith(sending: false));
        return res;
      }
      ref.invalidateSelf();
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart' as eh;
import 'package:pica_comic/network/jm_network/jm_models.dart' as jm;
import 'package:pica_comic/network/jm_network/jm_network.dart';
import 'package:pica_comic/network/picacg_network/methods.dart' as pica;
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/ehentai/eh_comments_page.dart';
import 'package:pica_comic/pages/jm/jm_comments_page.dart';
import 'package:pica_comic/pages/jm/week_recommendation_page.dart';
import 'package:pica_comic/pages/picacg/comments_page.dart';

void main() {
  group('PicaCG 评论 Provider', () {
    test('初始加载失败会进入错误状态', () async {
      final repository = _FakePicacgRepository(
        comments: pica.Comments([], 'comic', 1, 0),
      );
      final container = ProviderContainer(
        overrides: [
          picacgCommentsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final provider = picacgCommentsProvider(('comic', 'comics'));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await expectLater(
        container.read(provider.future),
        throwsA(isA<PicacgCommentsException>()),
      );
    });

    test('重复触发加载更多只发送一个请求', () async {
      final repository = _FakePicacgRepository(
        comments: pica.Comments([_picacgComment('first')], 'comic', 2, 1),
        loadMoreCompleter: Completer<Res<bool>>(),
      );
      final container = ProviderContainer(
        overrides: [
          picacgCommentsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final provider = picacgCommentsProvider(('comic', 'comics'));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final logic = container.read(provider.notifier);

      final first = logic.loadMore();
      final duplicate = logic.loadMore();
      expect(repository.loadMoreCalls, 1);
      repository.loadMoreCompleter!.complete(const Res(true));
      await Future.wait([first, duplicate]);
      expect(container.read(provider).value!.loadingMore, isFalse);
    });

    test('发送评论成功后重新加载列表，失败恢复发送状态', () async {
      final repository = _FakePicacgRepository(
        comments: pica.Comments([_picacgComment('first')], 'comic', 1, 1),
      );
      final container = ProviderContainer(
        overrides: [
          picacgCommentsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final provider = picacgCommentsProvider(('comic', 'comics'));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final logic = container.read(provider.notifier);

      expect(await logic.sendComment('hello'), isTrue);
      await container.read(provider.future);
      expect(repository.getCommentsCalls, 2);

      repository.sendResult = false;
      expect(await logic.sendComment('failed'), isFalse);
      expect(container.read(provider).value!.sending, isFalse);
    });

    test('回复支持分页和发送', () async {
      final repository = _FakePicacgRepository(
        comments: pica.Comments([], 'comment', 1, 1),
        reply: pica.Reply('comment', 1, 2, [_picacgComment('reply')]),
      );
      final container = ProviderContainer(
        overrides: [
          picacgCommentsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final provider = picacgReplyProvider('comment');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final logic = container.read(provider.notifier);

      await logic.loadMore();
      expect(container.read(provider).value!.loaded, 2);
      expect(await logic.sendReply('reply text'), isTrue);
    });
  });

  group('EHentai 评论 Provider', () {
    test('加载、投票和发送评论都会更新 Provider 状态', () async {
      final repository = _FakeEhCommentsRepository([_ehComment('1', score: 1)]);
      final container = ProviderContainer(
        overrides: [ehCommentsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final provider = ehCommentsProvider('comments-url');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final logic = container.read(provider.notifier);

      final vote = await logic.voteComment({}, '1', true);
      expect(vote.success, isTrue);
      expect(container.read(provider).value!.comments.single.voteUP, isTrue);
      expect(container.read(provider).value!.comments.single.score, 5);

      final send = await logic.sendComment('new comment');
      expect(send.success, isTrue);
      expect(container.read(provider).value!.comments, hasLength(2));
      expect(container.read(provider).value!.sending, isFalse);
    });

    test('加载失败会保留错误原因', () async {
      final repository = _FakeEhCommentsRepository(
        const [],
        loadResult: const Res.error('request failed'),
      );
      final container = ProviderContainer(
        overrides: [ehCommentsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final provider = ehCommentsProvider('comments-url');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await expectLater(
        container.read(provider.future),
        throwsA(
          predicate<Object>(
            (error) =>
                error is EhCommentsException &&
                error.message == 'request failed',
          ),
        ),
      );
    });
  });

  group('JM 评论 Provider', () {
    test('不同漫画的 family 状态互不污染', () async {
      final repository = _FakeJmCommentsRepository({
        'one': [_jmComment('one-comment')],
        'two': [_jmComment('two-comment')],
      });
      final container = ProviderContainer(
        overrides: [jmCommentsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final one = jmCommentsProvider(('one', 1));
      final two = jmCommentsProvider(('two', 1));
      await Future.wait([
        container.read(one.future),
        container.read(two.future),
      ]);

      expect(container.read(one).value!.comments.single.content, 'one-comment');
      expect(container.read(two).value!.comments.single.content, 'two-comment');
    });

    test('分页边界和发送成功刷新均正常', () async {
      final repository = _FakeJmCommentsRepository(
        {
          'comic': [_jmComment('first')],
        },
        pageTwo: [_jmComment('second')],
      );
      final container = ProviderContainer(
        overrides: [jmCommentsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final provider = jmCommentsProvider(('comic', 2));
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      final logic = container.read(provider.notifier);

      await logic.loadMore();
      expect(repository.getCommentsCalls, 2);
      expect(container.read(provider).value!.page, 2);
      await logic.loadMore();
      expect(repository.getCommentsCalls, 2);

      expect((await logic.sendComment('new')).success, isTrue);
      await container.read(provider.future);
      expect(repository.getCommentsCalls, 3);
    });
  });

  group('JM 每周推荐 Provider', () {
    test('空推荐列表转为明确错误', () async {
      final repository = _FakeJmWeekRepository(const <String, String>{});
      final container = ProviderContainer(
        overrides: [
          jmWeekRecommendationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        jmWeekRecommendationProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await expectLater(
        container.read(jmWeekRecommendationProvider.future),
        throwsA(
          predicate<Object>(
            (error) =>
                error is JmWeekRecommendationException &&
                error.message == '暂无每周推荐',
          ),
        ),
      );
    });

    test('选择分类和漫画 family key 互相独立', () async {
      final repository = _FakeJmWeekRepository({'1': '第一周', '2': '第二周'});
      final container = ProviderContainer(
        overrides: [
          jmWeekRecommendationRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      const recommendation = jmWeekRecommendationProvider;
      final subscription = container.listen(recommendation, (_, _) {});
      addTearDown(subscription.close);
      await container.read(recommendation.future);
      container.read(recommendation.notifier).select('2');
      expect(container.read(recommendation).value!.currentId, '2');
      expect(container.read(recommendation).value!.currentName, '第二周');

      final korean = jmWeekRecommendationComicsProvider((
        '1',
        WeekRecommendationType.korean,
      ));
      final manga = jmWeekRecommendationComicsProvider((
        '2',
        WeekRecommendationType.manga,
      ));
      final results = await Future.wait([
        container.read(korean.future),
        container.read(manga.future),
      ]);
      expect(results[0].single.id, '1-korean');
      expect(results[1].single.id, '2-manga');
    });
  });
}

class _FakePicacgRepository implements PicacgCommentsRepository {
  _FakePicacgRepository({
    required this.comments,
    this.reply,
    this.loadMoreCompleter,
  });

  final pica.Comments comments;
  final pica.Reply? reply;
  final Completer<Res<bool>>? loadMoreCompleter;
  int getCommentsCalls = 0;
  int loadMoreCalls = 0;
  bool sendResult = true;

  @override
  Future<pica.Comments> getComments(String id, {required String type}) async {
    getCommentsCalls++;
    return pica.Comments(
      List.of(comments.comments),
      comments.id,
      comments.pages,
      comments.loaded,
    );
  }

  @override
  Future<Res<bool>> loadMoreComments(
    pica.Comments comments, {
    required String type,
  }) async {
    loadMoreCalls++;
    if (loadMoreCompleter != null) return loadMoreCompleter!.future;
    comments.loaded = comments.pages;
    return const Res(true);
  }

  @override
  Future<pica.Reply> getReplies(String id) async {
    return reply ?? pica.Reply(id, 1, 1, []);
  }

  @override
  Future<void> loadMoreReplies(pica.Reply replies) async {
    replies.loaded = replies.total;
  }

  @override
  Future<bool> toggleLike(String commentId) async => true;

  @override
  Future<bool> sendComment(
    String id,
    String text,
    bool isReply, {
    String type = 'comics',
  }) async => sendResult;
}

class _FakeEhCommentsRepository implements EhCommentsRepository {
  _FakeEhCommentsRepository(this.comments, {this.loadResult});

  final List<eh.Comment> comments;
  final Res<List<eh.Comment>>? loadResult;

  @override
  String get currentUserName => 'tester';

  @override
  Future<Res<List<eh.Comment>>> getComments(String url) async {
    return loadResult ?? Res(List.of(comments));
  }

  @override
  Future<Res<bool>> sendComment(String text, String url) async {
    return const Res(true);
  }

  @override
  Future<Res<int>> voteComment(
    Map<String, String> auth,
    String commentId,
    bool isUp,
  ) async => const Res(5);
}

class _FakeJmCommentsRepository implements JmCommentsRepository {
  _FakeJmCommentsRepository(this.commentsById, {this.pageTwo = const []});

  final Map<String, List<jm.Comment>> commentsById;
  final List<jm.Comment> pageTwo;
  int getCommentsCalls = 0;

  @override
  Future<Res<List<jm.Comment>>> getComments(String id, int page) async {
    getCommentsCalls++;
    final comments = page == 1 ? commentsById[id] ?? const [] : pageTwo;
    return Res(List.of(comments), subData: page == 1 ? 2 : 2);
  }

  @override
  Future<Res<dynamic>> sendComment(String id, String text) async {
    return const Res(true);
  }
}

class _FakeJmWeekRepository implements JmWeekRecommendationRepository {
  _FakeJmWeekRepository(this.recommendations);

  final Map<String, String> recommendations;

  @override
  Future<Res<Map<String, String>>> getRecommendations() async {
    return Res(Map.of(recommendations));
  }

  @override
  Future<Res<List<jm.JmComicBrief>>> getComics(
    String id,
    WeekRecommendationType type,
  ) async {
    return Res([
      jm.JmComicBrief('$id-${type.name}', 'author', 'title', '', const []),
    ]);
  }
}

pica.Comment _picacgComment(String id) {
  return pica.Comment(
    'name',
    'avatar',
    'user',
    1,
    id,
    0,
    id,
    false,
    0,
    null,
    null,
    '2026-08-29T12:00:00Z',
  );
}

eh.Comment _ehComment(String id, {int score = 0}) {
  return eh.Comment(id, 'name', id, '2026-08-29T12:00:00Z', score, null);
}

jm.Comment _jmComment(String content) {
  return jm.Comment('id-$content', 'avatar', 'name', 'time', content, []);
}

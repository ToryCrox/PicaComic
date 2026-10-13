import 'dart:async';

import '../../network/res.dart';

/// 连续阅读中的图片、章节标题或加载边界。
class ReaderItem {
  const ReaderItem.image(this.episode, this.page, this.url)
    : kind = ReaderItemKind.image,
      message = null;

  const ReaderItem.header(this.episode)
    : kind = ReaderItemKind.header,
      page = 0,
      url = '',
      message = null;

  const ReaderItem.boundary(this.episode, this.kind, [this.message])
    : page = 0,
      url = '';

  final int episode;

  /// 图片页码从零开始。
  final int page;
  final String url;
  final ReaderItemKind kind;
  final String? message;

  bool get isImage => kind == ReaderItemKind.image;

  /// 图片刷新地址时保持同一章内页的身份。
  String get identity {
    var prefix = 'boundary';
    if (isImage) {
      prefix = 'image';
    } else if (kind == ReaderItemKind.header) {
      prefix = 'header';
    }
    return '$prefix:$episode:$page';
  }
}

/// 边界状态不占用漫画页码。
enum ReaderItemKind { image, header, idle, loading, error, empty }

/// 单章的不可变加载快照。
class ReaderChapter {
  const ReaderChapter(this.urls, {this.error});
  final List<String> urls;
  final String? error;
}

/// 连续章节会话：串行预加载、合并请求并屏蔽已取消会话的结果。
class ContinuousReaderData {
  ContinuousReaderData({
    required this.episodeCount,
    required this.loadEpisode,
    required this.onChanged,
    required this.canPrepend,
    this.chapterStep = 1,
  }) : assert(chapterStep == 1 || chapterStep == -1);

  final int episodeCount;
  final int chapterStep;
  final Stream<Res<List<String>>> Function(int) loadEpisode;
  final void Function() onChanged;
  final bool Function() canPrepend;
  final chapters = <int, ReaderChapter>{};
  final _attached = <int>{};
  final _requests = <int, Completer<void>>{};
  final _queue = <int>[];
  final _deferred = <int>{};
  final _skipped = <int>{};
  bool _pumping = false;
  bool _disposed = false;
  StreamSubscription<Res<List<String>>>? _subscription;
  Completer<void>? _streamCompletion;

  int get firstEpisode =>
      _attached.reduce((a, b) => _compareEpisodes(a, b) < 0 ? a : b);
  int get lastEpisode =>
      _attached.reduce((a, b) => _compareEpisodes(a, b) > 0 ? a : b);

  /// 首尾相邻章节沿阅读方向查找，目录索引可以递增或递减。
  int? get previousEpisode =>
      _attached.isEmpty ? null : _adjacentEpisode(firstEpisode, -1);
  int? get nextEpisode =>
      _attached.isEmpty ? null : _adjacentEpisode(lastEpisode, 1);

  /// 按阅读顺序比较目录索引。
  int _compareEpisodes(int a, int b) => (a - b) * chapterStep;

  /// 将阅读方向转换为目录索引，并排除首尾之外的章节。
  int? _adjacentEpisode(int episode, int direction) {
    final adjacent = episode + direction * chapterStep;
    return adjacent >= 1 && adjacent <= episodeCount ? adjacent : null;
  }

  /// 首次加载或手动跳章设置新的列表起点。
  void seed(int episode, List<String> urls) {
    chapters[episode] = ReaderChapter(List.unmodifiable(urls));
    _attached.add(episode);
  }

  /// 生成稳定标识的阅读条目，不把分隔与错误计入图片列表。
  List<ReaderItem> get items {
    if (_attached.isEmpty) return const [];
    final result = <ReaderItem>[];
    final previous = previousEpisode;
    if (previous != null) result.add(_boundary(previous));
    final episodes = _attached.toList()..sort(_compareEpisodes);
    for (final episode in episodes) {
      result.add(ReaderItem.header(episode));
      final chapter = chapters[episode]!;
      if (chapter.urls.isEmpty) {
        result.add(_boundary(episode));
      } else {
        for (var page = 0; page < chapter.urls.length; page++) {
          result.add(ReaderItem.image(episode, page, chapter.urls[page]));
        }
      }
    }
    final next = nextEpisode;
    if (next != null) result.add(_boundary(next));
    return List.unmodifiable(result);
  }

  /// 边界根据请求或章节结果显示加载、失败及空章节。
  ReaderItem _boundary(int episode) {
    final chapter = chapters[episode];
    var kind = ReaderItemKind.idle;
    if (_requests.containsKey(episode)) {
      kind = ReaderItemKind.loading;
    } else if (chapter?.error != null) {
      kind = ReaderItemKind.error;
    } else if (chapter != null && chapter.urls.isEmpty) {
      kind = ReaderItemKind.empty;
    }
    return ReaderItem.boundary(episode, kind, chapter?.error);
  }

  /// 失败或空章节阻止自动越过，用户可以明确跳过。
  bool get canLoadNext =>
      _attached.isNotEmpty &&
      (chapters[lastEpisode]!.urls.isNotEmpty ||
          _skipped.contains(lastEpisode));
  bool get canLoadPrevious =>
      _attached.isNotEmpty &&
      (chapters[firstEpisode]!.urls.isNotEmpty ||
          _skipped.contains(firstEpisode));

  /// 合并同章请求，手动操作排到后台队列之前。
  Future<void> load(int episode, {bool retry = false, bool priority = false}) {
    if (_disposed || episode < 1 || episode > episodeCount) {
      return Future.value();
    }
    final pending = _requests[episode];
    if (pending != null) {
      if (priority && _queue.remove(episode)) _queue.insert(0, episode);
      return pending.future;
    }
    if (!retry && chapters.containsKey(episode)) return Future.value();
    final completer = Completer<void>();
    _requests[episode] = completer;
    if (priority) {
      _queue.insert(0, episode);
    } else {
      _queue.add(episode);
    }
    onChanged();
    unawaited(_pump());
    return completer.future;
  }

  /// 缓存与网络结果替换同一章，网络失败保留有效图片。
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (!_disposed && _queue.isNotEmpty) {
      final episode = _queue.removeAt(0);
      try {
        final completion = Completer<void>();
        _streamCompletion = completion;
        _subscription = loadEpisode(episode).listen(
          (result) {
            if (_disposed) return;
            final previous = chapters[episode];
            if (result.error) {
              if (previous == null || previous.urls.isEmpty) {
                chapters[episode] = ReaderChapter(
                  const [],
                  error: result.errorMessage,
                );
              }
            } else {
              chapters[episode] = ReaderChapter(List.unmodifiable(result.data));
            }
            _attach(episode);
            onChanged();
          },
          onError: (Object error, StackTrace stack) {
            if (!_disposed && (chapters[episode]?.urls.isEmpty ?? true)) {
              chapters[episode] = ReaderChapter(
                const [],
                error: error.toString(),
              );
              _attach(episode);
              onChanged();
            }
          },
          onDone: () {
            if (!completion.isCompleted) completion.complete();
          },
        );
        await completion.future;
        if (!_disposed && !chapters.containsKey(episode)) {
          chapters[episode] = const ReaderChapter([]);
          _attach(episode);
        }
      } catch (error) {
        if (!_disposed && (chapters[episode]?.urls.isEmpty ?? true)) {
          chapters[episode] = ReaderChapter(const [], error: error.toString());
          _attach(episode);
        }
      } finally {
        // onDone 已结束订阅；不要再次等待取消，以免阻塞后续重试队列。
        _subscription = null;
        _streamCompletion = null;
        final request = _requests.remove(episode);
        if (request != null && !request.isCompleted) request.complete();
        if (!_disposed) onChanged();
      }
    }
    _pumping = false;
  }

  /// 拖动期间不插入头部，避免打断正在进行的滚动。
  void _attach(int episode) {
    if (_attached.isNotEmpty &&
        _compareEpisodes(episode, firstEpisode) < 0 &&
        !canPrepend()) {
      _deferred.add(episode);
    } else {
      _attached.add(episode);
    }
  }

  /// 滚动结束后提交待插入章节。
  void flushPrepend() {
    if (_disposed || !canPrepend() || _deferred.isEmpty) return;
    _attached.addAll(_deferred);
    _deferred.clear();
    onChanged();
  }

  /// 用户明确跳过空章或失败章节。
  Future<void> skip(int episode, int direction) {
    _skipped.add(episode);
    final adjacent = _adjacentEpisode(episode, direction);
    if (adjacent == null) return Future.value();
    return load(adjacent, priority: true);
  }

  /// 取消队列，后续网络结果不会修改会话。
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    final completion = _streamCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    _queue.clear();
    for (final request in _requests.values) {
      if (!request.isCompleted) request.complete();
    }
    _requests.clear();
    _deferred.clear();
  }
}

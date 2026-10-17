import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../comic_source/comic_source.dart';
import '../foundation/app_settings_provider.dart';
import '../foundation/pair.dart';
import '../foundation/def.dart';
import '../tools/tags_translation.dart';

part 'pre_search_providers.g.dart';

/// 单个搜索页面的不可变状态，不包含输入框和焦点控制器。
class PreSearchState {
  PreSearchState({
    required this.target,
    Iterable<String> options = const [],
    Iterable<Pair<String, TranslationType>> suggestions = const [],
    this.language,
    this.limitHistory = true,
  }) : options = List.unmodifiable(options),
       suggestions = List.unmodifiable(suggestions);

  final ComicType target;
  final List<String> options;
  final List<Pair<String, TranslationType>> suggestions;
  final String? language;
  final bool limitHistory;

  SearchPageData get searchPageData =>
      ComicSource.find(target)!.searchPageData!;

  /// 替换已修改字段，集合始终复制成只读快照。
  PreSearchState copyWith({
    ComicType? target,
    Iterable<String>? options,
    Iterable<Pair<String, TranslationType>>? suggestions,
    String? language,
    bool? limitHistory,
  }) => PreSearchState(
    target: target ?? this.target,
    options: options ?? this.options,
    suggestions: suggestions ?? this.suggestions,
    language: language ?? this.language,
    limitHistory: limitHistory ?? this.limitHistory,
  );
}

/// 按页面实例隔离搜索状态，退出页面后自动释放。
@riverpod
class PreSearch extends _$PreSearch {
  @override
  PreSearchState build(Object session) {
    final sources = ComicSource.sources
        .where((source) => source.searchPageData != null)
        .toList();
    if (sources.isEmpty) throw StateError('没有可搜索的漫画源');
    final initial = ref
        .read(appSettingsProvider)
        .value(AppSettingKeys.defaultSearchSource);
    final target = sources
        .firstWhere(
          (source) => source.key.name == initial,
          orElse: () => sources.first,
        )
        .key;
    return PreSearchState(target: target, options: _defaultOptions(target));
  }

  /// 读取所选来源的默认筛选项。
  List<String> _defaultOptions(ComicType target) => [
    for (final option
        in ComicSource.find(target)?.searchPageData?.searchOptions ??
            <SearchOptions>[])
      option.defaultValue,
  ];

  /// 切换来源时重置该来源的筛选项和建议。
  void updateTarget(ComicType target) {
    state = state.copyWith(
      target: target,
      options: _defaultOptions(target),
      suggestions: [],
    );
  }

  /// 更新搜索建议。
  void setSuggestions(Iterable<Pair<String, TranslationType>> suggestions) {
    state = state.copyWith(suggestions: suggestions);
  }

  /// 更新自定义筛选项。
  void setOptions(List<String> options) {
    state = state.copyWith(options: options);
  }

  /// 更新单个筛选项。
  void setOption(int index, String value) {
    final options = state.options.toList();
    options[index] = value;
    setOptions(options);
  }

  /// 设置语言筛选。
  void setLanguage(String language) {
    state = state.copyWith(language: language);
  }

  /// 展开全部搜索历史。
  void showAllHistory() {
    state = state.copyWith(limitHistory: false);
  }
}

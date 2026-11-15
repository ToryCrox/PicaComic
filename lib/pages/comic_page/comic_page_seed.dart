import 'package:flutter/foundation.dart';

import '../../network/download/download_model.dart';

/// 漫画详情页的首帧种子。
///
/// 详情页原本只靠 `comicType + id` 自行取数据，首帧必然是骨架屏。但调用方
/// （列表卡片、下载卡片）往往已经掌握部分甚至全部信息，通过本类带进页面，
/// 首帧就能直接渲染真实内容：
///
/// * 只填展示字段（列表卡片）：标题、封面、作者、页数、简介、标签立即可见；
/// * 填 [download]（下载卡片）：详情页用下载记录里保存的完整详情对象渲染，
///   连骨架屏都不需要；
/// * 填 [data]（任意已持有完整对象的入口）：直接作为详情数据使用。
///
/// [data] / [download] 里的对象必须是目标来源的数据模型（如 `ComicItem`、
/// `Gallery`），是否匹配由 `ComicPageAdapter.acceptSeedData` 校验，类型不符
/// 会自动丢弃，退回按展示字段渲染。
@immutable
class ComicPageSeed {
  const ComicPageSeed({
    this.title,
    this.subTitle,
    this.cover,
    this.heroTag,
    this.sourceLabel,
    this.pagesCount,
    this.introduction,
    this.tags,
    this.eps,
    this.downloadedEps = const [],
    this.isDownloaded,
    this.coverPath,
    this.data,
    this.download,
  });

  /// 从下载记录生成种子。
  ///
  /// 下载记录本身已含标题、作者、章节、已下载章节、标签和封面路径，足够让
  /// 详情页首帧填满信息区；如果来源保存了完整详情对象，[download] 会让详情页
  /// 进一步取到它并直接渲染完整内容。
  factory ComicPageSeed.fromDownloadedItem(
    DownloadedItem item, {
    String? heroTag,
  }) {
    String? coverPath;
    try {
      coverPath = item.coverPath;
    } catch (_) {
      // 记录尚未绑定下载管理器时取不到封面路径，退化为无封面。
      coverPath = null;
    }
    return ComicPageSeed(
      title: item.name,
      subTitle: item.subTitle,
      cover: coverPath == null ? null : Uri.file(coverPath).toString(),
      heroTag: heroTag,
      tags: item.tags.isEmpty ? null : List<String>.of(item.tags),
      eps: item.eps.isEmpty ? null : List<String>.of(item.eps),
      downloadedEps: item.downloadedEps,
      isDownloaded: true,
      coverPath: coverPath,
      download: item,
    );
  }

  /// 标题，首帧直接显示，同时作为标题 Hero 的文字。
  final String? title;

  /// 副标题，通常是作者。
  final String? subTitle;

  /// 封面地址，网络图或 `file://` 本地封面。
  final String? cover;

  /// 与列表卡片完全一致的封面 Hero 标签。
  final String? heroTag;

  /// 来源展示名，例如 “Picacg”；为空时用适配器提供的名称。
  final String? sourceLabel;

  /// 页数，信息区的 “xxP”。
  final int? pagesCount;

  /// 简介，数据到达前先显示。
  final String? introduction;

  /// 扁平标签列表，仅用于首帧展示，不可点击。
  final List<String>? tags;

  /// 章节名列表，用于显示章节数量。
  final List<String>? eps;

  /// 已下载章节序号，用于信息区的已下载提示。
  final List<int> downloadedEps;

  /// 是否已下载；为空表示未知，由页面自行查询。
  final bool? isDownloaded;

  /// 本地封面文件路径，优先级高于 [cover]。
  final String? coverPath;

  /// 调用方已持有的完整详情对象，可直接用于渲染内容页。
  final Object? data;

  /// 调用方持有的下载记录，详情页会向适配器索取其保存的详情对象。
  final DownloadedItem? download;

  /// 是否携带了可用于渲染完整内容的数据来源。
  bool get hasDetailSource => data != null || download != null;

  /// 是否没有任何可展示的信息。
  bool get isEmpty =>
      title == null &&
      subTitle == null &&
      cover == null &&
      coverPath == null &&
      introduction == null &&
      (tags == null || tags!.isEmpty) &&
      (eps == null || eps!.isEmpty);

  ComicPageSeed copyWith({
    String? title,
    String? subTitle,
    String? cover,
    String? heroTag,
    String? sourceLabel,
    int? pagesCount,
    String? introduction,
    List<String>? tags,
    List<String>? eps,
    List<int>? downloadedEps,
    bool? isDownloaded,
    String? coverPath,
    Object? data,
    DownloadedItem? download,
  }) {
    return ComicPageSeed(
      title: title ?? this.title,
      subTitle: subTitle ?? this.subTitle,
      cover: cover ?? this.cover,
      heroTag: heroTag ?? this.heroTag,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      pagesCount: pagesCount ?? this.pagesCount,
      introduction: introduction ?? this.introduction,
      tags: tags ?? this.tags,
      eps: eps ?? this.eps,
      downloadedEps: downloadedEps ?? this.downloadedEps,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      coverPath: coverPath ?? this.coverPath,
      data: data ?? this.data,
      download: download ?? this.download,
    );
  }
}

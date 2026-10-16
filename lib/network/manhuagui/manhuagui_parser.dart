import 'dart:convert';

import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html;
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/res.dart';

import 'manhuagui_decoder.dart';

/// 漫画柜列表项。
class ManhuaguiComic extends BaseComic {
  @override
  final String id;
  @override
  final String title;
  @override
  final String cover;
  @override
  final String subTitle;
  @override
  final String description;
  @override
  final List<String> tags;

  const ManhuaguiComic({
    required this.id,
    required this.title,
    required this.cover,
    this.subTitle = '',
    this.description = '',
    this.tags = const [],
  });
}

/// 评论正文及其引用的回复链。
class ManhuaguiCommentThread {
  final Comment comment;
  final List<Comment> quotes;

  const ManhuaguiCommentThread(this.comment, this.quotes);
}

/// 站点 HTML 与 JSON 的无副作用解析器。
abstract final class ManhuaguiParser {
  static const baseUrl = 'https://www.manhuagui.com';

  /// 补全封面或站内链接。
  static String absolute(String value) =>
      Uri.parse(baseUrl).resolve(value).toString();

  /// 提取分类页面的筛选值，去掉当前路径中其他筛选条件。
  static Map<String, Map<String, String>> filters(String source) {
    final document = html.parse(source);
    final result = <String, Map<String, String>>{};
    for (final key in ['area', 'genre', 'age', 'year', 'letter', 'status']) {
      final options = <String, String>{'': '全部'};
      for (final link in document.querySelectorAll('.filter.$key a')) {
        final match = RegExp(
          r'^/list/([^/]+)/$',
        ).firstMatch(link.attributes['href'] ?? '');
        if (match != null) options[match[1]!] = link.text.trim();
      }
      if (options.length == 1) throw const FormatException('漫画柜分类筛选加载失败');
      result[key] = options;
    }
    return result;
  }

  /// 解析列表并从网站分页控件取得总页数。
  static Res<List<BaseComic>> comics(
    String source, {
    bool updates = false,
    bool search = false,
  }) {
    final document = html.parse(source);
    final nodes = document.querySelectorAll(
      updates
          ? '.latest-list li'
          : search
          ? '.book-result li'
          : '#contList li',
    );
    // 搜索页使用独立布局，兼容旧版本的 result-list 类名。
    final entries = nodes.isEmpty && search
        ? document.querySelectorAll(
            '.result-list li, #searchResult li, .book-list li',
          )
        : nodes;
    final comics = <String, BaseComic>{};
    for (final node in entries) {
      final comic = comicNode(node);
      if (comic != null) comics.putIfAbsent(comic.id, () => comic);
    }
    if (entries.isEmpty &&
        !document.body!.text.contains('0  部') &&
        !RegExp(r'共.*?0\s*部|暂无|没有找到|无相关').hasMatch(document.body!.text)) {
      throw const FormatException('漫画柜列表结构已变化或请求被拦截');
    }
    var maxPage = 1;
    for (final link in document.querySelectorAll('.pager a, .page a')) {
      final page = RegExp(r'_p(\d+)').firstMatch(link.attributes['href'] ?? '');
      final number = int.tryParse(page?[1] ?? link.text.trim()) ?? 1;
      if (number > maxPage) maxPage = number;
    }
    return Res(comics.values.toList(), subData: maxPage);
  }

  /// 将带封面的列表节点转换为漫画。
  static ManhuaguiComic? comicNode(Element node) {
    final link = node.querySelector('a[href^="/comic/"]');
    final image = node.querySelector('img');
    final id = RegExp(
      r'/comic/(\d+)/',
    ).firstMatch(link?.attributes['href'] ?? '')?[1];
    if (id == null || image == null) return null;
    final title =
        link?.attributes['title'] ??
        image.attributes['alt'] ??
        link?.text.trim() ??
        '';
    final cover = image.attributes['data-src'] ?? image.attributes['src'] ?? '';
    return ManhuaguiComic(
      id: id,
      title: title,
      cover: absolute(cover),
      subTitle: node.querySelector('.tt')?.text.trim() ?? '',
      description: node.querySelector('.dt')?.text.trim() ?? '',
      tags: node
          .querySelectorAll('dd a[href^="/list/"]')
          .map((e) => e.text.trim())
          .toList(),
    );
  }

  /// 读取完整分组目录，包含网页中被隐藏的章节区间。
  static ComicInfoData info(String source, String id) {
    final document = html.parse(source);
    final title = document.querySelector('.book-title h1')?.text.trim();
    if (title == null || title.isEmpty) {
      throw const FormatException('漫画柜详情加载失败');
    }
    final state = document.querySelector('#__VIEWSTATE')?.attributes['value'];
    final directory = state == null
        ? document
        : html.parse(ManhuaguiDecoder.decompress(state));
    final chapters = <String, String>{};
    final groups = <ComicChapterGroup>[];
    final headings = directory.querySelectorAll('.chapter h4, h4');
    for (final heading in headings) {
      final links = <Element>[];
      var sibling = heading.nextElementSibling;
      while (sibling != null && sibling.localName != 'h4') {
        // 区间本身按旧到新排列，各区间内才是新到旧，不能整体倒转。
        final lists = sibling.localName == 'ul'
            ? [sibling]
            : sibling.querySelectorAll('ul');
        if (lists.isEmpty) {
          links.addAll(sibling.querySelectorAll('a[href*=".html"]').reversed);
        } else {
          for (final list in lists) {
            links.addAll(list.querySelectorAll('a[href*=".html"]').reversed);
          }
        }
        sibling = sibling.nextElementSibling;
      }
      final groupChapters = <String, String>{};
      for (final link in links) {
        final chapterId = RegExp(
          r'/comic/\d+/(\d+)\.html',
        ).firstMatch(link.attributes['href'] ?? '')?[1];
        if (chapterId == null) continue;
        groupChapters[chapterId] =
            link.attributes['title'] ??
            link.text.replaceAll(RegExp(r'\d+p$'), '').trim();
      }
      if (groupChapters.isEmpty) continue;
      chapters.addAll(groupChapters);
      final groupTitle = heading.text.trim();
      groups.add(
        ComicChapterGroup(
          id: 'group-${groups.length}',
          title: groupTitle,
          chapterIds: groupChapters.keys.toList(),
        ),
      );
    }
    if (chapters.isEmpty) throw const FormatException('漫画柜章节不可用，请在网站确认访问提示后重试');
    final tags = <String, List<String>>{};
    for (final span in document.querySelectorAll('.detail-list li > span')) {
      final label = span
          .querySelector('strong')
          ?.text
          .replaceAll('：', '')
          .trim();
      if (label == null || label.isEmpty) continue;
      final values = span
          .querySelectorAll('a')
          .map((a) => a.text.trim())
          .toList();
      if (values.isNotEmpty) tags[label] = values;
    }
    final suggestions = <BaseComic>[];
    for (final node in document.querySelectorAll(
      '.book-like li, .similar-list li',
    )) {
      final comic = comicNode(node);
      if (comic != null) suggestions.add(comic);
    }
    return ComicInfoData(
      title: title,
      cover: absolute(
        document.querySelector('.book-cover img')?.attributes['src'] ?? '',
      ),
      subTitle: document.querySelector('.detail-list .status')?.text.trim(),
      description:
          (document.querySelector('#intro-all') ??
                  document.querySelector('#intro-cut'))
              ?.text
              .trim(),
      tags: tags,
      chapters: chapters,
      chapterGroups: groups,
      suggestions: suggestions,
      sourceKey: 'manhuagui',
      comicId: id,
    );
  }

  /// 解析图片地址并保留签名查询参数。
  static List<String> pages(String source, {String host = 'i.hamreus.com'}) {
    final data = ManhuaguiDecoder.imageData(source);
    final files = List<String>.from(data['files'] as List);
    if (files.isEmpty) throw const FormatException('漫画柜章节没有图片');
    if (int.tryParse('${data['len']}') != files.length) {
      throw const FormatException('漫画柜章节图片不完整');
    }
    final path = data['path'] as String;
    final signature = (data['sl'] as Map?)?.map(
      (key, value) => MapEntry('$key', '$value'),
    );
    return files
        .map(
          (file) => Uri.parse(
            'https://$host$path$file',
          ).replace(queryParameters: signature).toString(),
        )
        .toList();
  }

  /// 还原网站评论中的 HTML、表情文本和百分号转义。
  static String commentText(String value) {
    value = value.replaceAllMapped(
      RegExp(r'%u([0-9a-fA-F]{4})'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    value = value.replaceAllMapped(
      RegExp(r'%([0-9a-fA-F]{2})'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    return html
            .parseFragment(
              value.replaceAll(
                RegExp(r'<br\s*/?>', caseSensitive: false),
                '\n',
              ),
            )
            .text ??
        '';
  }

  /// 按 commentIds 保留网站排序及从旧到新的引用链。
  static Res<List<ManhuaguiCommentThread>> comments(Object? response) {
    final data = response is String ? jsonDecode(response) : response;
    if (data is! Map ||
        data['commentIds'] is! List ||
        data['comments'] is! Map ||
        data['total'] is! num) {
      throw const FormatException('漫画柜评论响应无效');
    }
    final objects = data['comments'] as Map;
    Comment comment(String id) {
      final raw = objects[id];
      if (raw is! Map) throw const FormatException('漫画柜评论引用缺失');
      return Comment(
        '${raw['user_name'] ?? ''}',
        raw['avatar'] == null ? null : absolute('${raw['avatar']}'),
        commentText('${raw['content'] ?? ''}'),
        '${raw['add_time'] ?? ''}',
        null,
        id,
      );
    }

    final threads = <ManhuaguiCommentThread>[];
    for (final relation in data['commentIds'] as List) {
      final ids = '$relation'.split(',');
      threads.add(
        ManhuaguiCommentThread(
          comment(ids.first),
          ids.skip(1).toList().reversed.map(comment).toList(),
        ),
      );
    }
    return Res(threads, subData: ((data['total'] as num).toInt() / 30).ceil());
  }
}

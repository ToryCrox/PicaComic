import 'package:pica_comic/comic_source/comic_source.dart';

/// 分组章节和下载映射的共享样例。
const sample = ComicInfoData(
  title: '测试',
  comicId: '4125',
  sourceKey: 'manhuagui',
  chapters: {
    '10': '第01卷',
    '11': '第02卷',
    '20': '第01话',
    '21': '第02话',
    '30': '番外篇',
  },
  chapterGroups: [
    ComicChapterGroup(id: 'volumes', title: '单行本', chapterIds: ['10', '11']),
    ComicChapterGroup(id: 'chapters', title: '单话', chapterIds: ['20', '21']),
    ComicChapterGroup(id: 'extras', title: '番外篇', chapterIds: ['30']),
  ],
);

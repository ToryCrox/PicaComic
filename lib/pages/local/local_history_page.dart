import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:path/path.dart' as Path;
import '../reader/comic_reading_page.dart';
import 'local_thumbs_page.dart';

class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await downloadManager.getAllLocalHistory();
    if (mounted) {
      setState(() {
        _history = List<Map<String, dynamic>>.from(history);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("历史记录".tl),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(child: Text("暂无记录".tl))
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    final path = item['path'] as String;
                    final title = Path.basename(path);
                    final time = DateTime.fromMillisecondsSinceEpoch(item['time'] as int);
                    final pageIndex = item['pageIndex'] as int;
                    final isReversed = item['isReversed'] == 1;

                    return ListTile(
                      title: Text(title),
                      subtitle: Text("${time.toString().split('.').first} | 第 $pageIndex 页"),
                      leading: const Icon(Icons.history),
                      onTap: () {
                        App.globalTo(() => ComicReadingPage.localComic(
                              path,
                              title,
                              initialPage: pageIndex,
                              isReversed: isReversed,
                            ));
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.folder_open),
                        onPressed: () {
                          App.globalTo(() => LocalThumbsPage(dirPath: path));
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

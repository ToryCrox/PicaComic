import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as Path;
import 'package:pica_comic/tools/image_utils.dart';

import '../../foundation/app.dart';
import '../reader/comic_reading_page.dart';

class LocalThumbsPage extends StatefulWidget {
  const LocalThumbsPage({
    super.key,
    required this.dirPath,
    this.onItemTap,
  });

  final String dirPath;
  final void Function(int, String)? onItemTap;

  @override
  State<LocalThumbsPage> createState() => _LocalThumbsPageState();
}

class _LocalThumbsPageState extends State<LocalThumbsPage> {
  final _imagePaths = <String>[];

  String _title = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _title = Path.basename(widget.dirPath);
    _loadImages();
  }

  static Future<List<String>> loadImagesFilePaths(String dirPath) async {
    final dir = Directory(dirPath);
    //final images = (await dir.list(recursive: true).toList())
    sFileRelativeFromPath = dirPath;
    final images = dir.listSync(recursive: true)
        .where(predictImageFile)
        .sorted(fileNameCompare)
        .map((e) => e.absolute.path)
        .toList();
    return images;
  }

  Future<void> _loadImages() async {
    final t1 = DateTime.now();
    final dir = Directory(widget.dirPath);
    // final images = dir.listSync(recursive: true)
    //     .where(predictImageFile)
    //     .sorted(fileNameCompare)
    //     .map((e) => e.absolute.path)
    //     .toList();
    final images = await compute(loadImagesFilePaths, widget.dirPath);
    final diff = DateTime.now().difference(t1);
    if (diff.inMilliseconds < 300) {
      final delay  = 300 - diff.inMilliseconds;
      debugPrint("LocalThumbsPage: delay $delay ms");
      await Future.delayed(Duration(milliseconds: delay));
    }
    debugPrint("LocalThumbsPage: load ${images.length} images, diff: ${diff.inMilliseconds}ms");
    setState(() {
      _loading = false;
      _imagePaths.clear();
      _imagePaths.addAll(images);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _title + (_imagePaths.isEmpty ? "" : " (${_imagePaths.length})")),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final cacheWidth = MediaQuery.devicePixelRatioOf(context) * 200;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: _imagePaths.length,
      itemBuilder: (BuildContext context, int index) {
        return InkWell(
          onTap: () {
            if (widget.onItemTap != null) {
              widget.onItemTap?.call(index + 1, _imagePaths[index]);
            } else {
              App.globalTo(
                    () => ComicReadingPage.localComic(
                  widget.dirPath,
                  _title,
                  initialPage: index + 1,
                ),
              );
            }
          },
          child: Image.file(
            File(_imagePaths[index]),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth.toInt(),
          ),
        );
      },
    );
  }
}

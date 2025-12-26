import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/image_loader/base_image_provider.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/download/download_manager.dart';
import 'package:pica_comic/network/eh_network/eh_models.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/tools/map_extension.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/network/jm_network/jm_image.dart';

import 'reader/comic_reading_page.dart';

class ImageFavoritesPage extends StatefulWidget {
  const ImageFavoritesPage({
    super.key,
    this.filterTitle = "",
  });

  final String filterTitle;

  @override
  State<ImageFavoritesPage> createState() => _ImageFavoritesPageState();
}

class _ImageFavoritesPageState extends State<ImageFavoritesPage> {
  String _filterTitle = '';
  List<ImageFavorite> _imageList = [];

  bool _showGroup = false;
  List<String> _titles = [];

  @override
  void initState() {
    super.initState();
    _filterTitle = widget.filterTitle;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_showGroup) {
      _titles = await ImageFavoriteManager.getAllTitle();
    } else {
      if (_filterTitle.isNotEmpty) {
        _imageList = await ImageFavoriteManager.getAllByTitle(_filterTitle);
      } else {
        _imageList = await ImageFavoriteManager.getAll();
      }
    }
    Log.d('ImageFavorites _imageList $_imageList');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final title =
        Text("图片收藏".tl + (_filterTitle.isEmpty ? "" : " - $_filterTitle"));
    return StateBuilder(
      tag: "image_favorites_page",
      init: SimpleController(),
      builder: (controller) {
        if (UiMode.m1(context)) {
          return Scaffold(
            appBar: AppBar(
              title: title,
              actions: [
                ..._buildActions(),
              ],
            ),
            body: buildPage(),
          );
        } else {
          return Material(
            child: Column(
              children: [
                Appbar(
                  title: title,
                  actions: [
                    ..._buildActions(),
                  ],
                ),
                Expanded(
                  child: buildPage(),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  List<Widget> _buildActions() {
    return [
      Tooltip(
        message: _showGroup ? "显示列表".tl : "显示分组".tl,
        child: IconButton(
          icon:
              _showGroup ? const Icon(Icons.list) : const Icon(Icons.grid_view),
          onPressed: () {
            _showGroup = !_showGroup;
            _refresh();
          },
        ),
      )
    ];
  }

  Widget buildPage() {
    if (_showGroup) {
      return ListView.separated(
        itemCount: _titles.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(_titles[index]),
            onTap: () {
              // _showGroup = false;
              // _filterTitle = _titles[index];
              // _refresh();
              context.to(() => ImageFavoritesPage(filterTitle: _titles[index]));
            },
          );
        },
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithComics(true, appdata.settings[74]),
      itemCount: _imageList.length,
      itemBuilder: (context, index) {
        return FavoriteImageTile(_imageList[index]);
      },
    );
  }
}

class FavoriteImageTile extends StatelessWidget {
  const FavoriteImageTile(this.image, {super.key});

  final ImageFavorite image;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.of(context).devicePixelRatio;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: Image(
                  image: ResizeImage.resizeIfNeeded(
                    (200 * ratio).toInt(),
                    null,
                    _ImageProvider(image),
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.5),
                      ]),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Text(
                    image.title.replaceAll("\n", ""),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14.0,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongTap,
                  onSecondaryTapDown: (details) => onSecondaryTap(details, context),
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void onTap() {
    var type = image.id.split("-")[0];
    _readWithKey(type, image.id.replaceFirst("$type-", ""), image.ep,
        image.page, image.title, image.otherInfo);
  }

  void _readWithKey(String key, String target, int ep, int page, String title,
      Map<String, dynamic> otherInfo) async {
    switch (key) {
      case "picacg":
        App.globalTo(() => ComicReadingPage.picacg(
            target, ep, List.from(otherInfo.optStringList("eps")), title,
            initialPage: page));
      case "ehentai":
        App.globalTo(
          () => ComicReadingPage.ehentai(
            Gallery.fromJson(otherInfo["gallery"]),
            initialPage: page,
          ),
        );
      case "jm":
        App.globalTo(
          () => ComicReadingPage(
            JmReadingData(
              title,
              target,
              List.from(otherInfo.optStringList('eps')),
              List.from(
                otherInfo.optStringList("jmEpNames"),
              ),
            ),
            page,
            ep,
          ),
        );
      case "hitomi":
        App.globalTo(
          () => ComicReadingPage(
            HitomiReadingData(
              title,
              target,
              (otherInfo["hitomi"] as List)
                  .map((e) => HitomiFile.fromMap(e))
                  .toList(),
              target,
            ),
            page,
            0,
          ),
        );
      case "htManga":
      case "htmanga":
        App.globalTo(
          () => ComicReadingPage.htmanga(target, title, initialPage: page),
        );
      case "nhentai":
        App.globalTo(
          () => ComicReadingPage.nhentai(target, title, initialPage: page),
        );
      default:
        var source = ComicSource.find(key);
        if (source == null) throw "Unknown source $key";
        App.globalTo(
          () => ComicReadingPage(
            CustomReadingData(
              target,
              title,
              source,
              Map.from(otherInfo["eps"]),
            ),
            page,
            ep,
          ),
        );
    }
  }

  void onLongTap() {
    showConfirmDialog(App.globalContext!, "确认删除".tl, "要删除这个图片吗".tl, delete);
  }

  void delete() {
    ImageFavoriteManager.delete(image);
    showToast(message: "删除成功".tl);
    StateController.findOrNull(tag: "image_favorites_page")?.update();
  }

  void onSecondaryTap(TapDownDetails details, BuildContext context) {
    showDesktopMenu(App.globalContext!, details.globalPosition, [
      DesktopMenuEntry(text: "查看".tl, onClick: onTap),
      DesktopMenuEntry(text: "分组".tl, onClick: (){
        context.to(() => ImageFavoritesPage(filterTitle: image.title));
      }),
      DesktopMenuEntry(text: "删除".tl, onClick: delete),
    ]);
  }
}

class _ImageProvider extends BaseImageProvider<_ImageProvider> {
  _ImageProvider(this.image);

  final ImageFavorite image;

  @override
  String get key => image.id + image.ep.toString() + image.page.toString();

  @override
  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents) async {
    final isLocalFile = image.imagePath.startsWith("file://");
    Log.d("load image ${image.imagePath}, isLocalFile: $isLocalFile");
    if (isLocalFile) {
      return await File(image.imagePath.replaceFirst("file://", ""))
          .readAsBytes();
    } else if (File(image.imagePath).existsSync()) {
      return await File("${App.dataPath}/images/${image.imagePath}")
          .readAsBytes();
    } else {
      var type = image.id.split("-")[0];
      bool hasEp =  type == "jm";

      final downloadFile = await DownloadManager()
          .getDownloadImageOrNull(image.title, hasEp ? image.ep : 0, image.page);
      if (downloadFile != null) {
        return await downloadFile.readAsBytes();
      }

      Stream<DownloadProgress> stream;
      switch (type) {
        case "ehentai":
          stream = ImageManager().getEhImageNew(
              Gallery.fromJson(image.otherInfo["gallery"]), image.page);
        case "jm":
          stream = ImageManager().getJmImage(image.otherInfo["url"], null,
              epsId: image.otherInfo["epsId"],
              scrambleId: kJmScrambleId,
              bookId: image.otherInfo["bookId"]);
        case "hitomi":
          stream = ImageManager().getHitomiImage(
              HitomiFile.fromMap(image.otherInfo["hitomi"][image.page - 1]),
              image.otherInfo["galleryId"]);
        default:
          stream = ImageManager().getImage(image.otherInfo["url"]);
      }
      DownloadProgress? finishProgress;
      await for (var progress in stream) {
        if (progress.currentBytes == progress.expectedBytes) {
          finishProgress = progress;
        }
        chunkEvents.add(ImageChunkEvent(
            cumulativeBytesLoaded: progress.currentBytes,
            expectedTotalBytes: progress.expectedBytes));
      }
      var file = finishProgress!.getFile();
      var data = await file.readAsBytes();
      var file2 = File("${App.dataPath}/images/${image.imagePath}");
      if (!file2.existsSync()) {
        await file2.create(recursive: true);
      }
      await file2.writeAsBytes(data);
      return data;
    }
  }

  @override
  Future<_ImageProvider> obtainKey(ImageConfiguration configuration) async {
    return this;
  }
}

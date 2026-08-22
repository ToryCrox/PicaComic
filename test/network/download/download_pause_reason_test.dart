import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/network/download/download_model.dart';

void main() {
  test('特殊暂停原因可以持久化并从旧数据兼容恢复', () {
    final task = _TestDownloadingTask();
    task.pauseReason = DownloadPauseReason.ehOriginalGpInsufficient;

    final restored = _TestDownloadingTask.fromMap(task.toMap());

    expect(restored.pauseReason, DownloadPauseReason.ehOriginalGpInsufficient);
    expect(_TestDownloadingTask.fromMap({}).pauseReason, isNull);
  });
}

class _TestDownloadingTask extends DownloadingTask {
  _TestDownloadingTask()
    : super(null, null, null, 'test-download', type: DownloadType.picacg);

  _TestDownloadingTask.fromMap(Map<String, dynamic> map)
    : super.fromMap(map, null, null, null);

  @override
  Future<Map<int, List<String>>> getLinks() async => {};

  @override
  Stream<DownloadProgress> downloadImage(String link) => Stream.empty();

  @override
  String get cover => '';

  @override
  String get title => 'test';

  @override
  FutureOr<DownloadedItem> toDownloadedItem() {
    throw UnimplementedError();
  }

  @override
  Map<String, dynamic> toMap() => toBaseMap();
}

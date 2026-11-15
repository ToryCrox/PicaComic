import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/components/download_button_loading_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  DownloadButtonLoading notifier() =>
      container.read(downloadButtonLoadingProvider.notifier);

  test('按漫画 ID 独立记录加载状态', () {
    expect(container.read(downloadButtonLoadingProvider), isEmpty);

    notifier()
      ..add('comic-a')
      ..add('comic-b');

    expect(container.read(downloadButtonLoadingProvider), {
      'comic-a',
      'comic-b',
    });

    notifier().remove('comic-a');

    expect(container.read(downloadButtonLoadingProvider), {'comic-b'});
    expect(container.read(downloadButtonIsLoadingProvider('comic-a')), isFalse);
    expect(container.read(downloadButtonIsLoadingProvider('comic-b')), isTrue);
  });

  test('重复标记不会发布新状态', () {
    var notifications = 0;
    container.listen(downloadButtonLoadingProvider, (_, _) => notifications++);

    notifier()
      ..add('comic-a')
      ..add('comic-a');
    expect(notifications, 1);

    notifier()
      ..remove('comic-a')
      ..remove('comic-a');
    expect(notifications, 2);
  });

  test('family 派生只在该漫画的加载态变化时通知', () async {
    final events = <bool>[];
    final subscription = container.listen(
      downloadButtonIsLoadingProvider('comic-a'),
      (_, next) => events.add(next),
    );
    addTearDown(subscription.close);
    await container.pump();

    // 其他漫画开始或结束下载都不应触发该订阅方。
    notifier().add('comic-b');
    await container.pump();
    expect(events, isEmpty);

    notifier().add('comic-a');
    await container.pump();
    expect(events, [true]);

    notifier().remove('comic-b');
    await container.pump();
    expect(events, [true]);

    notifier().remove('comic-a');
    await container.pump();
    expect(events, [true, false]);
  });
}

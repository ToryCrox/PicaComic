import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/comic_source_services.dart';
import 'package:pica_comic/network/network_client_manager.dart';
import 'package:pica_comic/network/network_telemetry.dart';
import 'package:pica_comic/network/download/download_manager.dart';

void main() {
  test('漫画源网络客户端由各自的 ProviderScope 持有', () async {
    final firstContainer = ProviderContainer(
      overrides: [
        networkTelemetryBridgeProvider.overrideWithValue(
          NetworkTelemetryBridge(),
        ),
      ],
    );
    final secondContainer = ProviderContainer(
      overrides: [
        networkTelemetryBridgeProvider.overrideWithValue(
          NetworkTelemetryBridge(),
        ),
      ],
    );

    addTearDown(() async {
      firstContainer.dispose();
      secondContainer.dispose();
    });

    final firstClient = firstContainer.read(picacgNetworkProvider);
    final secondClient = secondContainer.read(picacgNetworkProvider);
    final firstManager = firstContainer.read(downloadManagerProvider.notifier);
    final secondManager = secondContainer.read(
      downloadManagerProvider.notifier,
    );

    expect(firstClient, same(firstContainer.read(picacgNetworkProvider)));
    expect(secondClient, same(secondContainer.read(picacgNetworkProvider)));
    expect(
      firstClient,
      same(firstContainer.read(picacgNetworkProvider.notifier)),
    );
    expect(
      firstContainer.read(networkClientManagerProvider),
      same(firstContainer.read(networkClientManagerProvider.notifier)),
    );
    expect(firstClient, isNot(same(secondClient)));
    expect(
      firstClient.clientManager,
      same(firstContainer.read(networkClientManagerProvider)),
    );
    expect(
      secondClient.clientManager,
      same(secondContainer.read(networkClientManagerProvider)),
    );
    expect(
      firstManager,
      same(firstContainer.read(downloadManagerProvider.notifier)),
    );
    expect(
      secondManager,
      same(secondContainer.read(downloadManagerProvider.notifier)),
    );
    expect(firstManager, isNot(same(secondManager)));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/network/picacg_network/models.dart';
import 'package:pica_comic/pages/account_providers.dart';

void main() {
  group('Picacg 前台自动签到条件', () {
    test('仅启用且账号尚未签到时执行', () {
      expect(
        shouldCheckInPicacgAccount(const Profile(isPunched: false), true),
        isTrue,
      );
    });

    test('设置关闭时不执行', () {
      expect(
        shouldCheckInPicacgAccount(const Profile(isPunched: false), false),
        isFalse,
      );
    });

    test('已签到或签到状态未知时不执行', () {
      expect(
        shouldCheckInPicacgAccount(const Profile(isPunched: true), true),
        isFalse,
      );
      expect(shouldCheckInPicacgAccount(const Profile(), true), isFalse);
    });
  });
}

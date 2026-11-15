import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/api/api_client.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/avatars.dart';
import 'package:qq_concept/core/profile.dart';

/// 真实服务的注册链路集成测试：需先启动 qq-server（本机 MySQL + Redis）。
///
///   cd qq-server && npm start
///   cd qq_concept && flutter test --dart-define=RUN_API_TEST=true \
///       test/register_integration_test.dart
///
/// 用时间戳注册一个全新账号，验证昵称 / 性别 / 内置头像落库并回显；
/// 默认跳过，保证普通 `flutter test` 在离线环境也能全绿。
const bool _run = bool.fromEnvironment('RUN_API_TEST');

void main() {
  test('真实 API：注册资料字段（昵称 / 性别 / 内置头像）落库并回显', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = stamp.substring(stamp.length - 10);
    final acc = 'r$suffix';
    final nickname = '注册测试$suffix';
    const password = 'Passw0rd!';

    final state = QAppState(preset: 'login');
    final bridge = QApiBridge(state);
    state.backend = bridge;
    addTearDown(() async {
      await bridge.dispose();
      state.dispose();
    });

    await bridge.register(
      QRegistration(
        account: acc,
        nickname: nickname,
        password: password,
        passwordConfirm: password,
        gender: QGender.female,
        avatarIndex: 5,
      ),
    );

    // 注册即登录：进入主面板，头像下标已本地回显。
    expect(state.loggedIn, isTrue);
    expect(state.displayName, nickname);
    expect(state.myAvatarIndex, 5);

    // 服务端 /users/me 回读，确认资料真实落库（不是前端假数据）。
    final me = await bridge.client.me();
    expect(me.account, acc);
    expect(me.nickname, nickname);
    expect(me.gender, QGender.female.code);
    expect(qBuiltinAvatarIndex(me.avatarUrl), 5);

    final otherNickname = '其他用户$suffix';
    await bridge.client.register('s$suffix', password, nickname: otherNickname);
    await expectLater(
      state.changeNickname(otherNickname),
      throwsA(
        isA<QApiException>().having((e) => e.code, 'code', 'NICKNAME_EXISTS'),
      ),
    );
    expect(state.displayName, nickname);
    final updatedNickname = '修改昵称$suffix';
    await state.changeNickname(updatedNickname);
    expect(state.displayName, updatedNickname);
    expect((await bridge.client.me()).nickname, updatedNickname);
  }, skip: !_run);
}

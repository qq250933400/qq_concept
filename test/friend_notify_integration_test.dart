import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/core/app_state.dart';

/// 真实服务的关系链实时通知集成测试：需先启动 qq-server（本机 MySQL + Redis）。
///
///   cd qq-server && npm start
///   cd qq_concept && flutter test --dart-define=RUN_API_TEST=true \
///       test/friend_notify_integration_test.dart
///
/// 验证「不手动刷新、靠 WS 推送」链路：
///   发申请 → 对方收到 friend_request.new（申请数 +1，无需重开窗口）
///   对方同意 → 本端收到 friend.accepted（好友列表即时出现新好友）
///   对方删好友 → 本端收到 friend.deleted（好友列表即时移除）
const bool _run = bool.fromEnvironment('RUN_API_TEST');

Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  throw StateError('等待条件超时');
}

void main() {
  test('真实 API：关系链变更通过 WS 实时推送（无需手动刷新）', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = stamp.substring(stamp.length - 9);
    final accA = 'na$suffix';
    final accB = 'nb$suffix';
    const password = 'Passw0rd!';

    final stateA = QAppState(preset: 'login');
    final stateB = QAppState(preset: 'login');
    final a = QApiBridge(stateA);
    final b = QApiBridge(stateB);
    stateA.backend = a;
    stateB.backend = b;
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      stateA.dispose();
      stateB.dispose();
    });

    await a.client.register(accA, password, nickname: '通知A');
    await b.client.register(accB, password, nickname: '通知B');
    await a.login(accA, password);
    await b.login(accB, password);
    await _waitFor(() => a.connected && b.connected);

    // 1. A 发申请 → B 不手动刷新，靠 WS 收到 friend_request.new。
    final before = stateB.pendingRequestCount;
    await a.sendFriendRequest(accB, '实时通知集成测试');
    await _waitFor(() => stateB.pendingRequestCount > before);
    expect(
      stateB.friendRequests.any((r) => r.account == accA && r.pending),
      isTrue,
    );

    // 2. B 同意 → A 不手动刷新，靠 WS 收到 friend.accepted，好友列表出现 B。
    final req = stateB.friendRequests.firstWhere((r) => r.account == accA);
    await b.acceptFriendRequest(req.id);
    await _waitFor(() => stateA.contacts.any((c) => c.account == accB));
    expect(stateA.friends.any((f) => f.name == '通知B'), isTrue);

    // 3. B 删好友 → A 靠 WS 收到 friend.deleted，好友列表移除 B。
    await b.deleteFriend('通知A');
    await _waitFor(() => !stateA.contacts.any((c) => c.account == accB));
    expect(stateA.friends.any((f) => f.name == '通知B'), isFalse);
  }, skip: !_run);
}

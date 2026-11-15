import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/api/api_client.dart';
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
const String _secondApi = String.fromEnvironment('QQ_API_BASE_2');

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
    final nicknameA = '通知A$suffix';
    final nicknameB = '通知B$suffix';
    const password = 'Passw0rd!';

    final stateA = QAppState(preset: 'login');
    final stateB = QAppState(preset: 'login');
    final stateB2 = QAppState(preset: 'login');
    final a = QApiBridge(stateA);
    final b = QApiBridge(stateB);
    final b2 = QApiBridge(
      stateB2,
      apiClient: QApiClient(baseUrl: _secondApi.isEmpty ? null : _secondApi),
    );
    stateA.backend = a;
    stateB.backend = b;
    stateB2.backend = b2;
    final errors = <String>[];
    for (final state in [stateA, stateB, stateB2]) {
      state.addListener(() {
        final toast = state.toast;
        if (toast != null && (toast.contains('失败') || toast.contains('错误'))) {
          errors.add(toast);
        }
      });
    }
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await b2.dispose();
      stateA.dispose();
      stateB.dispose();
      stateB2.dispose();
    });

    await a.client.register(accA, password, nickname: nicknameA);
    await b.client.register(accB, password, nickname: nicknameB);
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
    expect(stateA.friends.any((f) => f.name == nicknameB), isTrue);

    await a.send(nicknameB, '改名前的消息');
    await a.send(nicknameB, '第二条消息');
    await _waitFor(() => stateB.unreadFor(nicknameA) == 2);
    await b2.login(accB, password);
    await _waitFor(() => b2.connected);
    await _waitFor(() => stateB2.unreadFor(nicknameA) == 2);
    expect(stateB2.recentChats.first.message.text, '第二条消息');
    final senderConversations = await a.client.conversations();
    final senderItems = senderConversations['items'] as List;
    expect(int.parse(senderItems.first['unread'].toString()), 0);
    final receiverConversations = await b2.client.conversations();
    final receiverItems = receiverConversations['items'] as List;
    await b2.client.markRead(
      receiverItems.first['id'].toString(),
      stateB2.thread(nicknameA).first.seq!,
    );
    await _waitFor(() => stateB.unreadFor(nicknameA) == 1);
    await _waitFor(() => stateB2.unreadFor(nicknameA) == 1);
    stateB.selectFriend(nicknameA);
    await _waitFor(() => stateB.unreadFor(nicknameA) == 0);
    await _waitFor(() => stateB2.unreadFor(nicknameA) == 0);

    stateA.selectFriend(nicknameB);
    final renamed = '新昵称$suffix';
    await stateB.changeNickname(renamed);
    await _waitFor(() => stateA.friends.any((f) => f.name == renamed));
    expect(stateA.thread(renamed).any((m) => m.text == '改名前的消息'), isTrue);
    expect(stateA.windows.any((w) => w.id == 'chat:$renamed'), isTrue);
    await a.send(renamed, '改名后的消息');
    await _waitFor(
      () => stateB.thread(nicknameA).any((m) => m.text == '改名后的消息'),
    );

    await Future.wait([
      for (var i = 0; i < 5; i++) ...[
        a.send(renamed, '并发A$i'),
        b2.send(nicknameA, '并发B$i'),
      ],
    ]);
    await _waitFor(
      () =>
          stateA
              .thread(renamed)
              .where((m) => m.text.startsWith('并发') && !m.pending)
              .length ==
          10,
    );
    await _waitFor(
      () =>
          stateB2
              .thread(nicknameA)
              .where((m) => m.text.startsWith('并发') && !m.pending)
              .length ==
          10,
    );
    await _waitFor(() => stateA.unreadFor(renamed) == 0);
    await _waitFor(() => stateB.unreadFor(nicknameA) == 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(errors, isEmpty);

    // 3. B 删好友 → A 靠 WS 收到 friend.deleted，好友列表移除 B。
    await b.deleteFriend(nicknameA);
    await _waitFor(() => !stateA.contacts.any((c) => c.account == accB));
    expect(stateA.friends.any((f) => f.name == renamed), isFalse);
  }, skip: !_run);
}

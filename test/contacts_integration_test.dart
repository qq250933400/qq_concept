import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/core/app_state.dart';

/// 真实服务的关系链集成测试：需先启动 qq-server（本机 MySQL + Redis）。
///
///   cd qq-server && npm run seed && npm start
///   cd qq_concept && flutter test --dart-define=RUN_API_TEST=true \
///       test/contacts_integration_test.dart
///
/// 用时间戳注册两个全新账号，不污染 seed 的 10001~10007；
/// 默认跳过，保证普通 `flutter test` 在离线环境也能全绿。
const bool _run = bool.fromEnvironment('RUN_API_TEST');

void main() {
  test('真实 API：搜索 / 申请 / 通过 / 分组增改删 / 移动 / 删除好友', () async {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final suffix = stamp.substring(stamp.length - 10);
    final accA = 'a$suffix';
    final accB = 'b$suffix';
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

    await a.client.register(accA, password);
    await b.client.register(accB, password);
    await a.login(accA, password);
    await b.login(accB, password);
    expect(stateA.loggedIn, isTrue);
    expect(stateA.contacts, isEmpty);
    expect(stateB.contacts, isEmpty);

    // 1. 搜人：能找到对方，且标记为「还不是好友」
    await a.searchContacts(accB);
    final hit = stateA.searchResults.firstWhere(
      (u) => u.account == accB,
      orElse: () => throw StateError('搜不到 $accB'),
    );
    expect(hit.isFriend, isFalse);

    // 2. A 发申请 → B 收到 → B 通过 → A 的好友列表出现 B
    await a.sendFriendRequest(accB, 'Dart 关系链集成测试');
    await b.refreshContacts();
    final request = stateB.friendRequests.firstWhere(
      (r) => r.account == accA && r.pending,
      orElse: () => throw StateError('B 未收到 A 的好友申请'),
    );
    await b.acceptFriendRequest(request.id);
    await a.refreshContacts();
    expect(stateA.contacts.any((c) => c.account == accB), isTrue);
    expect(stateA.friends.any((f) => f.name == accB), isTrue);
    expect(stateA.pendingRequestCount, 0);

    // 3. 建分组 / 改名 / 移动好友
    final groupName = '临时分组$suffix';
    await a.createFriendGroup(groupName);
    final group = stateA.contactGroups.firstWhere(
      (g) => g.name == groupName,
      orElse: () => throw StateError('分组未创建'),
    );
    await a.moveFriendToGroup(accB, group.id);
    expect(
      stateA.contacts.firstWhere((c) => c.account == accB).groupId,
      group.id,
    );
    expect(stateA.contactGroups.firstWhere((g) => g.id == group.id).count, 1);

    final renamed = '${groupName}R';
    await a.renameFriendGroup(group.id, renamed);
    expect(
      stateA.contactGroups.firstWhere((g) => g.id == group.id).name,
      renamed,
    );

    // 4. 删分组 → 好友回落未分组（FK ON DELETE SET NULL）
    await a.deleteFriendGroup(group.id);
    expect(stateA.contactGroups.any((g) => g.id == group.id), isFalse);
    expect(
      stateA.contacts.firstWhere((c) => c.account == accB).groupId,
      isNull,
    );
    expect(stateA.contactGroups.any((g) => g.id.isEmpty), isTrue,
        reason: '有散落好友时应出现「未分组」虚拟分组');

    // 5. 删好友 → 双向关系解除
    await a.deleteFriend(accB);
    expect(stateA.contacts.any((c) => c.account == accB), isFalse);
    await b.refreshContacts();
    expect(stateB.contacts.any((c) => c.account == accA), isFalse);

    await a.logout();
    await b.logout();
  }, skip: _run ? null : '需启动 qq-server 并指定 RUN_API_TEST=true');
}

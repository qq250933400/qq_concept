import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/contacts.dart';
import 'package:qq_concept/screens/friends_manager_screen.dart';

/// 关系链状态的离线兜底：不接 API 时也要能完整走一遍
/// 「搜索 → 发申请 → 通过 → 建分组 → 移动 → 改名 → 删分组 → 删好友」。
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('离线模式关系链全链路', () async {
    final st = QAppState(preset: 'main');
    addTearDown(st.dispose);

    expect(st.contactGroups.length, 6);
    expect(st.contacts.length, 6);
    expect(st.pendingRequestCount, 1);

    // 搜索本地用户目录
    st.searchUsersForAdd('10009');
    expect(st.searchResults.any((u) => u.account == '10009'), isTrue);
    expect(st.searchResults.first.isFriend, isFalse);

    // 发出申请
    st.sendFriendRequest('10009', '你好');
    await _settle();
    expect(st.contactsBusy, isFalse);
    expect(
      st.friendRequests.any(
        (r) => r.account == '10009' && r.direction == 'out' && r.status == 0,
      ),
      isTrue,
    );

    // 通过初始收到的申请 → 好友落到「未分组」
    st.acceptFriendRequest('local-req-1');
    await _settle();
    expect(st.contacts.any((c) => c.account == '10008'), isTrue);
    expect(st.pendingRequestCount, 0);
    expect(st.friendGroups, isNotNull, reason: '本地写操作后主面板也要跟着变');

    // 新建分组 → 移动好友 → 改名
    st.createFriendGroup('同事');
    await _settle();
    final group = st.contactGroups.firstWhere((g) => g.name == '同事');
    st.moveFriend('沈星回', group.id);
    await _settle();
    expect(st.contactByName('沈星回')!.groupId, group.id);
    expect(st.contactGroups.firstWhere((g) => g.id == group.id).count, 1);

    st.renameFriendGroup(group.id, '同事2');
    await _settle();
    expect(st.contactGroups.firstWhere((g) => g.id == group.id).name, '同事2');

    // 删除分组 → 好友回落未分组
    st.deleteFriendGroup(group.id);
    await _settle();
    expect(st.contactByName('沈星回')!.groupId, isNull);
    expect(st.contactGroups.any((g) => g.id == group.id), isFalse);

    // 分组筛选：未分组（id 为空串）应只剩回落的好友
    st.selectContactGroup('');
    expect(st.visibleContacts.every((c) => (c.groupId ?? '').isEmpty), isTrue);
    st.selectContactGroup(null);
    expect(st.visibleContacts.length, st.contacts.length);

    // 删除好友
    st.deleteFriend('沈星回');
    await _settle();
    expect(st.contacts.any((c) => c.account == '10008'), isFalse);
  });

  testWidgets('好友管理页能打开添加好友浮层', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final st = QAppState(preset: 'main');
    addTearDown(st.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FriendsManagerScreen(state: st),
        ),
      ),
    );
    expect(find.text('+ 添加好友'), findsOneWidget);
    expect(find.text('QQ好友管理'), findsOneWidget);

    await tester.tap(find.text('+ 添加好友'));
    await tester.pump();
    expect(st.contactDialog, QContactDialog.addFriend);
    expect(find.text('添加好友'), findsOneWidget);
    // 好友管理页搜索框 + 添加好友的「查找」与「验证消息」输入框
    expect(find.byType(TextField), findsNWidgets(3));

    st.closeContactsDialog();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('设计稿画廊保持静态气泡与照片卡', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final st = QAppState(preset: 'main');
    addTearDown(st.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FriendsManagerScreen(state: st, staticPreview: true),
        ),
      ),
    );
    expect(find.text('+ 添加好友'), findsNothing);
    expect(find.text('陈华'), findsOneWidget);
    expect(find.text('大学好友'), findsNWidgets(2));
  });
}

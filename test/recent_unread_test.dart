import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/models.dart';
import 'package:qq_concept/frontend/window_content.dart';

void main() {
  test('未读快照、实时消息和已读游标不会互相覆盖', () {
    final state = QAppState(preset: 'main');
    addTearDown(state.dispose);
    state.applyUnreadSnapshot('好友', 2, 5, 1);
    state.addUnread('好友', 5);
    state.addUnread('好友', 6);
    state.addUnread('好友', 6);
    expect(state.unreadFor('好友'), 3);
    state.markConversationRead('好友', 5);
    expect(state.unreadFor('好友'), 1);
    state.applyUnreadSnapshot('好友', 2, 5, 1);
    expect(state.unreadFor('好友'), 1);
    state.markConversationRead('好友', 6);
    expect(state.unreadFor('好友'), 0);
  });

  test('本地打开聊天只清除已有未读，不影响后续消息', () {
    final state = QAppState(preset: 'main');
    addTearDown(state.dispose);
    state.applyUnreadSnapshot('好友', 1, 2, 0);
    state.addUnread('好友', 3);
    state.open(QWindowKind.chat, friend: '好友');
    expect(state.unreadFor('好友'), 0);
    state.addUnread('好友', 4);
    expect(state.unreadFor('好友'), 1);
  });

  testWidgets('好友未读头像抖动，打开后清除，最近聊天按消息排序', (tester) async {
    tester.view.physicalSize = const Size(272, 645);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = QAppState(preset: 'main');
    addTearDown(state.dispose);
    final first = qFriendFromApi('好友甲', '签名甲');
    final second = qFriendFromApi('好友乙', '签名乙');
    state.applyBackendData(
      groups: [
        QFriendGroup('朋友(0/2)', [first, second]),
      ],
      friends: [first, second],
    );
    state.toggleGroup('朋友(0/2)');
    final now = DateTime.now();
    state.addBackendMessage(
      '好友乙',
      QMessage('较早消息', false, now.subtract(const Duration(minutes: 2)), seq: 1),
    );
    state.addBackendMessage('好友甲', QMessage('最新消息', false, now, seq: 2));
    state.applyUnreadSnapshot('好友甲', 2, 2, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ListenableBuilder(
            listenable: state,
            builder: (_, _) => buildQWindowContent(
              state,
              state.windows.firstWhere((w) => w.kind == QWindowKind.panel),
              onWindowButton: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('unread-好友甲')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    var transform = tester.widget<Transform>(
      find.byKey(const ValueKey('shake-好友甲')),
    );
    expect(transform.transform.getTranslation().x.abs(), greaterThan(1));

    final row = find.text('好友甲');
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row);
    await tester.pump();
    expect(state.isChatVisible('好友甲'), isTrue);
    expect(state.unreadFor('好友甲'), 0);
    expect(find.byKey(const ValueKey('unread-好友甲')), findsNothing);
    transform = tester.widget<Transform>(
      find.byKey(const ValueKey('shake-好友甲')),
    );
    expect(transform.transform.getTranslation().x, 0);

    state.setPanelTab(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('最近聊天'), findsOneWidget);
    expect(find.text('最新消息'), findsOneWidget);
    expect(find.text('较早消息'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('好友甲')).dy,
      lessThan(tester.getTopLeft(find.text('好友乙')).dy),
    );
  });
}

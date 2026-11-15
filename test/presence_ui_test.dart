import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qq_concept/core/models.dart';
import 'package:qq_concept/screens/main_panel.dart';
import 'package:qq_concept/screens/login_screen.dart';
import 'package:qq_concept/core/app_state.dart';

void main() {
  testWidgets('登录按钮左侧可选择登录后的状态', (tester) async {
    tester.view.physicalSize = const Size(372, 282);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = QAppState(preset: 'login');
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ListenableBuilder(
            listenable: state,
            builder: (_, _) => LoginScreen(
              presence: state.loginPresence,
              onPresenceChanged: state.setLoginPresence,
              onLogin: state.login,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('login-presence-selector')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<QPresence>),
        matching: find.text('忙碌'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.loginPresence, QPresence.busy);
    state.setPassword('password');
    state.login();
    expect(state.myPresence, QPresence.busy);
    expect(state.loggedIn, isTrue);
  });

  testWidgets('可以切换四种状态并显示好友状态和分组在线数', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(272, 645);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var mine = QPresence.online;
    var friend = QPresence.away;
    late StateSetter update;
    final row = qFriendFromApi('好友', '签名');

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MainPanel(
                myPresence: mine,
                friendPresence: {'好友': friend},
                friendGroups: [
                  QFriendGroup('朋友(0/1)', [row]),
                ],
                expandedGroup: '朋友(0/1)',
                onPresenceChanged: (value) => setState(() => mine = value),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('朋友(1/1)'), findsOneWidget);
    expect(find.text('离开'), findsOneWidget);

    for (final status in QPresence.values) {
      await tester.tap(find.byKey(const ValueKey('presence-selector')));
      await tester.pumpAndSettle();
      final item = find.descendant(
        of: find.byType(PopupMenuItem<QPresence>),
        matching: find.text(status.label),
      );
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(mine, status);
    }

    update(() => friend = QPresence.offline);
    await tester.pump();
    expect(find.text('朋友(0/1)'), findsOneWidget);
    expect(find.text('离线'), findsOneWidget);
  });
}

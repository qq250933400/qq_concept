import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qq_concept/core/models.dart';
import 'package:qq_concept/screens/main_panel.dart';

void main() {
  testWidgets('可以切换四种状态并显示好友状态和分组在线数', (tester) async {
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
                friendGroups: [QFriendGroup('朋友(0/1)', [row])],
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

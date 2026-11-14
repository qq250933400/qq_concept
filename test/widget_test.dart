import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/app_shell.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/frontend/desktop.dart';
import 'package:qq_concept/main.dart';

void main() {
  testWidgets('默认入口是交互应用桌面，不是设计稿画廊', (WidgetTester tester) async {
    // 单画布入口（web / 非窗口化环境），不走 runWidget 的 ViewCollection。
    await tester.pumpWidget(QQConceptApp(state: QAppState(preset: 'main')));
    expect(find.byType(QDesktop), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('交互应用'), findsOneWidget);
    expect(find.text('任务栏'), findsOneWidget);
  });
}

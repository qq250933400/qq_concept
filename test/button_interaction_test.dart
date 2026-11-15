import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qq_concept/core/widgets.dart';
import 'package:qq_concept/screens/chat_screen.dart';

void main() {
  testWidgets('按钮悬停、按下和取消时显示对应状态，点击仍然生效', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MetalButton(label: '保存', onTap: () => taps++),
        ),
      ),
    );

    final button = find.byType(QButtonInteraction);
    AnimatedScale scale() => tester.widget<AnimatedScale>(
      find.descendant(of: button, matching: find.byType(AnimatedScale)),
    );
    Color? overlay() {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: button, matching: find.byType(AnimatedContainer)),
      );
      return (container.decoration! as BoxDecoration).color;
    }

    expect(overlay(), Colors.transparent);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump();
    expect(overlay(), const Color(0x33FFFFFF));
    expect(scale().scale, 1);

    await mouse.down(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    expect(overlay(), const Color(0x33000000));
    expect(scale().scale, .97);
    await mouse.up();
    await tester.pump();
    expect(taps, 1);
    expect(overlay(), const Color(0x33FFFFFF));
    expect(scale().scale, 1);

    await mouse.down(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    await mouse.cancel();
    await tester.pump();
    expect(taps, 1);
    expect(scale().scale, 1);
    await mouse.removePointer();
  });

  testWidgets('禁用按钮没有悬停或按下反馈', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: MetalButton(label: '保存'))),
    );
    final button = find.byType(QButtonInteraction);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump();
    expect(
      find.descendant(of: button, matching: find.byType(AnimatedScale)),
      findsNothing,
    );
    await mouse.removePointer();
  });

  testWidgets('聊天发送按钮保留发送行为', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: ChatScreen(onSend: sent.add)),
      ),
    );
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    expect(sent, ['你好']);
  });
}

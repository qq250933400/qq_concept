import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/avatars.dart';
import 'package:qq_concept/core/profile.dart';
import 'package:qq_concept/screens/register_screen.dart';

/// 注册窗口与资料字段的离线测试：不依赖服务端。
void main() {
  test('内置头像 URL 编解码往返一致', () {
    for (var i = 0; i < kQBuiltinAvatars.length; i++) {
      expect(qBuiltinAvatarIndex(qBuiltinAvatarUrl(i)), i);
    }
    expect(qBuiltinAvatarIndex(null), isNull);
    expect(qBuiltinAvatarIndex('https://example.com/a.png'), isNull);
    expect(qBuiltinAvatarIndex('builtin://avatar/999'), isNull);
    expect(qBuiltinAvatarIndex('builtin://avatar/x'), isNull);
  });

  test('注册表单校验：帐号 / 昵称 / 密码 / 二次确认', () {
    QRegistration reg({
      String account = 'zhangsan',
      String nickname = '张三',
      String password = 'Passw0rd!',
      String confirm = 'Passw0rd!',
    }) =>
        QRegistration(
          account: account,
          nickname: nickname,
          password: password,
          passwordConfirm: confirm,
        );

    expect(reg().validate(), isNull);
    expect(reg(account: 'ab').validate(), contains('帐号'));
    expect(reg(account: '含 空格').validate(), contains('帐号'));
    expect(reg(nickname: '   ').validate(), contains('昵称'));
    expect(reg(password: '12345').validate(), contains('密码'));
    expect(reg(confirm: 'Passw0rd!x').validate(), contains('不一致'));
  });

  test('性别枚举与服务端 code 对齐', () {
    expect(QGender.fromCode(0), QGender.secret);
    expect(QGender.fromCode(1), QGender.male);
    expect(QGender.fromCode(2), QGender.female);
    expect(QGender.fromCode(null), QGender.secret);
    expect(QGender.fromCode(9), QGender.secret);
    expect(QGender.male.code, 1);
    expect(QGender.female.label, '女');
  });

  test('注册窗开关与离线拒绝提示', () async {
    final st = QAppState(preset: 'login');
    addTearDown(st.dispose);
    expect(st.windows.any((w) => w.kind.name == 'register'), isFalse);

    st.openRegisterWindow();
    expect(st.windows.any((w) => w.kind.name == 'register'), isTrue);

    // backend 为空（离线）时拒绝注册，并给出内联错误。
    st.submitRegistration(const QRegistration(
      account: 'zhangsan',
      nickname: '张三',
      password: 'Passw0rd!',
      passwordConfirm: 'Passw0rd!',
      gender: QGender.male,
      avatarIndex: 3,
    ));
    expect(st.registerError, contains('API'));

    st.closeRegisterWindow();
    expect(st.windows.any((w) => w.kind.name == 'register'), isFalse);
  });

  testWidgets('注册窗口渲染 6 个字段并做本地校验', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(760, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final st = QAppState(preset: 'register');
    addTearDown(st.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: RegisterScreen(state: st)),
      ),
    );

    expect(find.text('注册新帐号'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    // 性别三个选项 + 8 个内置头像。
    expect(find.text('保密'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('女'), findsOneWidget);
    expect(find.text('注册并登录'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 密码与二次确认不一致 → 点击注册应显示本地校验错误，而不是发请求。
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'zhangsan');
    await tester.enterText(fields.at(1), '张三');
    await tester.enterText(fields.at(2), 'Passw0rd!');
    await tester.enterText(fields.at(3), 'Passw0rd!x');
    await tester.tap(find.text('注册并登录'));
    await tester.pump();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);

    // 改回一致 → 离线（backend null）应提示需要 API 服务。
    await tester.enterText(fields.at(3), 'Passw0rd!');
    await tester.tap(find.text('注册并登录'));
    await tester.pump();
    expect(find.text('注册需要连接 API 服务'), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/api/api_client.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/profile.dart';
import 'package:qq_concept/frontend/window_content.dart';

void main() {
  testWidgets('修改昵称时显示重复错误，成功后更新主面板', (tester) async {
    tester.view.physicalSize = const Size(272, 645);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requests = <String>[];
    final client = QApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        final nickname = jsonDecode(request.body)['nickname'] as String;
        requests.add(nickname);
        final body = nickname == '已使用'
            ? {'code': 'NICKNAME_EXISTS', 'message': '昵称已被使用'}
            : {'nickname': nickname};
        return http.Response(
          jsonEncode(body),
          nickname == '已使用' ? 409 : 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final state = QAppState(preset: 'main')..displayName = '原昵称';
    final bridge = QApiBridge(state, apiClient: client);
    state.backend = bridge;
    addTearDown(() async {
      await bridge.dispose();
      state.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ListenableBuilder(
            listenable: state,
            builder: (context, _) => buildQWindowContent(
              state,
              state.windows.first,
              onWindowButton: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('edit-nickname')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '已使用');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('昵称已被使用'), findsOneWidget);
    expect(state.displayName, '原昵称');

    await tester.enterText(find.byType(TextField).last, ' 新昵称 ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('修改昵称'), findsNothing);
    expect(find.text('新昵称'), findsOneWidget);
    expect(requests, ['已使用', '新昵称']);
  });

  test('注册遇到重复昵称时显示服务端错误', () async {
    final client = QApiClient(
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'code': 'NICKNAME_EXISTS', 'message': '昵称已被使用'}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final state = QAppState(preset: 'register');
    final bridge = QApiBridge(state, apiClient: client);
    state.backend = bridge;
    addTearDown(() async {
      await bridge.dispose();
      state.dispose();
    });
    state.submitRegistration(
      const QRegistration(
        account: 'test123',
        nickname: '已使用',
        password: 'password',
        passwordConfirm: 'password',
      ),
    );
    while (state.registerBusy) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(state.registerError, '昵称已被使用');
    expect(state.loggedIn, isFalse);
  });
}

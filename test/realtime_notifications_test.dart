import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/api/api_client.dart';
import 'package:qq_concept/api/api_models.dart';
import 'package:qq_concept/api/ws_gateway.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:qq_concept/core/models.dart';
import 'package:qq_concept/frontend/window_content.dart';

class _Gateway extends QWsGateway {
  _Gateway() : super(apiBase: 'http://localhost/v1', deviceId: 'test');
  final controller = StreamController<QFrame>.broadcast(sync: true);

  @override
  Stream<QFrame> get frames => controller.stream;
  @override
  bool get connected => true;
  @override
  Future<void> connect(Future<String> Function() tokenProvider) async {}
  @override
  Future<void> close() async {}

  void emit(String type, Map<String, dynamic> data) {
    controller.add(QFrame.fromJson({'type': type, 'data': data}));
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待实时事件超时');
}

void main() {
  test('好友事件刷新列表，消息按窗口状态通知且重复帧不重复提示', () async {
    var friendAdded = false;
    var incomingRequest = false;
    var conversationCreated = false;
    var failPresence = false;
    String? sentPresence;
    var catchUpMessages = <Map<String, dynamic>>[];
    final requests = <String>[];
    final client = QApiClient(
      baseUrl: 'http://localhost/v1',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        requests.add(path);
        Object response;
        switch (path) {
          case '/v1/auth/login':
            response = {
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': 'me'},
            };
          case '/v1/users/me':
            response = {
              'id': 'me',
              'account': '123',
              'nickname': '真实昵称',
              'signature': '真实签名',
              'presence': 'online',
            };
          case '/v1/friends':
            response = {
              'groups': <Object>[],
              'items': friendAdded
                  ? [
                      {
                        'id': 'peer',
                        'account': '456',
                        'nickname': '好友',
                        'presence': 'away',
                      },
                    ]
                  : <Object>[],
            };
          case '/v1/friend-requests':
            response = {
              'items':
                  request.url.queryParameters['direction'] == 'in' &&
                      incomingRequest
                  ? [
                      {'id': 'request', 'account': '456', 'nickname': '好友'},
                    ]
                  : <Object>[],
            };
          case '/v1/conversations':
            response = {
              'items': conversationCreated
                  ? [
                      {'id': 'conv', 'peer_id': 'peer', 'peer_nickname': '好友'},
                    ]
                  : <Object>[],
            };
          case '/v1/conversations/conv/messages':
            response = {'items': catchUpMessages};
          case '/v1/settings':
            response = {'settings': <String, Object>{}};
          case '/v1/users/me/presence':
            sentPresence = (jsonDecode(request.body) as Map<String, dynamic>)['status'] as String;
            if (failPresence) {
              return http.Response('{"message":"status failed"}', 503);
            }
            response = {'status': sentPresence};
          default:
            return http.Response('{"message":"unexpected $path"}', 404);
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(response)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final gateway = _Gateway();
    final state = QAppState(preset: 'login');
    final bridge = QApiBridge(state, apiClient: client, gateway: gateway);
    state.backend = bridge;
    final notices = <(String, String, String?, bool)>[];
    state.onIncomingNotification = (title, body, chat, sound) {
      notices.add((title, body, chat, sound));
    };
    addTearDown(() async {
      await bridge.dispose();
      await gateway.controller.close();
      state.dispose();
    });

    await bridge.login('123', 'password');
    expect(state.displayName, '真实昵称');
    expect(state.signature, '真实签名');

    incomingRequest = true;
    gateway.emit('friend_request.new', {'from_nickname': '好友'});
    await _waitFor(() => state.pendingRequestCount == 1);
    expect(notices.last, ('好友申请', '好友 申请加你为好友', null, true));

    friendAdded = true;
    gateway.emit('friend.accepted', {'by_nickname': '好友'});
    await _waitFor(() => state.friends.any((f) => f.name == '好友'));
    expect(notices.last.$2, '好友 已同意你的好友申请');
    expect(state.presence['好友'], QPresence.away);
    state.setBackendConnected(true);
    await state.changePresence(QPresence.away);
    expect(sentPresence, 'away');
    expect(state.myPresence, QPresence.away);
    gateway.emit('presence', {'user_id': 'peer', 'status': 'busy'});
    expect(state.presence['好友'], QPresence.busy);
    gateway.emit('presence', {'user_id': 'me', 'status': 'offline'});
    expect(state.myPresence, QPresence.offline);
    failPresence = true;
    await state.changePresence(QPresence.online);
    expect(state.myPresence, QPresence.offline);
    expect(state.toast, contains('修改在线状态失败'));
    failPresence = false;

    conversationCreated = true;
    Map<String, dynamic> message(String id, int seq) => {
      'message': {
        'id': id,
        'conversation_id': 'conv',
        'sender_id': 'peer',
        'seq': seq,
        'content': {'text': '你好'},
      },
    };
    gateway.emit('msg.new', message('m1', 1));
    await _waitFor(() => state.thread('好友').length == 1);
    expect(notices.last, ('新消息', '好友 发来一条消息', null, true));
    expect(requests, isNot(contains('/v1/conversations/conv/messages')));

    state.open(QWindowKind.chat, friend: '好友');
    state.setSetting('sound', false);
    gateway.emit('msg.new', message('m2', 2));
    await _waitFor(() => state.thread('好友').length == 2);
    expect(notices.last, ('新消息', '好友 发来一条消息', 'chat:好友', false));
    final count = notices.length;
    gateway.emit('msg.new', message('m2', 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notices.length, count);

    state.minimize('chat:好友');
    gateway.emit('msg.new', message('m3', 3));
    await _waitFor(() => state.thread('好友').length == 3);
    expect(notices.last.$3, isNull);

    catchUpMessages = [(message('m4', 4)['message'] as Map<String, dynamic>)];
    friendAdded = false;
    gateway.emit('ready', {
      'seqs': {'conv': 4},
    });
    await _waitFor(() => state.thread('好友').length == 4);
    await _waitFor(() => state.friends.isEmpty);
    expect(notices.last.$3, isNull);
    final afterCatchUp = notices.length;
    gateway.emit('msg.new', message('m4', 4));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notices.length, afterCatchUp);
    expect(requests, isNot(contains('/v1/conversations/conv/read')));
  });

  testWidgets('主面板使用传入的昵称和签名', (tester) async {
    final state = QAppState(preset: 'main');
    final gateway = _Gateway();
    final bridge = QApiBridge(state, gateway: gateway);
    state.backend = bridge;
    state.setBackendNickname('真实昵称');
    state.setBackendSignature('真实签名');
    addTearDown(() async {
      await bridge.dispose();
      await gateway.controller.close();
      state.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: buildQWindowContent(
            state,
            QWindow(id: 'panel', kind: QWindowKind.panel),
            onWindowButton: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('真实昵称'), findsOneWidget);
    expect(find.text('真实签名'), findsOneWidget);
    expect(find.text('wzw'), findsNothing);
  });

  test('好友列表慢响应不会覆盖更新的实时状态', () async {
    final pendingResponse = Completer<http.Response>();
    final refreshStarted = Completer<void>();
    var friendCalls = 0;
    http.Response json(Object value) => http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
    final friends = {
      'groups': <Object>[],
      'items': [
        {'id': 'peer', 'account': '456', 'nickname': '好友', 'presence': 'online'},
      ],
    };
    final client = QApiClient(
      baseUrl: 'http://localhost/v1',
      httpClient: MockClient((request) async {
        switch (request.url.path) {
          case '/v1/auth/login':
            return json({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {'id': 'me'},
            });
          case '/v1/users/me':
            return json({'id': 'me', 'account': '123', 'nickname': '我'});
          case '/v1/friends':
            if (++friendCalls == 1) return json(friends);
            refreshStarted.complete();
            return pendingResponse.future;
          case '/v1/conversations':
          case '/v1/friend-requests':
            return json({'items': <Object>[]});
          case '/v1/settings':
            return json({'settings': <String, Object>{}});
          default:
            return http.Response('not found', 404);
        }
      }),
    );
    final gateway = _Gateway();
    final state = QAppState(preset: 'login');
    final bridge = QApiBridge(state, apiClient: client, gateway: gateway);
    addTearDown(() async {
      await bridge.dispose();
      await gateway.controller.close();
      state.dispose();
    });
    await bridge.login('123', 'password');
    final refresh = bridge.refreshContacts();
    await refreshStarted.future;
    gateway.emit('presence', {'user_id': 'peer', 'status': 'busy'});
    pendingResponse.complete(json(friends));
    await refresh;
    expect(state.presence['好友'], QPresence.busy);
  });

  test('刷新分组计数时保持展开状态', () {
    final state = QAppState(preset: 'main');
    addTearDown(state.dispose);
    state.expandedGroup = '未分组(1/1)';
    state.applyBackendData(
      groups: [const QFriendGroup('未分组(2/2)', [])],
      friends: [],
    );
    expect(state.expandedGroup, '未分组(2/2)');
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qq_concept/api/api_bridge.dart';
import 'package:qq_concept/api/api_client.dart';
import 'package:qq_concept/api/api_config.dart';
import 'package:qq_concept/core/app_state.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 真实 API 集成测试：需先启动 qq-server（含 seed 数据）。
///
///   cd qq-server && npm run build && npm run migrate && npm run seed && npm start
///   cd qq_concept && flutter test --dart-define=RUN_API_TEST=true \
///       test/api_integration_test.dart
///
/// 默认跳过，保证普通 `flutter test` 在离线环境也能全绿。
const bool _run = bool.fromEnvironment('RUN_API_TEST');

void main() {
  test(
    '客户端通过 REST + WS 完成登录 / 关系链 / 会话 / 消息 / 设置 / 登出',
    () async {
      final state = QAppState(preset: 'login');
      final bridge = QApiBridge(state);
      state.backend = bridge;
      addTearDown(() async {
        await bridge.dispose();
        state.dispose();
      });

      // 1. 登录 → 自动 bootstrap（好友分组、会话历史、设置）
      await bridge.login('10001', 'Passw0rd!');
      expect(state.loggedIn, isTrue, reason: '登录成功后应切到主面板');
      expect(state.windows.any((w) => w.kind.name == 'login'), isFalse);
      expect(state.friendGroups, isNotNull);
      expect(state.friendGroups!.length, 6, reason: 'seed 的 6 个分组');
      expect(state.friends.length, 6, reason: 'seed 的 6 位好友');
      expect(
        state.threads.values.any((list) => list.isNotEmpty),
        isTrue,
        reason: '历史消息应回填到 threads',
      );

      // 2. 打开会话 → 拉历史 + 已读上报
      await bridge.openConversation('阿澈');
      final before = state.thread('阿澈').length;
      expect(before, greaterThan(0));

      // 3. 发消息：乐观插入 → WS msg.ack 确认 pending 落定
      final text = 'Dart 集成测试 ${DateTime.now().millisecondsSinceEpoch}';
      await bridge.send('阿澈', text);
      expect(state.thread('阿澈').length, before + 1);
      expect(state.thread('阿澈').last.text, text);
      for (var i = 0; i < 40; i++) {
        if (!state.thread('阿澈').last.pending) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(state.thread('阿澈').last.pending, isFalse,
          reason: 'msg.ack 应把乐观消息标记为已确认');
      expect(state.thread('阿澈').last.clientMsgId, isNotNull);

      // 3.5 对方（10002 阿澈）从另一条 WS 连接发消息，本端应实时收到
      final peer = QApiClient();
      addTearDown(peer.dispose);
      await peer.login('10002', 'Passw0rd!');
      final peerConv = await peer.createConversation(bridge.client.userId!);
      final peerWs = WebSocketChannel.connect(
        Uri.parse(qResolveWsUrl(peer.baseUrl)).replace(
          queryParameters: <String, String>{
            'token': peer.accessToken!,
            'device_id': peer.deviceId,
          },
        ),
      );
      await peerWs.ready;
      final incoming =
          '来自阿澈的实时消息 ${DateTime.now().millisecondsSinceEpoch}';
      peerWs.sink.add(jsonEncode(<String, dynamic>{
        'type': 'msg.send',
        'id': 'peer-1',
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': <String, dynamic>{
          'client_msg_id': 'peer-${DateTime.now().microsecondsSinceEpoch}',
          'conversation_id': peerConv['id'],
          'type': 1,
          'content': <String, dynamic>{'text': incoming},
        },
      }));
      var received = false;
      for (var i = 0; i < 40; i++) {
        if (state.thread('阿澈').any((m) => m.text == incoming && !m.self)) {
          received = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(received, isTrue, reason: 'msg.new 应路由到阿澈的聊天窗');
      await peerWs.sink.close();

      // 4. 服务端确实落库（不是只改了本地内存）
      final convs = await bridge.client.conversations();
      final rows = (convs['items'] as List).cast<Map<String, dynamic>>();
      final conv = rows.firstWhere(
        (r) => r['peer_nickname']?.toString() == '阿澈',
      );
      final history = await bridge.client.messages(conv['id'].toString());
      final messages = (history['items'] as List).cast<Map<String, dynamic>>();
      expect(
        messages.any((m) =>
            (m['content'] is Map) && m['content']['text'] == text),
        isTrue,
        reason: '消息应写入 MySQL 并能通过 REST 查到',
      );

      // 5. 设置写入后可读回
      await bridge.saveSettings(<String, bool>{
        'autoStart': true,
        'alwaysOnTop': false,
        'autoHide': false,
        'sound': true,
        'sendCtrlEnter': true,
      });
      final saved = await bridge.client.settings();
      expect((saved['settings'] as Map)['sound'], isTrue);

      // 6. 登出清理本机 token
      await bridge.logout();
      expect(bridge.client.signedIn, isFalse);
      expect(bridge.connected, isFalse);
    },
    skip: !_run,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}

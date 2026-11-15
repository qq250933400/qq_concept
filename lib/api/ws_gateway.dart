import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_config.dart';
import 'api_models.dart';

/// WS 网关客户端：自动重连、心跳、断线期间帧排队。
///
/// 网关本身无状态，重连到任意一台 API 实例都能靠 `ready.seqs` +
/// `after_seq` 补齐断线期间的消息（可靠性规则 3），客户端无需粘滞路由。
class QWsGateway {
  QWsGateway({required String apiBase, required this.deviceId})
    : _wsUrl = qResolveWsUrl(apiBase);

  final String _wsUrl;
  final String deviceId;

  final StreamController<QFrame> _frames =
      StreamController<QFrame>.broadcast();
  final List<String> _outbox = <String>[];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _retry;
  Future<String> Function()? _tokenProvider;
  void Function(bool connected)? onStatus;
  bool _manuallyClosed = true;
  bool _connected = false;
  int _attempt = 0;
  int _frameId = 0;

  Stream<QFrame> get frames => _frames.stream;
  bool get connected => _connected;

  Future<void> connect(Future<String> Function() tokenProvider) async {
    _tokenProvider = tokenProvider;
    _manuallyClosed = false;
    _retry?.cancel();
    await _open();
  }

  Future<void> _open() async {
    if (_manuallyClosed) return;
    try {
      final token = await _tokenProvider!();
      final uri = Uri.parse(_wsUrl).replace(
        queryParameters: <String, String>{
          'token': token,
          'device_id': deviceId,
        },
      );
      final channel = WebSocketChannel.connect(uri);
      // 等握手结果：connect() 是惰性的，失败时 ready 会抛错。
      await channel.ready;
      _channel = channel;
      _attempt = 0;
      _setConnected(true);
      _subscription = channel.stream.listen(
        (dynamic raw) {
          if (raw is String) {
            try {
              _frames.add(QFrame.fromJson(qDecode(raw)));
            } catch (_) {
              // 忽略畸形帧，不让单个坏包打断连接。
            }
          }
        },
        onError: (Object _) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: true,
      );
      _startHeartbeat();
      _flush();
    } catch (error) {
      // 异常文本里可能带完整 URL（含 token），日志必须脱敏。
      final safe = error
          .toString()
          .replaceAll(RegExp(r'token=[^&\s]+'), 'token=***');
      if (kDebugMode) debugPrint('[QQ][WS] 握手失败：$safe');
      _setConnected(false);
      _scheduleRetry();
    }
  }

  void _handleDrop() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _heartbeat?.cancel();
    _setConnected(false);
    if (!_manuallyClosed) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_manuallyClosed || _retry?.isActive == true) return;
    _attempt += 1;
    final delay = Duration(
      milliseconds: (500 * (1 << (_attempt > 4 ? 4 : _attempt - 1))),
    );
    _retry = Timer(delay, () => unawaited(_open()));
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // 服务端 30s 未收到 pong 会断开；客户端 20s 主动发一次 JSON ping。
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_connected) send('ping', const <String, dynamic>{});
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onStatus?.call(value);
  }

  /// 返回帧 id，便于把 `msg.ack` 与本地乐观消息对齐。
  String send(String type, Map<String, dynamic> data) {
    final id = 'c-${++_frameId}';
    final envelope = jsonEncode(<String, dynamic>{
      'type': type,
      'id': id,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
    if (_connected) {
      try {
        _channel?.sink.add(envelope);
      } catch (_) {
        _outbox.add(envelope);
      }
    } else {
      // 断线期间最多缓存 200 帧，避免无限增长；重连后按序发送，
      // client_msg_id 幂等保证重发不会产生重复消息。
      if (_outbox.length < 200) _outbox.add(envelope);
    }
    return id;
  }

  void _flush() {
    final queued = List<String>.from(_outbox);
    _outbox.clear();
    for (final frame in queued) {
      try {
        _channel?.sink.add(frame);
      } catch (_) {
        _outbox.add(frame);
      }
    }
  }

  Future<void> close() async {
    _manuallyClosed = true;
    _retry?.cancel();
    _heartbeat?.cancel();
    _setConnected(false);
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {
      // 已断开时忽略。
    }
    _channel = null;
    _outbox.clear();
  }
}

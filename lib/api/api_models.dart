import 'dart:convert';

/// 服务端 JSON 解析（snake_case，时间 ISO8601 UTC）。
/// 所有字段都做容错：服务端可选字段缺失时不会让界面崩。

String _s(Map<String, dynamic> j, String key, [String fallback = '']) =>
    j[key] == null ? fallback : j[key].toString();

int _i(dynamic v) => v is int
    ? v
    : (v is double ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

DateTime _t(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

class ApiUser {
  ApiUser.fromJson(Map<String, dynamic> j)
    : id = _s(j, 'id'),
      account = _s(j, 'account'),
      nickname = _s(j, 'nickname'),
      avatarUrl = j['avatar_url']?.toString(),
      signature = j['signature']?.toString(),
      gender = _i(j['gender']);

  final String id;
  final String account;
  final String nickname;
  final String? avatarUrl;
  final String? signature;

  /// 0 保密 / 1 男 / 2 女（与 core/profile.dart 的 QGender 对齐）。
  final int gender;
}

class ApiFriend {
  ApiFriend.fromJson(Map<String, dynamic> j)
    : id = _s(j, 'id'),
      groupId = j['group_id']?.toString(),
      remark = j['remark']?.toString(),
      account = _s(j, 'account'),
      nickname = _s(j, 'nickname', _s(j, 'account')),
      signature = j['signature']?.toString() ?? '',
      status = _i(j['status']);

  final String id;
  final String? groupId;
  final String? remark;
  final String account;
  final String nickname;
  final String signature;
  final int status;
}

class ApiGroup {
  ApiGroup.fromJson(Map<String, dynamic> j)
    : id = _s(j, 'id'),
      name = _s(j, 'name'),
      sort = _i(j['sort']);

  final String id;
  final String name;
  final int sort;
}

class ApiConversation {
  ApiConversation.fromJson(Map<String, dynamic> j)
    : id = _s(j, 'id'),
      peerId = _s(j, 'peer_id'),
      peerNickname = _s(j, 'peer_nickname'),
      lastSeq = _i(j['last_seq']),
      readSeq = _i(j['read_seq']),
      unread = _i(j['unread']);

  final String id;
  final String peerId;
  final String peerNickname;
  final int lastSeq;
  final int readSeq;
  final int unread;
}

class ApiMessage {
  ApiMessage.fromJson(Map<String, dynamic> j)
    : id = _s(j, 'id'),
      conversationId = _s(j, 'conversation_id'),
      seq = _i(j['seq']),
      senderId = _s(j, 'sender_id'),
      clientMsgId = j['client_msg_id']?.toString(),
      text = (() {
        final c = j['content'];
        if (c is Map) return (c['text'] ?? c['body'] ?? '').toString();
        return c?.toString() ?? '';
      })(),
      createdAt = _t(j['created_at']),
      revoked = j['revoked_at'] != null;

  final String id;
  final String conversationId;
  final int seq;
  final String senderId;
  final String? clientMsgId;
  final String text;
  final DateTime createdAt;
  final bool revoked;
}

class QFrame {
  QFrame.fromJson(Map<String, dynamic> j)
    : type = _s(j, 'type'),
      id = j['id']?.toString(),
      ts = _i(j['ts']),
      data = j['data'] is Map
          ? Map<String, dynamic>.from(j['data'] as Map)
          : const <String, dynamic>{};

  final String type;
  final String? id;
  final int ts;
  final Map<String, dynamic> data;
}

Map<String, dynamic> qDecode(String body) {
  final decoded = jsonDecode(body);
  return decoded is Map
      ? Map<String, dynamic>.from(decoded)
      : <String, dynamic>{};
}

List<Map<String, dynamic>> qList(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false)
    : const <Map<String, dynamic>>[];

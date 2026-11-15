import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../core/app_state.dart';
import '../core/avatars.dart';
import '../core/backend.dart';
import '../core/contacts.dart';
import '../core/models.dart';
import '../core/profile.dart';
import 'api_client.dart';
import 'api_models.dart';
import 'ws_gateway.dart';

/// 把 [QAppState] 接到真实 API：
/// REST 负责登录 / 关系链 / 会话 / 设置 / 历史，WS 负责实时收发与断线补偿。
///
/// 名字是 UI 的主键（聊天窗按好友名开），服务端用 UUID，因此这里维护
/// 双向映射；消息用 client_msg_id + seq 做去重，避免乐观消息与 WS 回帧重复。
class QApiBridge implements QBackend {
  QApiBridge(this.state) {
    client = QApiClient();
    ws = QWsGateway(apiBase: client.baseUrl, deviceId: client.deviceId);
    ws.onStatus = state.setBackendConnected;
    _frames = ws.frames.listen(_onFrame);
  }

  final QAppState state;
  late final QApiClient client;
  late final QWsGateway ws;
  StreamSubscription<QFrame>? _frames;

  final Map<String, String> _friendIdByName = <String, String>{};
  final Map<String, String> _friendNameById = <String, String>{};
  final Map<String, String> _convByFriend = <String, String>{};
  final Map<String, String> _friendByConv = <String, String>{};
  final Map<String, int> _seqByConv = <String, int>{};
  final Map<String, String> _clientMsgToFriend = <String, String>{};
  final Set<String> _seenIds = <String>{};
  DateTime? _expiresAt;
  int _localSeq = 0;

  @override
  bool get connected => ws.connected;

  void _log(String message) {
    // 只记事件与数量，不打印 token / 密码 / 消息正文。
    if (kDebugMode) debugPrint('[QQ][API] $message');
  }

  // ------------------------------------------------------------ 认证
  @override
  Future<void> login(String account, String password) async {
    final json = await client.login(account, password);
    _expiresAt = DateTime.now().add(
      Duration(seconds: int.tryParse(json['expires_in']?.toString() ?? '') ?? 900),
    );
    _resetCaches();
    await _bootstrap();
    _log('登录成功：${state.friends.length} 位好友 / '
        '${state.friendGroups?.length ?? 0} 个分组 / '
        '${state.threads.length} 个会话');
    state.onBackendLoggedIn(account);
    await _connectWs();
    _log('WS ${ws.connected ? '已连接' : '连接中（将自动重连）'}');
  }

  @override
  Future<void> register(QRegistration reg) async {
    final account = reg.account.trim();
    // 注册资料：昵称为空时服务端约定回落为帐号；头像存内置标识串。
    await client.register(
      account,
      reg.password,
      nickname: reg.nickname.trim(),
      gender: reg.gender.code,
      avatarUrl: qBuiltinAvatarUrl(reg.avatarIndex),
    );
    // 注册即登录：头像先本地回显，登录 bootstrap 会用 /users/me 覆盖确认。
    state.setBackendAvatarIndex(reg.avatarIndex);
    await login(account, reg.password);
  }

  @override
  Future<void> logout() async {
    await ws.close();
    await client.logout();
    _resetCaches();
  }

  void _resetCaches() {
    _friendIdByName.clear();
    _friendNameById.clear();
    _convByFriend.clear();
    _friendByConv.clear();
    _seqByConv.clear();
    _clientMsgToFriend.clear();
    _seenIds.clear();
    _expiresAt = null;
  }

  Future<void> _connectWs() async {
    await ws.connect(() async {
      // 重连时若 access token 已接近过期，先轮换再握手。
      final expires = _expiresAt;
      if (expires != null &&
          DateTime.now().isAfter(expires.subtract(const Duration(seconds: 60)))) {
        await client.refresh();
      }
      return client.accessToken ?? '';
    });
  }

  Future<void> _bootstrap() async {
    await _loadFriends();
    await _loadConversations();
    await _loadSettings();
    try {
      await _loadFriendRequests();
    } catch (_) {
      // 申请列表拉取失败不影响登录主流程，打开好友管理时会再拉一次。
    }
    try {
      final me = await client.me();
      state.setBackendNickname(me.nickname);
      state.setBackendAvatarIndex(qBuiltinAvatarIndex(me.avatarUrl));
    } catch (_) {
      // 个人资料拉取失败不影响主流程。
    }
  }

  Future<void> _loadFriends() async {
    final json = await client.friends();
    final groups = qList(json['groups'])
        .map(ApiGroup.fromJson)
        .toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final items = qList(json['items']).map(ApiFriend.fromJson).toList();
    _friendIdByName.clear();
    _friendNameById.clear();
    for (final f in items) {
      _friendIdByName[f.nickname] = f.id;
      _friendNameById[f.id] = f.nickname;
    }

    final knownGroups = groups.map((g) => g.id).toSet();
    final all = <QFriend>[];
    final result = <QFriendGroup>[];
    for (final g in groups) {
      final members = <QFriend>[];
      for (final f in items) {
        if (f.groupId != g.id) continue;
        members.add(qFriendFromApi(f.nickname, f.signature));
      }
      all.addAll(members);
      // 保留设计稿的「分组名(在线数/总数)」写法。
      result.add(QFriendGroup('${g.name}(${members.length}/${items.length})', members));
    }
    final orphans = items.where((f) => f.groupId == null || !knownGroups.contains(f.groupId));
    if (orphans.isNotEmpty) {
      final members = orphans
          .map((f) => qFriendFromApi(f.nickname, f.signature))
          .toList();
      all.addAll(members);
      result.add(QFriendGroup('未分组(${members.length}/${items.length})', members));
    }
    state.applyBackendData(groups: result, friends: all);

    // 同一份 /friends 响应同时回填关系链 DTO，好友管理窗口据此渲染与操作。
    // 「未分组」是虚拟分组（id 为空串），只在确实有散落好友时出现。
    final orphanCount = orphans.length;
    final dtoGroups = <QContactGroup>[
      for (final g in groups)
        QContactGroup(
          id: g.id,
          name: g.name,
          sort: g.sort,
          count: items.where((f) => f.groupId == g.id).length,
        ),
      if (orphanCount > 0)
        QContactGroup(
          id: '',
          name: '未分组',
          sort: 9999,
          count: orphanCount,
        ),
    ]..sort((a, b) => a.sort.compareTo(b.sort));
    state.applyContacts(
      groups: dtoGroups,
      contacts: <QContact>[
        for (final f in items)
          QContact(
            id: f.id,
            name: f.nickname,
            account: f.account,
            signature: f.signature,
            groupId: f.groupId,
          ),
      ],
    );
  }

  Future<void> _loadConversations() async {
    final json = await client.conversations();
    for (final raw in qList(json['items'])) {
      final conv = ApiConversation.fromJson(raw);
      final name = _friendNameById[conv.peerId] ?? conv.peerNickname;
      if (name.isEmpty) continue;
      _convByFriend[name] = conv.id;
      _friendByConv[conv.id] = name;
      _seqByConv[conv.id] = math.max(_seqByConv[conv.id] ?? 0, conv.lastSeq);
      final history = await client.messages(conv.id, limit: 50);
      final messages = _parseMessages(history);
      state.mergeBackendThread(name, messages);
      if (conv.lastSeq > conv.readSeq) {
        await client.markRead(conv.id, conv.lastSeq);
      }
    }
  }

  Future<void> _loadSettings() async {
    final json = await client.settings();
    final raw = json['settings'];
    if (raw is! Map) return;
    final values = <String, bool>{};
    for (final key in const <String>[
      'autoStart',
      'alwaysOnTop',
      'autoHide',
      'sound',
      'sendCtrlEnter',
    ]) {
      if (raw.containsKey(key)) {
        final v = raw[key];
        values[key] = v == true || v == 1 || v == 'true';
      }
    }
    if (values.isNotEmpty) state.applyBackendSettings(values);
  }

  @override
  Future<void> saveSettings(Map<String, bool> values) =>
      client.putSettings(values).then((_) {});

  // ------------------------------------------------------------ 关系链
  @override
  Future<void> refreshContacts() async {
    await _loadFriends();
    await _loadFriendRequests();
  }

  Future<void> _loadFriendRequests() async {
    final incoming = await client.friendRequests('in');
    final outgoing = await client.friendRequests('out');
    QFriendRequestInfo parse(Map<String, dynamic> r, String direction) =>
        QFriendRequestInfo(
          id: r['id']?.toString() ?? '',
          account: r['account']?.toString() ?? '',
          name: (r['nickname'] ?? r['account'] ?? '').toString(),
          message: r['message']?.toString() ?? '',
          status: int.tryParse(r['status']?.toString() ?? '') ?? 0,
          direction: direction,
          createdAt: r['created_at']?.toString() ?? '',
        );
    state.applyFriendRequests(<QFriendRequestInfo>[
      for (final r in incoming) parse(r, 'in'),
      for (final r in outgoing) parse(r, 'out'),
    ]);
  }

  @override
  Future<void> searchContacts(String query) async {
    final rows = await client.searchUsers(query.trim());
    state.applySearchResults(<QUserHit>[
      for (final r in rows)
        QUserHit(
          id: r['id']?.toString() ?? '',
          account: r['account']?.toString() ?? '',
          name: (r['nickname'] ?? r['account'] ?? '').toString(),
          signature: r['signature']?.toString() ?? '',
          isFriend: r['is_friend'] == true || r['is_friend'] == 1 ||
              r['is_friend'] == '1' || r['is_friend'] == 'true',
        ),
    ]);
  }

  @override
  Future<void> sendFriendRequest(String account, String message) async {
    await client.createFriendRequest(account.trim(), message: message);
    await _loadFriendRequests();
  }

  @override
  Future<void> acceptFriendRequest(String id) async {
    await client.acceptRequest(id);
    // 通过会双向写入关系，必须连同好友列表一起刷新。
    await refreshContacts();
  }

  @override
  Future<void> rejectFriendRequest(String id) async {
    await client.rejectRequest(id);
    await _loadFriendRequests();
  }

  @override
  Future<void> createFriendGroup(String name) async {
    await client.createGroup(name.trim(), state.contactGroups.length);
    await _loadFriends();
  }

  @override
  Future<void> renameFriendGroup(String id, String name) async {
    await client.renameGroup(id, name.trim());
    await _loadFriends();
  }

  @override
  Future<void> deleteFriendGroup(String id) async {
    await client.deleteGroup(id);
    await _loadFriends();
  }

  /// UI 用昵称作主键，这里换成服务端 user id。
  String _friendId(String name) {
    final id = _friendIdByName[name];
    if (id == null || id.isEmpty) {
      throw QApiException(404, 'NOT_FOUND', '找不到好友 $name');
    }
    return id;
  }

  @override
  Future<void> moveFriendToGroup(String name, String? groupId) async {
    // 虚拟「未分组」的 id 是空串，落到服务端就是 group_id = null。
    final target = (groupId == null || groupId.isEmpty) ? null : groupId;
    await client.patchFriend(
      _friendId(name),
      groupId: target,
      clearGroup: target == null,
    );
    await _loadFriends();
  }

  @override
  Future<void> deleteFriend(String name) async {
    final id = _friendId(name);
    await client.deleteFriend(id);
    final conv = _convByFriend.remove(name);
    if (conv != null) {
      _friendByConv.remove(conv);
      _seqByConv.remove(conv);
    }
    _friendIdByName.remove(name);
    _friendNameById.remove(id);
    state.clearBackendThread(name);
    await _loadFriends();
  }

  // ------------------------------------------------------------ 会话 / 消息
  Future<String> _ensureConversation(String friendName) async {
    final cached = _convByFriend[friendName];
    if (cached != null) return cached;
    var peerId = _friendIdByName[friendName];
    if (peerId == null) {
      final found = await client.searchUsers(friendName);
      for (final u in found) {
        if (u['nickname']?.toString() == friendName ||
            u['account']?.toString() == friendName) {
          peerId = u['id']?.toString();
          break;
        }
      }
    }
    if (peerId == null) {
      throw QApiException(404, 'NOT_FOUND', '找不到用户 $friendName');
    }
    final json = await client.createConversation(peerId);
    final convId = json['id']?.toString() ?? '';
    if (convId.isEmpty) {
      throw const QApiException(500, 'BAD_RESPONSE', '创建会话失败');
    }
    _convByFriend[friendName] = convId;
    _friendByConv[convId] = friendName;
    _friendIdByName[friendName] = peerId;
    _friendNameById[peerId] = friendName;
    return convId;
  }

  @override
  Future<void> openConversation(String friendName) async {
    final convId = await _ensureConversation(friendName);
    final history = await client.messages(convId, limit: 50);
    final messages = _parseMessages(history);
    state.mergeBackendThread(friendName, messages);
    int last = 0;
    for (final m in messages) {
      last = math.max(last, m.seq ?? 0);
    }
    _seqByConv[convId] = math.max(_seqByConv[convId] ?? 0, last);
    if (last > 0) await client.markRead(convId, last);
  }

  @override
  Future<void> send(String friendName, String text) async {
    final convId = await _ensureConversation(friendName);
    final cid = 'd-${DateTime.now().microsecondsSinceEpoch}-${++_localSeq}';
    _clientMsgToFriend[cid] = friendName;
    // 乐观插入：即使 WS 暂时断开，用户也能立刻看到自己发出的内容。
    state.addBackendMessage(
      friendName,
      QMessage(text, true, DateTime.now(), clientMsgId: cid, pending: true),
    );
    ws.send('msg.send', <String, dynamic>{
      'client_msg_id': cid,
      'conversation_id': convId,
      'type': 1,
      'content': <String, dynamic>{'text': text},
    });
    _log('发送消息 → $friendName（${text.length} 字）');
  }

  List<QMessage> _parseMessages(Map<String, dynamic> json) {
    final result = <QMessage>[];
    for (final raw in qList(json['items'])) {
      final m = ApiMessage.fromJson(raw);
      _seenIds.add(m.id);
      result.add(_toQMessage(m));
    }
    return result;
  }

  QMessage _toQMessage(ApiMessage m) => QMessage(
    m.text,
    m.senderId == client.userId,
    m.createdAt,
    clientMsgId: m.clientMsgId,
    seq: m.seq,
  );

  // ------------------------------------------------------------ WS 帧
  void _onFrame(QFrame f) {
    switch (f.type) {
      case 'ready':
        final seqs = f.data['seqs'];
        if (seqs is Map) unawaited(_catchUp(Map<String, dynamic>.from(seqs)));
      case 'msg.ack':
        _onAck(f.data);
      case 'msg.new':
        unawaited(_onNew(f.data));
      case 'presence':
        final id = f.data['user_id']?.toString();
        if (id != null) {
          state.setBackendPresence(
            _friendNameById[id] ?? id,
            f.data['status']?.toString() == 'online',
          );
        }
      case 'kick':
        unawaited(ws.close());
        client.clearTokens();
        _resetCaches();
        state.forceLogout('帐号在其它设备登录，已下线');
      case 'friend_request.new':
        unawaited(_onFriendRequestNew(f.data));
      case 'friend.accepted':
        unawaited(_onFriendAccepted(f.data));
      case 'friend_request.rejected':
        unawaited(_onFriendRejected(f.data));
      case 'friend.deleted':
        unawaited(_onFriendDeleted(f.data));
      case 'error':
        state.flash('服务端返回错误：${f.data['code'] ?? 'UNKNOWN'}');
      default:
        break;
    }
  }

  // ------------------------------------------------------------ 关系链实时帧
  Future<void> _onFriendRequestNew(Map<String, dynamic> data) async {
    final name = data['from_nickname']?.toString().trim() ?? '';
    state.flash(name.isEmpty ? '收到新的好友申请' : '$name 申请加你为好友');
    // 重拉申请列表，让好友管理窗的「好友申请 (N)」和列表即时更新。
    try {
      await _loadFriendRequests();
    } catch (_) {
      // 拉取失败不阻断通知，打开好友管理时会再拉一次。
    }
  }

  Future<void> _onFriendAccepted(Map<String, dynamic> data) async {
    final name = data['by_nickname']?.toString().trim() ?? '';
    state.flash(name.isEmpty ? '对方已同意你的好友申请' : '$name 已同意你的好友申请');
    // 好友列表即时出现新好友，无需重开窗口。
    try {
      await refreshContacts();
    } catch (_) {
      // 同上，容错。
    }
  }

  Future<void> _onFriendRejected(Map<String, dynamic> data) async {
    final name = data['by_nickname']?.toString().trim() ?? '';
    state.flash(name.isEmpty ? '对方拒绝了你的好友申请' : '$name 拒绝了你的好友申请');
    try {
      await _loadFriendRequests();
    } catch (_) {
      // 容错。
    }
  }

  Future<void> _onFriendDeleted(Map<String, dynamic> data) async {
    state.flash('对方已删除与你的好友关系');
    try {
      await refreshContacts();
    } catch (_) {
      // 容错。
    }
  }

  void _onAck(Map<String, dynamic> data) {
    final cid = data['client_msg_id']?.toString();
    if (cid == null) return;
    final friend = _clientMsgToFriend.remove(cid);
    final seq = int.tryParse(data['seq']?.toString() ?? '') ?? 0;
    if (friend != null) state.confirmBackendMessage(friend, cid, seq);
    final conv = _convByFriend[friend];
    if (conv != null) {
      _seqByConv[conv] = math.max(_seqByConv[conv] ?? 0, seq);
    }
  }

  Future<void> _onNew(Map<String, dynamic> data) async {
    final raw = data['message'];
    if (raw is! Map) return;
    final m = ApiMessage.fromJson(Map<String, dynamic>.from(raw));
    if (m.text.isEmpty && m.revoked) return;
    if (!_seenIds.add(m.id)) return;

    var convId = m.conversationId;
    if (convId.isEmpty) convId = data['conversation_id']?.toString() ?? '';
    var friend = _friendByConv[convId];
    if (friend == null) {
      // 对方第一次发消息：会话尚未在本端登记，重拉一次列表补齐映射。
      await _loadConversations();
      friend = _friendByConv[convId] ?? _friendNameById[m.senderId];
    }
    if (friend == null) return;
    _convByFriend[friend] = convId;
    _seqByConv[convId] = math.max(_seqByConv[convId] ?? 0, m.seq);

    final self = m.senderId == client.userId;
    if (self && m.clientMsgId != null) {
      final existed = state.confirmBackendMessage(friend, m.clientMsgId!, m.seq);
      if (existed) return;
    }
    state.addBackendMessage(friend, _toQMessage(m));
    _log('收到 ${self ? '多端同步' : '新'}消息 ← $friend (seq=${m.seq})');
    if (!self) state.flash('$friend 发来一条消息');
  }

  /// `ready.seqs` 与本地已见 seq 比较，只补断线期间的增量。
  Future<void> _catchUp(Map<String, dynamic> seqs) async {
    for (final entry in seqs.entries) {
      final convId = entry.key.toString();
      final remote = int.tryParse(entry.value?.toString() ?? '') ?? 0;
      final local = _seqByConv[convId] ?? 0;
      if (remote <= local) continue;
      try {
        final json = await client.messages(convId, afterSeq: local, limit: 100);
        for (final raw in qList(json['items'])) {
          final m = ApiMessage.fromJson(raw);
          _seqByConv[convId] = math.max(_seqByConv[convId] ?? 0, m.seq);
          if (!_seenIds.add(m.id)) continue;
          final friend = _friendByConv[convId] ?? _friendNameById[m.senderId];
          if (friend == null) continue;
          state.addBackendMessage(friend, _toQMessage(m));
        }
      } catch (_) {
        // 补洞失败保留当前 seq，下次重连会再补。
      }
    }
  }

  Future<void> dispose() async {
    await _frames?.cancel();
    await ws.close();
    client.dispose();
  }
}

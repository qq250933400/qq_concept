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
  QApiBridge(this.state, {QApiClient? apiClient, QWsGateway? gateway}) {
    client = apiClient ?? QApiClient();
    ws =
        gateway ??
        QWsGateway(apiBase: client.baseUrl, deviceId: client.deviceId);
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
  final Map<String, QPresence> _presenceById = <String, QPresence>{};
  final Map<String, int> _presenceRevisionById = <String, int>{};
  int _presenceRevision = 0;
  int _friendsLoadRevision = 0;
  DateTime? _expiresAt;
  int _localSeq = 0;
  Future<void> _contactsQueue = Future<void>.value();

  @override
  bool get connected => ws.connected;

  void _log(String message) {
    // 只记事件与数量，不打印 token / 密码 / 消息正文。
    if (kDebugMode) debugPrint('[QQ][API] $message');
  }

  // ------------------------------------------------------------ 认证
  Future<void> _configureServer() async {
    final local = state.localStore;
    if (local != null && client.baseUrl != local.settings.server) {
      await ws.close();
      client.clearTokens();
      client.baseUrl = local.settings.server;
      ws.setApiBase(client.baseUrl);
    }
  }

  @override
  Future<void> login(String account, String password) async {
    await _configureServer();
    final json = await client.login(account, password);
    _resetCaches();
    _expiresAt = DateTime.now().add(
      Duration(
        seconds: int.tryParse(json['expires_in']?.toString() ?? '') ?? 900,
      ),
    );
    await _bootstrap();
    await client.setPresence(state.loginPresence.name);
    state.setBackendMyPresence(state.loginPresence);
    _log(
      '登录成功：${state.friends.length} 位好友 / '
      '${state.friendGroups?.length ?? 0} 个分组 / '
      '${state.threads.length} 个会话',
    );
    state.onBackendLoggedIn(account);
    await _connectWs();
    _log('WS ${ws.connected ? '已连接' : '连接中（将自动重连）'}');
  }

  @override
  Future<void> register(QRegistration reg) async {
    await _configureServer();
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

  @override
  Future<String> updateNickname(String nickname) async {
    final result = await client.updateMe(nickname: nickname);
    final updated = result['nickname'];
    if (updated is! String || updated.isEmpty) {
      throw const QApiException(500, 'BAD_RESPONSE', '修改昵称响应无效');
    }
    return updated;
  }

  void _resetCaches() {
    _friendIdByName.clear();
    _friendNameById.clear();
    _convByFriend.clear();
    _friendByConv.clear();
    _seqByConv.clear();
    _clientMsgToFriend.clear();
    _seenIds.clear();
    _presenceById.clear();
    _presenceRevisionById.clear();
    _presenceRevision = 0;
    _friendsLoadRevision++;
    _expiresAt = null;
  }

  Future<void> _connectWs() async {
    await ws.connect(() async {
      // 重连时若 access token 已接近过期，先轮换再握手。
      final expires = _expiresAt;
      if (expires != null &&
          DateTime.now().isAfter(
            expires.subtract(const Duration(seconds: 60)),
          )) {
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
    await _loadMyProfile();
  }

  Future<void> _loadMyProfile() async {
    final me = await client.me();
    _cache('profile', me.id, {
      'id': me.id,
      'account': me.account,
      'nickname': me.nickname,
      'signature': me.signature,
      'avatar_url': me.avatarUrl,
      'gender': me.gender,
    });
    state.setBackendNickname(me.nickname.isEmpty ? me.account : me.nickname);
    state.setBackendSignature(me.signature ?? '');
    state.setBackendMyPresence(_parsePresence(me.presence, QPresence.online));
    state.setBackendAvatarIndex(qBuiltinAvatarIndex(me.avatarUrl));
  }

  Future<void> _loadFriends() async {
    final loadRevision = ++_friendsLoadRevision;
    final snapshotRevision = _presenceRevision;
    final json = await client.friends();
    if (loadRevision != _friendsLoadRevision) return;
    _cache('friends', 'list', json);
    final groups = qList(json['groups']).map(ApiGroup.fromJson).toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final items = qList(json['items']).map(ApiFriend.fromJson).toList();
    for (final friend in items) {
      _renamePeer(friend.id, friend.nickname);
    }
    final conversationNames = _friendByConv.values.toSet();
    _friendIdByName.removeWhere((name, _) => !conversationNames.contains(name));
    _friendNameById.removeWhere((_, name) => !conversationNames.contains(name));
    for (final f in items) {
      _friendIdByName[f.nickname] = f.id;
      _friendNameById[f.id] = f.nickname;
      if ((_presenceRevisionById[f.id] ?? 0) <= snapshotRevision) {
        _presenceById[f.id] = _parsePresence(f.presence, QPresence.offline);
      }
    }
    state.applyBackendPresence({
      for (final f in items)
        f.nickname: _presenceById[f.id] ?? QPresence.offline,
    });

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
      result.add(
        QFriendGroup('${g.name}(${members.length}/${items.length})', members),
      );
    }
    final orphans = items.where(
      (f) => f.groupId == null || !knownGroups.contains(f.groupId),
    );
    if (orphans.isNotEmpty) {
      final members = orphans
          .map((f) => qFriendFromApi(f.nickname, f.signature))
          .toList();
      all.addAll(members);
      result.add(
        QFriendGroup('未分组(${members.length}/${items.length})', members),
      );
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
        QContactGroup(id: '', name: '未分组', sort: 9999, count: orphanCount),
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
      _friendIdByName[name] = conv.peerId;
      _friendNameById[conv.peerId] = name;
      _seqByConv[conv.id] = math.max(_seqByConv[conv.id] ?? 0, conv.lastSeq);
      state.applyUnreadSnapshot(name, conv.unread, conv.lastSeq, conv.readSeq);
      final history = await client.messages(conv.id, limit: 50);
      final messages = _parseMessages(history);
      state.mergeBackendThread(_friendByConv[conv.id] ?? name, messages);
    }
  }

  Future<void> _loadConversationMappings() async {
    final json = await client.conversations();
    for (final raw in qList(json['items'])) {
      final conv = ApiConversation.fromJson(raw);
      final name = _friendNameById[conv.peerId] ?? conv.peerNickname;
      if (conv.id.isEmpty || name.isEmpty) continue;
      _convByFriend[name] = conv.id;
      _friendByConv[conv.id] = name;
      _friendIdByName[name] = conv.peerId;
      _friendNameById[conv.peerId] = name;
      state.applyUnreadSnapshot(name, conv.unread, conv.lastSeq, conv.readSeq);
    }
  }

  void _renamePeer(String id, String name) {
    final old = _friendNameById[id];
    if (old == null || old == name || name.isEmpty) return;
    state.renameBackendFriend(old, name);
    if (_friendIdByName[old] == id) _friendIdByName.remove(old);
    _friendIdByName[name] = id;
    _friendNameById[id] = name;
    final conv = _convByFriend.remove(old);
    if (conv != null) {
      _convByFriend[name] = conv;
      _friendByConv[conv] = name;
    }
    _clientMsgToFriend.updateAll((_, value) => value == old ? name : value);
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
    final local = state.localStore?.settings.options;
    if (local != null && local.isNotEmpty) {
      state.applyBackendSettings(local);
    } else if (values.isNotEmpty) {
      state.applyBackendSettings(values);
    }
  }

  @override
  Future<void> saveSettings(Map<String, bool> values) =>
      client.putSettings(values).then((_) {});

  @override
  Future<void> setPresence(QPresence status) => client.setPresence(status.name);

  QPresence _parsePresence(String? value, QPresence fallback) {
    if (value == null) return fallback;
    final status = QPresence.parse(value);
    if (status == null) throw FormatException('未知在线状态：$value');
    return status;
  }

  // ------------------------------------------------------------ 关系链
  @override
  Future<void> refreshContacts() {
    final next = _contactsQueue.then((_) async {
      await _loadFriends();
      await _loadFriendRequests();
    });
    _contactsQueue = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
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
          isFriend:
              r['is_friend'] == true ||
              r['is_friend'] == 1 ||
              r['is_friend'] == '1' ||
              r['is_friend'] == 'true',
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
    final name = _friendNameById[peerId] ?? friendName;
    _convByFriend[name] = convId;
    _friendByConv[convId] = name;
    _friendIdByName[name] = peerId;
    _friendNameById[peerId] = name;
    return convId;
  }

  @override
  Future<void> openConversation(String friendName) async {
    final convId = await _ensureConversation(friendName);
    final history = await client.messages(convId, limit: 50);
    final messages = _parseMessages(history);
    state.mergeBackendThread(_friendByConv[convId] ?? friendName, messages);
    int last = 0;
    for (final m in messages) {
      last = math.max(last, m.seq ?? 0);
    }
    _seqByConv[convId] = math.max(_seqByConv[convId] ?? 0, last);
    if (last > 0) await _markRead(convId, friendName, last);
  }

  Future<void> _markRead(String convId, String friend, int seq) async {
    final response = await client.markRead(convId, seq);
    final readSeq = int.tryParse(response['read_seq']?.toString() ?? '');
    if (readSeq == null) throw const FormatException('已读响应缺少序号');
    state.markConversationRead(_friendByConv[convId] ?? friend, readSeq);
  }

  @override
  Future<void> send(String friendName, String text) async {
    final convId = await _ensureConversation(friendName);
    final name = _friendByConv[convId] ?? friendName;
    final cid = 'd-${DateTime.now().microsecondsSinceEpoch}-${++_localSeq}';
    _clientMsgToFriend[cid] = name;
    // 乐观插入：即使 WS 暂时断开，用户也能立刻看到自己发出的内容。
    state.addBackendMessage(
      name,
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
      if (m.id.isNotEmpty) _cache('message', m.id, raw);
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
        _runFrameTask(refreshContacts(), '刷新好友列表');
        _runFrameTask(_loadMyProfile(), '刷新个人资料');
        if (seqs is Map) {
          _runFrameTask(
            _syncConversations(Map<String, dynamic>.from(seqs)),
            '同步消息',
          );
        }
      case 'msg.ack':
        _onAck(f.data);
      case 'msg.new':
        _runFrameTask(_onNew(f.data), '接收消息');
      case 'msg.read':
        if (f.data['user_id']?.toString() == client.userId) {
          _runFrameTask(_onRead(f.data), '同步已读状态');
        }
      case 'presence':
        final id = f.data['user_id']?.toString();
        final status = QPresence.parse(f.data['status']?.toString());
        if (id == null || id.isEmpty || status == null) {
          state.flash('收到无效的在线状态');
        } else if (id == client.userId) {
          state.setBackendMyPresence(status);
        } else {
          _presenceById[id] = status;
          _presenceRevisionById[id] = ++_presenceRevision;
          final name = _friendNameById[id];
          if (name != null) state.setBackendPresence(name, status);
        }
      case 'kick':
        unawaited(ws.close());
        client.clearTokens();
        _resetCaches();
        state.forceLogout('帐号在其它设备登录，已下线');
      case 'friend_request.new':
        _runFrameTask(_onFriendRequestNew(f.data), '刷新好友申请');
      case 'friend.accepted':
        _runFrameTask(_onFriendAccepted(f.data), '刷新好友列表');
      case 'friend_request.rejected':
        _runFrameTask(_onFriendRejected(f.data), '刷新好友申请');
      case 'friend.deleted':
        _runFrameTask(_onFriendDeleted(f.data), '刷新好友列表');
      case 'user.profile_changed':
        if (f.data['user_id']?.toString() == client.userId) {
          _runFrameTask(_loadMyProfile(), '刷新个人资料');
        } else {
          _runFrameTask(refreshContacts(), '刷新好友资料');
        }
      case 'error':
        state.flash('服务端返回错误：${f.data['code'] ?? 'UNKNOWN'}');
      default:
        break;
    }
  }

  void _runFrameTask(Future<void> task, String action) {
    unawaited(
      task.catchError((Object error, StackTrace stack) {
        state.flash('$action失败：$error');
        debugPrint('[QQ][API] $action失败：$error');
      }),
    );
  }

  // ------------------------------------------------------------ 关系链实时帧
  Future<void> _onFriendRequestNew(Map<String, dynamic> data) async {
    final name = data['from_nickname']?.toString().trim() ?? '';
    state.notifyIncoming('好友申请', name.isEmpty ? '收到新的好友申请' : '$name 申请加你为好友');
    // 重拉申请列表，让好友管理窗的「好友申请 (N)」和列表即时更新。
    await refreshContacts();
  }

  Future<void> _onFriendAccepted(Map<String, dynamic> data) async {
    final name = data['by_nickname']?.toString().trim() ?? '';
    state.notifyIncoming(
      '好友申请',
      name.isEmpty ? '对方已同意你的好友申请' : '$name 已同意你的好友申请',
    );
    // 好友列表即时出现新好友，无需重开窗口。
    await refreshContacts();
  }

  Future<void> _onFriendRejected(Map<String, dynamic> data) async {
    final name = data['by_nickname']?.toString().trim() ?? '';
    state.flash(name.isEmpty ? '对方拒绝了你的好友申请' : '$name 拒绝了你的好友申请');
    await refreshContacts();
  }

  Future<void> _onFriendDeleted(Map<String, dynamic> data) async {
    state.flash('对方已删除与你的好友关系');
    await refreshContacts();
  }

  void _onAck(Map<String, dynamic> data) {
    final cid = data['client_msg_id']?.toString();
    if (cid == null) return;
    final friend = _clientMsgToFriend.remove(cid);
    final seq = int.tryParse(data['seq']?.toString() ?? '') ?? 0;
    final conv = _convByFriend[friend];
    if (friend != null && conv != null && data['msg_id'] != null) {
      final matches = state.thread(friend).where((m) => m.clientMsgId == cid);
      if (matches.isNotEmpty) {
        _cache('message', data['msg_id'].toString(), {
          'id': data['msg_id'],
          'conversation_id': conv,
          'sender_id': client.userId,
          'seq': seq,
          'client_msg_id': cid,
          'created_at': data['created_at'],
          'content': {'text': matches.first.text},
        });
      }
    }
    if (friend != null) state.confirmBackendMessage(friend, cid, seq);
    if (conv != null) {
      _advanceLiveSeq(conv, seq);
    }
  }

  void _advanceLiveSeq(String convId, int seq) {
    final current = _seqByConv[convId] ?? 0;
    if (seq == current + 1) _seqByConv[convId] = seq;
  }

  Future<void> _onRead(Map<String, dynamic> data) async {
    final convId = data['conversation_id']?.toString() ?? '';
    final seq = int.tryParse(data['up_to_seq']?.toString() ?? '');
    if (convId.isEmpty || seq == null) {
      throw const FormatException('已读通知无效');
    }
    if (!_friendByConv.containsKey(convId)) await _loadConversationMappings();
    final friend = _friendByConv[convId];
    if (friend == null) throw StateError('无法找到已读消息对应的会话');
    state.markConversationRead(friend, seq);
    await _loadConversationMappings();
  }

  Future<void> _onNew(Map<String, dynamic> data) async {
    final raw = data['message'];
    if (raw is! Map) return;
    final m = ApiMessage.fromJson(Map<String, dynamic>.from(raw));
    if (m.id.isNotEmpty) _cache('message', m.id, raw);
    if (m.text.isEmpty && m.revoked) return;
    if (m.id.isNotEmpty && !_seenIds.add(m.id)) return;

    var convId = m.conversationId;
    if (convId.isEmpty) convId = data['conversation_id']?.toString() ?? '';
    var friend = _friendByConv[convId];
    if (friend == null) {
      // 对方第一次发消息：会话尚未在本端登记，重拉一次列表补齐映射。
      try {
        await _loadConversationMappings();
      } catch (error) {
        _seenIds.remove(m.id);
        rethrow;
      }

      friend = _friendByConv[convId] ?? _friendNameById[m.senderId];
    }
    if (friend == null) {
      _seenIds.remove(m.id);
      throw StateError('无法找到消息对应的会话');
    }
    _convByFriend[friend] = convId;
    _advanceLiveSeq(convId, m.seq);

    final self = m.senderId == client.userId;
    if (self && m.clientMsgId != null) {
      final existed = state.confirmBackendMessage(
        friend,
        m.clientMsgId!,
        m.seq,
      );
      if (existed) return;
    }
    state.addBackendMessage(friend, _toQMessage(m));
    _log('收到 ${self ? '多端同步' : '新'}消息 ← $friend (seq=${m.seq})');
    if (!self) {
      state.addUnread(friend, m.seq);
      state.notifyIncoming('新消息', '$friend 发来一条消息', friend: friend);
      if (state.isChatVisible(friend)) await _markRead(convId, friend, m.seq);
    }
  }

  void _cache(String kind, String id, Object data) {
    final userId = client.userId;
    final store = state.localStore;
    if (store == null || userId == null || userId.isEmpty || id.isEmpty) return;
    try {
      store.cache(client.baseUrl, userId, kind, id, data);
    } on Exception catch (error) {
      state.flash('保存本地数据失败：$error');
    }
  }

  Future<void> _syncConversations(Map<String, dynamic> seqs) async {
    await _loadConversationMappings();
    await _catchUp(seqs);
  }

  /// `ready.seqs` 与本地已见 seq 比较，只补断线期间的增量。
  Future<void> _catchUp(Map<String, dynamic> seqs) async {
    if (seqs.keys.any((id) => !_friendByConv.containsKey(id))) {
      await _loadConversationMappings();
    }
    for (final entry in seqs.entries) {
      final convId = entry.key.toString();
      final remote = int.tryParse(entry.value?.toString() ?? '') ?? 0;
      var cursor = _seqByConv[convId] ?? 0;
      var readThrough = 0;
      String? readFriend;
      while (cursor < remote) {
        final json = await client.messages(
          convId,
          afterSeq: cursor,
          limit: 100,
        );
        final previous = cursor;
        for (final raw in qList(json['items'])) {
          final m = ApiMessage.fromJson(raw);
          cursor = math.max(cursor, m.seq);
          final friend = _friendByConv[convId] ?? _friendNameById[m.senderId];
          if (friend == null) throw StateError('无法找到消息对应的会话');
          if (m.id.isNotEmpty && !_seenIds.add(m.id)) continue;
          state.addBackendMessage(friend, _toQMessage(m));
          if (m.senderId != client.userId) {
            state.addUnread(friend, m.seq);
            state.notifyIncoming('新消息', '$friend 发来一条消息', friend: friend);
            if (state.isChatVisible(friend)) {
              readThrough = math.max(readThrough, m.seq);
              readFriend = friend;
            }
          }
        }
        if (cursor == previous) throw StateError('同步消息时序号未前进');
        _seqByConv[convId] = math.max(_seqByConv[convId] ?? 0, cursor);
      }
      if (readThrough > 0 && readFriend != null) {
        await _markRead(convId, readFriend, readThrough);
      }
    }
  }

  Future<void> dispose() async {
    await _frames?.cancel();
    await ws.close();
    client.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset;

import 'backend.dart';
import 'contacts.dart';
import 'models.dart';
import 'profile.dart';

/// QQ 概念版前端状态（纯 ChangeNotifier，无第三方状态管理库）。
/// 只负责 UI 状态与内存数据；真实后端通过 [QBackend] 抽象接入，
/// 不接后端时（`backend == null`）全部走本地演示数据。
class QAppState extends ChangeNotifier {
  QAppState({String preset = 'demo'}) {
    _initLocalContacts();
    _applyPreset(preset);
  }

  /// 真实 API 桥接；null = 设计稿画廊 / 离线演示模式。
  QBackend? backend;

  /// 登录 / 注册中的忙碌态与错误文案（登录窗内联显示）。
  bool apiBusy = false;
  String? authError;

  /// 注册窗口专属状态（与登录窗的 authError 分开，避免两窗串台）。
  bool registerBusy = false;
  String? registerError;

  /// 当前用户的内置头像下标（`builtin://avatar/N` 解析结果）。
  /// null = 未设置或外链头像 → 主面板相框保持设计稿默认剪影。
  int? myAvatarIndex;

  /// WS 是否已连上（供状态点显示）。
  bool backendConnected = false;
  String displayName = '云帆';

  /// 好友数据：API 模式由服务端分组驱动，未接入时用设计稿常量。
  List<QFriend> friends = List<QFriend>.from(kFriends);
  List<QFriendGroup>? friendGroups;
  final Map<String, bool> presence = <String, bool>{};

  // ------------------------------------------------------------ 关系链 UI 状态
  List<QContactGroup> contactGroups = <QContactGroup>[];
  List<QContact> contacts = <QContact>[];
  List<QUserHit> searchResults = <QUserHit>[];
  List<QFriendRequestInfo> friendRequests = <QFriendRequestInfo>[];
  bool contactsBusy = false;
  String? contactsError;

  /// 好友管理页搜索词；同时过滤分组内照片卡。
  String contactsQuery = '';

  /// null = 全部好友；空串 = 「未分组」虚拟分组。
  String? selectedGroupId;
  String? selectedContactName;

  QContactDialog contactDialog = QContactDialog.none;
  String? dialogTarget;
  String? dialogTargetName;

  String confirmTitle = '';
  String confirmMessage = '';
  String confirmAction = '';
  String confirmTarget = '';

  int get pendingRequestCount =>
      friendRequests.where((r) => r.pending).length;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- 会话
  bool loggedIn = false;
  String account = '10001';
  String password = '';
  bool remember = true;

  /// 主面板当前 tab：0 好友列表 / 1 群组列表 / 2 最近消息。
  int panelTab = 0;

  /// 主菜单浮层是否打开（左下角企鹅球切换，不属于任何 tab）。
  bool panelMenu = false;

  String? activeFriend;
  String searchQuery = '';

  /// 当前展开的好友分组（null = 全部折叠）。只由点击分组标题驱动。
  String? expandedGroup;

  /// 主面板是否已翻转到背面（设置页）。翻转是窗口内动画，不是独立窗口。
  bool panelSettings = false;

  // ---------------------------------------------------------------- 窗口
  final List<QWindow> windows = [];
  int _z = 0;
  String? toast;
  Timer? _toastTimer;

  // ---------------------------------------------------------------- 消息
  final Map<String, List<QMessage>> threads = {};

  List<QMessage> thread([String? name]) =>
      threads[name ?? activeFriend ?? '云帆'] ?? const <QMessage>[];

  // ---------------------------------------------------------------- 设置
  bool autoStart = false;
  bool alwaysOnTop = false;
  bool autoHide = false;
  bool sound = false;
  bool sendCtrlEnter = true;

  bool setting(String key) => switch (key) {
    'autoStart' => autoStart,
    'alwaysOnTop' => alwaysOnTop,
    'autoHide' => autoHide,
    'sound' => sound,
    'sendCtrlEnter' => sendCtrlEnter,
    _ => false,
  };

  void setSetting(String key, bool value) {
    switch (key) {
      case 'autoStart':
        autoStart = value;
      case 'alwaysOnTop':
        alwaysOnTop = value;
      case 'autoHide':
        autoHide = value;
      case 'sound':
        sound = value;
      case 'sendCtrlEnter':
        sendCtrlEnter = value;
    }
    _notify();
  }

  // ---------------------------------------------------------------- 预设
  void _reset({required bool logged}) {
    // 清空窗口注册表后，QNativeWindows 会同步销毁对应的全部 OS 窗口。
    loggedIn = logged;
    panelTab = 0;
    panelMenu = false;
    activeFriend = null;
    searchQuery = '';
    expandedGroup = null;
    panelSettings = false;
    contactsBusy = false;
    contactsError = null;
    contactsQuery = '';
    selectedGroupId = null;
    selectedContactName = null;
    contactDialog = QContactDialog.none;
    dialogTarget = null;
    dialogTargetName = null;
    searchResults = const <QUserHit>[];
    registerBusy = false;
    registerError = null;
    myAvatarIndex = null;
    windows.clear();
    _z = 0;
  }

  void _applyPreset(String preset) {
    switch (preset) {
      case 'login':
        _reset(logged: false);
        _open(QWindowKind.login);
      case 'register':
        _reset(logged: false);
        _open(QWindowKind.login);
        _open(QWindowKind.register);
      case 'main':
      case 'chat':
      case 'fm':
      case 'settings':
      case 'about':
        _reset(logged: true);
        _open(QWindowKind.panel);
        if (preset == 'chat') _open(QWindowKind.chat);
        if (preset == 'fm') _open(QWindowKind.friendsManager);
        if (preset == 'settings') _open(QWindowKind.settings);
        if (preset == 'about') _open(QWindowKind.about);
      case 'friends':
        _reset(logged: true);
        _open(QWindowKind.panel);
        // 与 V6.1「好友列表展开态」等价，但由分组数据驱动。
        expandedGroup = '大学好友(21/66)';
      case 'groups':
        _reset(logged: true);
        _open(QWindowKind.panel);
        panelTab = 1;
      case 'menu':
        _reset(logged: true);
        _open(QWindowKind.panel);
        panelMenu = true;
      case 'bamboo':
        _reset(logged: true);
        _open(QWindowKind.panel);
        panelTab = 2;
      default: // demo：主面板 + 聊天 + 关于可见，好友管理/设置收在任务栏
        _reset(logged: true);
        _open(QWindowKind.panel);
        _open(QWindowKind.chat);
        _open(QWindowKind.about);
        _open(QWindowKind.friendsManager).minimized = true;
        _open(QWindowKind.settings).minimized = true;
    }
  }

  // ---------------------------------------------------------------- 窗口动作
  QWindow? _byId(String id) {
    for (final w in windows) {
      if (w.id == id) return w;
    }
    return null;
  }

  QWindow _open(QWindowKind kind, {String? friend}) {
    final id = kind == QWindowKind.chat
        ? 'chat:${friend ?? activeFriend ?? '云帆'}'
        : kind.name;
    final existing = _byId(id);
    if (existing != null) {
      existing.minimized = false;
      existing.z = ++_z;
      if (kind == QWindowKind.chat && friend != null) activeFriend = friend;
      return existing;
    }
    final w = QWindow(
      id: id,
      kind: kind,
      friend: kind == QWindowKind.chat ? (friend ?? '云帆') : null,
      z: ++_z,
    );
    windows.add(w);
    if (kind == QWindowKind.chat && friend != null) activeFriend = friend;
    return w;
  }

  /// 唯一入口：窗口只登记到 [windows]，由画布桌面或 QNativeWindows 各自渲染。
  /// 独立窗口模式下 QNativeWindows 监听本对象并 diff 出 OS 窗口的增/删/最小化。
  void open(QWindowKind kind, {String? friend}) {
    _open(kind, friend: friend);
    _notify();
  }

  void close(String id) {
    final wasPanel = id == QWindowKind.panel.name;
    windows.removeWhere((w) => w.id == id);
    if (wasPanel) panelSettings = false;
    _notify();
  }

  void minimize(String id) {
    for (final w in windows) {
      if (w.id == id) w.minimized = true;
    }
    _notify();
  }

  void restore(String id) {
    for (final w in windows) {
      if (w.id == id) {
        w.minimized = false;
        w.z = ++_z;
      }
    }
    _notify();
  }

  void focus(String id) {
    final w = _byId(id);
    if (w == null || w.z == _z) return;
    w.z = ++_z;
    _notify();
  }

  void setWindowPos(String id, Offset pos) {
    final w = _byId(id);
    if (w == null) return;
    w.pos = pos;
    _notify();
  }

  void centerWindow(String id, Offset pos) {
    final w = _byId(id);
    if (w == null) return;
    w.pos = pos;
    w.z = ++_z;
    _notify();
  }

  List<QWindow> get ordered {
    final list = List<QWindow>.from(windows);
    list.sort((a, b) => a.z.compareTo(b.z));
    return list;
  }

  void openAll() {
    loggedIn = true;
    for (final k in QWindowKind.values) {
      if (k == QWindowKind.login || k == QWindowKind.register) continue;
      _open(k).minimized = false;
    }
    flash('已打开全部窗口（可拖拽标题栏移动）');
  }

  // ---------------------------------------------------------------- 登录流程
  void setAccount(String v) {
    account = v;
    _notify();
  }

  void setPassword(String v) {
    password = v;
    _notify();
  }

  void setRemember(bool v) {
    remember = v;
    _notify();
  }

  void login() {
    if (apiBusy) return;
    if (account.trim().isEmpty || password.trim().isEmpty) {
      flash('请输入帐号和密码');
      return;
    }
    final b = backend;
    if (b == null) {
      _enterLoggedIn();
      return;
    }
    _runAuth(() => b.login(account.trim(), password));
  }

  /// 登录窗「注册新帐号」：弹出独立注册窗口（表单在窗口内，不再复用
  /// 登录框的帐号密码）。
  void openRegisterWindow() {
    if (apiBusy) return;
    registerError = null;
    _open(QWindowKind.register);
    _notify();
  }

  /// 关闭注册窗口（取消 / × / 注册成功后统一走 [_enterLoggedIn]）。
  void closeRegisterWindow() {
    if (windows.any((w) => w.kind == QWindowKind.register)) {
      windows.removeWhere((w) => w.kind == QWindowKind.register);
    }
    registerError = null;
    _notify();
  }

  /// 注册窗口「注册并登录」：校验 → 后端注册 → 自动登录进主面板。
  void submitRegistration(QRegistration reg) {
    if (registerBusy) return;
    final validation = reg.validate();
    if (validation != null) {
      registerError = validation;
      _notify();
      return;
    }
    final b = backend;
    if (b == null) {
      registerError = '注册需要连接 API 服务';
      flash(registerError!);
      _notify();
      return;
    }
    registerBusy = true;
    registerError = null;
    _notify();
    b.register(reg).then(
      (_) {},
      onError: (Object error) {
        registerError = error.toString().replaceFirst('Exception: ', '');
        flash(registerError!);
      },
    ).whenComplete(() {
      registerBusy = false;
      _notify();
    });
  }

  void _runAuth(Future<void> Function() action) {
    apiBusy = true;
    authError = null;
    _notify();
    action().then(
      (_) {},
      onError: (Object error) {
        authError = error.toString().replaceFirst('Exception: ', '');
        flash(authError!);
      },
    ).whenComplete(() {
      apiBusy = false;
      _notify();
    });
  }

  /// 后端登录成功后的统一入口（mock 登录也走这里）。
  void _enterLoggedIn() {
    loggedIn = true;
    windows.removeWhere(
      (w) => w.kind == QWindowKind.login || w.kind == QWindowKind.register,
    );
    registerBusy = false;
    registerError = null;
    // 登录后默认落在好友列表 tab，分组折叠，点击分组名展开好友行。
    panelTab = 0;
    expandedGroup = null;
    _open(QWindowKind.panel);
    flash('登录成功 · 欢迎回来，$account');
    _notify();
  }

  void onBackendLoggedIn(String acc) => _enterLoggedIn();

  /// 被顶号 / 令牌失效：不等待网络返回，直接回到登录窗。
  void forceLogout(String reason) {
    _reset(logged: false);
    threads.clear();
    friendGroups = null;
    friends = List<QFriend>.from(kFriends);
    // 退出后关系链回到离线演示数据，避免残留上一账号的真实好友/申请。
    _initLocalContacts();
    _open(QWindowKind.login);
    authError = reason;
    backendConnected = false;
    flash(reason);
    _notify();
  }

  void logout() {
    final b = backend;
    _reset(logged: false);
    threads.clear();
    friendGroups = null;
    friends = List<QFriend>.from(kFriends);
    // 退出后关系链回到离线演示数据，避免残留上一账号的真实好友/申请。
    _initLocalContacts();
    backendConnected = false;
    _open(QWindowKind.login);
    flash('已退出登录');
    _notify();
    if (b != null) _background(b.logout(), '退出登录');
  }

  void changeUser() {
    final b = backend;
    password = '';
    _reset(logged: false);
    friendGroups = null;
    friends = List<QFriend>.from(kFriends);
    // 退出后关系链回到离线演示数据，避免残留上一账号的真实好友/申请。
    _initLocalContacts();
    backendConnected = false;
    _open(QWindowKind.login);
    flash('请重新登录');
    _notify();
    if (b != null) _background(b.logout(), '切换用户');
  }

  void _background(Future<void> task, String what) {
    task.then(
      (_) {},
      onError: (Object error) {
        if (!_disposed) flash('$what失败：$error');
      },
    );
  }

  // ---------------------------------------------------------------- 主面板
  /// 点击 tab 图标切换列表页（3D 翻转方向由 TabFlip 依前后索引决定）。
  /// 再点当前 tab 时仅关闭主菜单浮层。
  void setPanelTab(int i) {
    if (panelTab == i) {
      if (panelMenu) {
        panelMenu = false;
        _notify();
      }
      return;
    }
    panelTab = i;
    panelMenu = false;
    _notify();
  }

  /// 点击分组标题：同组再点收起，点另一组则切换；同时关闭主菜单浮层。
  void toggleGroup(String label) {
    expandedGroup = expandedGroup == label ? null : label;
    if (panelMenu) panelMenu = false;
    _notify();
  }

  /// 主面板左下角企鹅球：主菜单的唯一切换入口（浮层，不改变 tab）。
  void toggleMainMenu() {
    panelMenu = !panelMenu;
    _notify();
  }

  // ------------------------------------------------------------ 面板内翻转
  /// 主面板 3D 翻转 → 设置页（不新开窗口）。
  void openPanelSettings() {
    panelMenu = false;
    _open(QWindowKind.panel);
    if (!panelSettings) {
      panelSettings = true;
      _notify();
    }
  }

  /// 设置页反向翻转 → 主面板。
  void closePanelSettings() {
    if (!panelSettings) return;
    panelSettings = false;
    _notify();
  }

  void setSearchQuery(String q) {
    searchQuery = q;
    // 输入搜索词时自动切到好友列表 tab 过滤好友。
    if (q.isNotEmpty && panelTab != 0) panelTab = 0;
    _notify();
  }

  void selectFriend(String name) {
    activeFriend = name;
    open(QWindowKind.chat, friend: name);
    final b = backend;
    if (b != null) _background(b.openConversation(name), '加载聊天记录');
  }

  void handleMenuAction(String action) {
    switch (action) {
      case '系统设置':
      case '个人设置':
        // 面板内 3D 翻转，不新开独立设置窗口。
        openPanelSettings();
      case '好友管理':
        panelMenu = false;
        open(QWindowKind.friendsManager);
      case '我的 Qzone':
        panelMenu = false;
        flash('Qzone 暂未接入（前端演示）');
      case '关于 QQ':
        panelMenu = false;
        open(QWindowKind.about);
      case '更换用户':
        changeUser();
      case '退出':
        logout();
      default:
        panelMenu = false;
        _notify();
    }
  }

  // ---------------------------------------------------------------- 聊天
  void sendMessage(String text, {String? friend}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final key = friend ?? activeFriend ?? '云帆';
    final b = backend;
    if (b != null) {
      // 真实模式由 WS 收发：QApiBridge 会先插入乐观消息，再等 msg.ack 确认。
      _background(b.send(key, trimmed), '发送消息');
      return;
    }
    threads
        .putIfAbsent(key, () => <QMessage>[])
        .add(QMessage(trimmed, true, DateTime.now()));
    _notify();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (_disposed || !loggedIn) return;
      threads
          .putIfAbsent(key, () => <QMessage>[])
          .add(QMessage(_reply(trimmed), false, DateTime.now()));
      _notify();
    });
  }

  String _reply(String text) {
    if (text.contains('?') || text.contains('？')) return '这个问题我得想想～';
    if (text.contains('你好') || text.contains(' hi')) return '你好呀，好久不见！';
    return '收到：$text';
  }

  // ------------------------------------------------- 后端数据回填（QBackend）
  void applyBackendData({
    required List<QFriendGroup> groups,
    required List<QFriend> friends,
  }) {
    friendGroups = groups;
    this.friends = friends;
    _notify();
  }

  void applyBackendSettings(Map<String, bool> values) {
    for (final entry in values.entries) {
      switch (entry.key) {
        case 'autoStart':
          autoStart = entry.value;
        case 'alwaysOnTop':
          alwaysOnTop = entry.value;
        case 'autoHide':
          autoHide = entry.value;
        case 'sound':
          sound = entry.value;
        case 'sendCtrlEnter':
          sendCtrlEnter = entry.value;
      }
    }
    _notify();
  }

  Map<String, bool> allSettings() => <String, bool>{
    'autoStart': autoStart,
    'alwaysOnTop': alwaysOnTop,
    'autoHide': autoHide,
    'sound': sound,
    'sendCtrlEnter': sendCtrlEnter,
  };

  /// 设置页「保存」：一次 PUT 写全量，避免逐项切换打爆接口。
  void commitSettings() {
    final b = backend;
    if (b != null) _background(b.saveSettings(allSettings()), '保存设置');
  }

  void setBackendNickname(String name) {
    if (name.isEmpty || displayName == name) return;
    displayName = name;
    _notify();
  }

  /// 回填当前用户的内置头像下标（`/users/me` 的 avatar_url 解析结果）。
  /// null / 未变化时不通知，避免登录后多余重建。
  void setBackendAvatarIndex(int? index) {
    if (myAvatarIndex == index) return;
    myAvatarIndex = index;
    _notify();
  }

  void setBackendConnected(bool value) {
    if (backendConnected == value) return;
    backendConnected = value;
    _notify();
  }

  void setBackendPresence(String name, bool online) {
    if (presence[name] == online) return;
    presence[name] = online;
    _notify();
  }

  /// 用服务端历史替换本地列表，但保留尚未被 ack 的乐观消息。
  void mergeBackendThread(String friend, List<QMessage> remote) {
    final current = threads[friend] ?? const <QMessage>[];
    final pending = current
        .where((m) => m.pending)
        .where(
          (m) => !remote.any(
            (r) => r.clientMsgId != null && r.clientMsgId == m.clientMsgId,
          ),
        )
        .toList();
    threads[friend] = <QMessage>[...remote, ...pending];
    _notify();
  }

  void addBackendMessage(String friend, QMessage msg) {
    final list = threads.putIfAbsent(friend, () => <QMessage>[]);
    if (msg.clientMsgId != null &&
        list.any((m) => m.clientMsgId == msg.clientMsgId)) {
      return;
    }
    if (msg.seq != null &&
        list.any((m) => m.seq == msg.seq && m.text == msg.text)) {
      return;
    }
    list.add(msg);
    _notify();
  }

  /// 返回 true 表示这条 ack 对应的是本地已有的乐观消息（无需再插入）。
  bool confirmBackendMessage(String friend, String clientMsgId, int seq) {
    final list = threads[friend];
    if (list == null) return false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].clientMsgId == clientMsgId) {
        list[i] = list[i].confirmed(seq: seq);
        _notify();
        return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------ 关系链
  /// 离线 / 画廊模式的通讯录：与 seed 同名分组 + 一条待处理申请，
  /// 保证不接后端时「搜索 → 加好友 → 通过 → 分组」整条链路也能演示。
  void _initLocalContacts() {
    contactGroups = <QContactGroup>[
      for (var i = 0; i < kLocalGroupNames.length; i++)
        QContactGroup(id: 'local-g-$i', name: kLocalGroupNames[i], sort: i),
    ];
    contacts = <QContact>[
      for (var i = 0; i < kFriends.length; i++)
        QContact(
          id: 'local-u-$i',
          name: kFriends[i].name,
          account: '${10002 + i}',
          signature: kFriends[i].sig,
          groupId: contactGroups[i % contactGroups.length].id,
        ),
    ];
    friendRequests = const <QFriendRequestInfo>[
      QFriendRequestInfo(
        id: 'local-req-1',
        account: '10008',
        name: '沈星回',
        message: '概念版演示：加个好友吧',
      ),
    ];
    _refreshLocalGroupCounts();
  }

  static const List<QUserHit> _localDirectory = <QUserHit>[
    QUserHit(
      id: 'local-u-10008',
      account: '10008',
      name: '沈星回',
      signature: '山高路远，来日方长',
    ),
    QUserHit(
      id: 'local-u-10009',
      account: '10009',
      name: '许知远',
      signature: '保持好奇',
    ),
    QUserHit(
      id: 'local-u-10010',
      account: '10010',
      name: '程野',
      signature: '在路上',
    ),
  ];

  int _localContactSeq = 0;

  void _refreshLocalGroupCounts() {
    contactGroups = <QContactGroup>[
      for (final g in contactGroups)
        g.copyWith(
          count: contacts.where((c) => (c.groupId ?? '') == g.id).length,
        ),
    ];
  }

  /// 离线模式下把关系链 DTO 同步回主面板用的 QFriend / QFriendGroup。
  void _rebuildLocalViews() {
    _refreshLocalGroupCounts();
    friends = <QFriend>[
      for (final c in contacts) qFriendFromApi(c.name, c.signature),
    ];
    final total = contacts.length;
    QFriend row(QContact c) => qFriendFromApi(c.name, c.signature);
    friendGroups = <QFriendGroup>[
      for (final g in contactGroups)
        QFriendGroup(
          '${g.name}(${g.count}/$total)',
          contacts.where((c) => (c.groupId ?? '') == g.id).map(row).toList(),
        ),
      if (contacts.any((c) => (c.groupId ?? '').isEmpty))
        QFriendGroup(
          '未分组(${contacts.where((c) => (c.groupId ?? '').isEmpty).length}/$total)',
          contacts
              .where((c) => (c.groupId ?? '').isEmpty)
              .map(row)
              .toList(),
        ),
    ];
  }

  List<QUserHit> _localSearch(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return const <QUserHit>[];
    final pool = <QUserHit>[
      for (final c in contacts)
        QUserHit(
          id: c.id,
          account: c.account,
          name: c.name,
          signature: c.signature,
          isFriend: true,
        ),
      ..._localDirectory,
    ];
    return pool
        .where(
          (u) => u.account.toLowerCase().contains(query) ||
              u.name.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  void _localSendRequest(String account, String message) {
    final acc = account.trim();
    if (acc.isEmpty) throw StateError('请输入对方帐号');
    if (contacts.any((c) => c.account == acc)) {
      throw StateError('对方已经是你的好友');
    }
    if (friendRequests.any((r) => r.account == acc && r.status == 0)) {
      throw StateError('申请已发出，请等待对方处理');
    }
    var name = acc;
    for (final u in _localDirectory) {
      if (u.account == acc) {
        name = u.name;
        break;
      }
    }
    friendRequests = <QFriendRequestInfo>[
      QFriendRequestInfo(
        id: 'local-req-out-${++_localContactSeq}',
        account: acc,
        name: name,
        message: message,
        direction: 'out',
      ),
      ...friendRequests,
    ];
  }

  void _localDecide(String id, bool accept) {
    final index = friendRequests.indexWhere((r) => r.id == id);
    if (index < 0) throw StateError('申请不存在');
    final req = friendRequests[index];
    friendRequests = <QFriendRequestInfo>[
      for (var i = 0; i < friendRequests.length; i++)
        i == index
            ? friendRequests[i].copyWith(status: accept ? 1 : 2)
            : friendRequests[i],
    ];
    if (accept && !contacts.any((c) => c.account == req.account)) {
      contacts = <QContact>[
        ...contacts,
        QContact(
          id: 'local-u-${req.account}',
          name: req.name,
          account: req.account,
          signature: '新朋友，打个招呼吧',
        ),
      ];
      _rebuildLocalViews();
    }
  }

  void _localCreateGroup(String name) {
    if (contactGroups.any((g) => g.name == name)) {
      throw StateError('分组名称已存在');
    }
    contactGroups = <QContactGroup>[
      ...contactGroups,
      QContactGroup(
        id: 'local-g-new-${++_localContactSeq}',
        name: name,
        sort: contactGroups.length,
      ),
    ];
    _rebuildLocalViews();
  }

  void _localRenameGroup(String id, String name) {
    if (contactGroups.any((g) => g.name == name && g.id != id)) {
      throw StateError('分组名称已存在');
    }
    contactGroups = <QContactGroup>[
      for (final g in contactGroups) g.id == id ? g.copyWith(name: name) : g,
    ];
    _rebuildLocalViews();
  }

  void _localDeleteGroup(String id) {
    contactGroups = contactGroups.where((g) => g.id != id).toList();
    contacts = <QContact>[
      for (final c in contacts)
        c.groupId == id ? c.copyWith(clearGroup: true) : c,
    ];
    if (selectedGroupId == id) selectedGroupId = null;
    _rebuildLocalViews();
  }

  void _localMoveFriend(String name, String? groupId) {
    final target = (groupId == null || groupId.isEmpty) ? null : groupId;
    contacts = <QContact>[
      for (final c in contacts)
        c.name == name
            ? (target == null
                ? c.copyWith(clearGroup: true)
                : c.copyWith(groupId: target))
            : c,
    ];
    _rebuildLocalViews();
  }

  void _localDeleteFriend(String name) {
    contacts = contacts.where((c) => c.name != name).toList();
    threads.remove(name);
    if (selectedContactName == name) selectedContactName = null;
    _rebuildLocalViews();
  }

  /// 所有关系链写操作的统一执行器：忙碌态、内联错误、成功 toast。
  void _runContacts(
    Future<void> Function() action, {
    String? success,
    bool closeDialog = false,
  }) {
    if (contactsBusy) return;
    contactsBusy = true;
    contactsError = null;
    _notify();
    action().then((_) {
      if (closeDialog) {
        contactDialog = QContactDialog.none;
        dialogTarget = null;
        dialogTargetName = null;
      }
      if (success != null) flash(success);
    }, onError: (Object error) {
      contactsError = _errorText(error);
      flash(contactsError!);
    }).whenComplete(() {
      contactsBusy = false;
      _notify();
    });
  }

  String _errorText(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');

  void refreshContacts() {
    final b = backend;
    if (b == null) {
      _notify();
      return;
    }
    _runContacts(() => b.refreshContacts());
  }

  void searchUsersForAdd(String q) {
    final b = backend;
    if (b == null) {
      searchResults = _localSearch(q);
      contactsError = null;
      _notify();
      return;
    }
    contactsError = null;
    _notify();
    b.searchContacts(q).then((_) {}, onError: (Object error) {
      contactsError = _errorText(error);
      _notify();
    });
  }

  void sendFriendRequest(String account, String message) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localSendRequest(account, message);
      } else {
        await b.sendFriendRequest(account, message);
      }
    }, success: '好友申请已发送');
  }

  void acceptFriendRequest(String id) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localDecide(id, true);
      } else {
        await b.acceptFriendRequest(id);
      }
    }, success: '已通过好友申请');
  }

  void rejectFriendRequest(String id) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localDecide(id, false);
      } else {
        await b.rejectFriendRequest(id);
      }
    }, success: '已拒绝好友申请');
  }

  void createFriendGroup(String name) {
    final trimmed = name.trim();
    final b = backend;
    _runContacts(() async {
      if (trimmed.isEmpty) throw StateError('请输入分组名称');
      if (b == null) {
        _localCreateGroup(trimmed);
      } else {
        await b.createFriendGroup(trimmed);
      }
    }, success: '分组已创建');
  }

  void renameFriendGroup(String id, String name) {
    final trimmed = name.trim();
    final b = backend;
    _runContacts(() async {
      if (trimmed.isEmpty) throw StateError('请输入分组名称');
      if (b == null) {
        _localRenameGroup(id, trimmed);
      } else {
        await b.renameFriendGroup(id, trimmed);
      }
    }, success: '分组已重命名', closeDialog: true);
  }

  void deleteFriendGroup(String id) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localDeleteGroup(id);
      } else {
        await b.deleteFriendGroup(id);
      }
    }, success: '分组已删除，好友回到未分组');
  }

  void moveFriend(String name, String? groupId) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localMoveFriend(name, groupId);
      } else {
        await b.moveFriendToGroup(name, groupId);
      }
    }, success: '已调整好友分组', closeDialog: true);
  }

  void deleteFriend(String name) {
    final b = backend;
    _runContacts(() async {
      if (b == null) {
        _localDeleteFriend(name);
      } else {
        await b.deleteFriend(name);
      }
    }, success: '已删除好友', closeDialog: true);
  }

  // -------------------------------------------------- 好友管理窗口的 UI 状态
  void openContactsDialog(
    QContactDialog dialog, {
    String? target,
    String? targetName,
  }) {
    contactDialog = dialog;
    dialogTarget = target;
    dialogTargetName = targetName;
    contactsError = null;
    if (dialog == QContactDialog.addFriend) {
      searchResults = const <QUserHit>[];
    }
    _notify();
    if (dialog == QContactDialog.requests ||
        dialog == QContactDialog.groups) {
      refreshContacts();
    }
  }

  void closeContactsDialog() {
    contactDialog = QContactDialog.none;
    dialogTarget = null;
    dialogTargetName = null;
    contactsError = null;
    _notify();
  }

  void setContactsQuery(String q) {
    contactsQuery = q;
    _notify();
  }

  void selectContactGroup(String? id) {
    selectedGroupId = id;
    selectedContactName = null;
    _notify();
  }

  void selectContact(String name) {
    selectedContactName = name;
    _notify();
  }

  void askConfirm({
    required String title,
    required String message,
    required String action,
    required String target,
  }) {
    confirmTitle = title;
    confirmMessage = message;
    confirmAction = action;
    confirmTarget = target;
    openContactsDialog(QContactDialog.confirm);
  }

  void runConfirm() {
    switch (confirmAction) {
      case 'deleteFriend':
        deleteFriend(confirmTarget);
      case 'deleteGroup':
        deleteFriendGroup(confirmTarget);
    }
    contactDialog = QContactDialog.none;
    _notify();
  }

  /// 主面板「+」：打开好友管理窗口并直接进入添加好友。
  void openAddFriend() {
    panelMenu = false;
    open(QWindowKind.friendsManager);
    openContactsDialog(QContactDialog.addFriend);
  }

  String get selectedGroupName {
    if (selectedGroupId == null) return '全部好友';
    for (final g in contactGroups) {
      if (g.id == selectedGroupId) return g.name;
    }
    return '全部好友';
  }

  /// 当前分组 + 搜索词过滤后的好友（好友管理页照片卡数据源）。
  List<QContact> get visibleContacts {
    final q = contactsQuery.trim().toLowerCase();
    return contacts.where((c) {
      if (selectedGroupId != null &&
          (c.groupId ?? '') != selectedGroupId) {
        return false;
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.account.toLowerCase().contains(q) ||
          c.signature.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  QContact? contactByName(String? name) {
    if (name == null) return null;
    for (final c in contacts) {
      if (c.name == name) return c;
    }
    return null;
  }

  // ------------------------------------------------- 后端数据回填（QBackend）
  void applyContacts({
    required List<QContactGroup> groups,
    required List<QContact> contacts,
  }) {
    contactGroups = groups;
    this.contacts = contacts;
    final ids = groups.map((g) => g.id).toSet();
    if (selectedGroupId != null && !ids.contains(selectedGroupId)) {
      selectedGroupId = null;
    }
    _notify();
  }

  void applySearchResults(List<QUserHit> rows) {
    searchResults = rows;
    _notify();
  }

  void applyFriendRequests(List<QFriendRequestInfo> rows) {
    friendRequests = rows;
    _notify();
  }

  void clearBackendThread(String friend) {
    threads.remove(friend);
    _notify();
  }

  // ---------------------------------------------------------------- toast
  void flash(String text) {
    toast = text;
    _toastTimer?.cancel();
    _notify();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      toast = null;
      _notify();
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _disposed = true;
    super.dispose();
  }
}

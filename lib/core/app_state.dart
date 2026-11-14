import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Offset;

import 'models.dart';

/// QQ 概念版前端状态（纯 ChangeNotifier，无第三方状态管理库）。
/// 只负责 UI 状态与内存数据，不接后端、不落盘。
class QAppState extends ChangeNotifier {
  QAppState({String preset = 'demo'}) {
    _applyPreset(preset);
  }

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
    windows.clear();
    _z = 0;
  }

  void _applyPreset(String preset) {
    switch (preset) {
      case 'login':
        _reset(logged: false);
        _open(QWindowKind.login);
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
      if (k == QWindowKind.login) continue;
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
    if (account.trim().isEmpty || password.trim().isEmpty) {
      flash('请输入帐号和密码');
      return;
    }
    loggedIn = true;
    windows.removeWhere((w) => w.kind == QWindowKind.login);
    // 登录后默认落在好友列表 tab，分组折叠，点击分组名展开好友行。
    panelTab = 0;
    expandedGroup = null;
    _open(QWindowKind.panel);
    flash('登录成功 · 欢迎回来，$account');
  }

  void logout() {
    _reset(logged: false);
    threads.clear();
    _open(QWindowKind.login);
    flash('已退出登录');
    _notify();
  }

  void changeUser() {
    password = '';
    _reset(logged: false);
    _open(QWindowKind.login);
    flash('请重新登录');
    _notify();
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

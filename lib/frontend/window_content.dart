import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/widgets.dart';
import '../screens/about_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/friends_manager_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_panel.dart';
import '../screens/register_screen.dart';
import '../screens/settings_screen.dart';
import 'panel_flip.dart';

/// 单个 QQ 窗口的内容（不含窗口外框 / 拖拽条）。
///
/// 画布桌面与「OS 级独立窗口」共用这一份接线：两者只是窗口按钮的落点不同
/// （画布内改 z-order / minimized，原生窗口改 NSWindow 状态），UI 与交互
/// 必须完全一致，否则两套实现会逐帧漂移。
Widget buildQWindowContent(
  QAppState st,
  QWindow w, {
  required void Function(QWinBtnKind kind) onWindowButton,
}) {
  switch (w.kind) {
    case QWindowKind.login:
      return LoginScreen(
        account: st.account,
        password: st.password,
        remember: st.remember,
        presence: st.loginPresence,
        onPresenceChanged: st.setLoginPresence,
        busy: st.apiBusy,
        statusText: st.apiBusy
            ? '正在连接服务…'
            : (st.authError ?? (st.backend == null ? null : 'API 服务已就绪')),
        statusError: st.authError != null,
        onAccountChanged: st.setAccount,
        onPasswordChanged: st.setPassword,
        onRememberChanged: st.setRemember,
        onLogin: st.login,
        onRegister: st.openRegisterWindow,
        onMinimize: () => onWindowButton(QWinBtnKind.minimize),
        onClose: () => onWindowButton(QWinBtnKind.close),
        onSettings: st.localStore == null ? null : st.openSettingsWindow,
      );

    case QWindowKind.register:
      return RegisterScreen(state: st, onButtonTap: onWindowButton);

    case QWindowKind.panel:
      final panel = Builder(
        builder: (context) => MainPanel(
          tab: st.panelTab,
          onTabChanged: st.setPanelTab,
          menuOpen: st.panelMenu,
          onDismissMenu: st.toggleMainMenu,
          onFriendTap: st.selectFriend,
          onMenuAction: st.handleMenuAction,
          onFooterAction: st.handleMenuAction,
          onWindowButton: onWindowButton,
          onSearchChanged: st.setSearchQuery,
          // 主面板「+」：打开好友管理窗口并直接进入添加好友流程。
          onAddTap: st.openAddFriend,
          onGroupTap: st.toggleGroup,
          onMainMenuTap: st.toggleMainMenu,
          onNicknameTap: st.backend == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => _NicknameDialog(state: st),
                ),
          selectedName: st.activeFriend,
          searchQuery: st.searchQuery,
          expandedGroup: st.expandedGroup,
          friendGroups: st.friendGroups,
          friends: st.friends,
          recentChats: st.recentChats,
          unreadCounts: st.unreadCounts,
          myPresence: st.visibleMyPresence,
          friendPresence: st.backend == null
              ? null
              : (st.backendConnected
                    ? st.presence
                    : const <String, QPresence>{}),
          onPresenceChanged: st.presenceBusy ? null : st.changePresence,
          displayName: st.backend == null ? 'wzw' : st.displayName,
          signature: st.backend == null ? '若不在连，请留言或邮件至' : st.signature,
          // 注册时选的内置头像登录后显示在左上角相框（null = 设计稿默认剪影）。
          myAvatarIndex: st.myAvatarIndex,
        ),
      );
      // 设置页作为面板背面：绕 Y 轴 3D 翻转进入，返回键反向翻回。
      return PanelFlip(
        flipped: st.panelSettings,
        front: panel,
        back: _settings(st, w, flipped: true, onWindowButton: onWindowButton),
      );

    case QWindowKind.chat:
      return ChatScreen(
        friendName: w.friend,
        messages: st.thread(w.friend),
        onSend: (text) => st.sendMessage(text, friend: w.friend),
        onClose: () => onWindowButton(QWinBtnKind.close),
        onMinimize: () => onWindowButton(QWinBtnKind.minimize),
        onMaximize: () => onWindowButton(QWinBtnKind.maximize),
        onFolderTap: () => st.flash('文件传输暂未接入（前端演示）'),
        onMailTap: () => st.flash('邮件暂未接入（前端演示）'),
        sendWithEnter: !st.sendCtrlEnter,
        sendWithCtrlEnter: st.sendCtrlEnter,
      );

    case QWindowKind.friendsManager:
      return FriendsManagerScreen(
        state: st,
        onButtonTap: onWindowButton,
        onFriendTap: st.selectFriend,
      );

    case QWindowKind.settings:
      return _settings(st, w, flipped: false, onWindowButton: onWindowButton);

    case QWindowKind.about:
      return AboutScreen(
        onButtonTap: onWindowButton,
        onOk: () => onWindowButton(QWinBtnKind.close),
      );
  }
}

class _NicknameDialog extends StatefulWidget {
  const _NicknameDialog({required this.state});

  final QAppState state;

  @override
  State<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends State<_NicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.displayName,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.changeNickname(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst(
            RegExp(r'^(Exception|FormatException|Bad state): '),
            '',
          );
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      title: const Text('修改昵称'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        enabled: !_busy,
        decoration: InputDecoration(labelText: '昵称', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '保存中' : '保存'),
        ),
      ],
    );
  }
}

/// 设置页。两种承载方式：
/// - [flipped] true：作为主面板背面（窗口内 3D 翻转），返回/保存都翻回面板；
/// - false：独立设置窗口（顶栏快捷入口、任务栏、`#settings` 预设）。
Widget _settings(
  QAppState st,
  QWindow w, {
  required bool flipped,
  required void Function(QWinBtnKind kind) onWindowButton,
}) {
  return SettingsScreen(
    values: <String, bool>{
      'autoStart': st.autoStart,
      'alwaysOnTop': st.alwaysOnTop,
      'autoHide': st.autoHide,
      'sound': st.sound,
      'sendCtrlEnter': st.sendCtrlEnter,
    },
    onToggle: st.setSetting,
    localStore: st.localStore,
    loggedIn: st.loggedIn,
    onSave: () async {
      try {
        await st.commitSettings();
        st.flash('设置已保存');
        if (flipped) {
          st.closePanelSettings();
        } else {
          onWindowButton(QWinBtnKind.close);
        }
      } catch (error) {
        st.flash('保存设置失败：$error');
      }
    },
    onCancel: () {
      if (flipped) {
        st.closePanelSettings();
      } else {
        onWindowButton(QWinBtnKind.close);
      }
    },
    onButtonTap: (k) {
      if (!flipped) {
        onWindowButton(k);
        return;
      }
      // 翻转态：← 返回 → 反向翻转；– / × 作用于主面板窗口本身。
      switch (k) {
        case QWinBtnKind.back:
          st.closePanelSettings();
        case QWinBtnKind.gear:
          break;
        default:
          onWindowButton(k);
      }
    },
  );
}

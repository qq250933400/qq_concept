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
        busy: st.apiBusy,
        statusText: st.apiBusy
            ? '正在连接服务…'
            : (st.authError ??
                (st.backend == null ? null : 'API 服务已就绪')),
        statusError: st.authError != null,
        onAccountChanged: st.setAccount,
        onPasswordChanged: st.setPassword,
        onRememberChanged: st.setRemember,
        onLogin: st.login,
        onRegister: st.openRegisterWindow,
        onMinimize: () => onWindowButton(QWinBtnKind.minimize),
        onClose: () => onWindowButton(QWinBtnKind.close),
      );

    case QWindowKind.register:
      return RegisterScreen(
        state: st,
        onButtonTap: onWindowButton,
      );

    case QWindowKind.panel:
      final panel = MainPanel(
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
        selectedName: st.activeFriend,
        searchQuery: st.searchQuery,
        expandedGroup: st.expandedGroup,
        friendGroups: st.friendGroups,
        friends: st.friends,
        // 注册时选的内置头像登录后显示在左上角相框（null = 设计稿默认剪影）。
        myAvatarIndex: st.myAvatarIndex,
      );
      // 设置页作为面板背面：绕 Y 轴 3D 翻转进入，返回键反向翻回。
      return PanelFlip(
        flipped: st.panelSettings,
        front: panel,
        back: _settings(
          st,
          w,
          flipped: true,
          onWindowButton: onWindowButton,
        ),
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
      return _settings(
        st,
        w,
        flipped: false,
        onWindowButton: onWindowButton,
      );

    case QWindowKind.about:
      return AboutScreen(
        onButtonTap: onWindowButton,
        onOk: () => onWindowButton(QWinBtnKind.close),
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
    onSave: () {
      st.commitSettings();
      st.flash('设置已保存');
      if (flipped) {
        st.closePanelSettings();
      } else {
        onWindowButton(QWinBtnKind.close);
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

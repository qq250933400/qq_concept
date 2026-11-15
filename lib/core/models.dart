import 'package:flutter/material.dart';

import 'tokens.dart';

/// 前端窗口类型。设计稿的九个 shot 收敛成 7 类真实窗口：
/// 主面板四态（默认/好友/菜单/竹叶）是一个窗口的四种内部状态。
enum QWindowKind {
  login,
  register,
  panel,
  chat,
  friendsManager,
  settings,
  about,
}

enum QPresence {
  online('在线', Color(0xFF61C847)),
  offline('离线', Color(0xFF929BA2)),
  away('离开', Color(0xFFE6B84A)),
  busy('忙碌', Color(0xFFE85C50));

  const QPresence(this.label, this.color);
  final String label;
  final Color color;

  static QPresence? parse(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

String qWindowTitle(QWindowKind kind, [String? friend]) => switch (kind) {
  QWindowKind.login => '登录',
  QWindowKind.register => '注册',
  QWindowKind.panel => '主面板',
  QWindowKind.chat => friend == null ? '聊天' : '与 $friend 聊天',
  QWindowKind.friendsManager => '好友管理',
  QWindowKind.settings => '设置',
  QWindowKind.about => '关于',
};

Size qWindowSize(QWindowKind kind) => switch (kind) {
  QWindowKind.login => const Size(S.loginCanvasW, S.loginCanvasH),
  QWindowKind.register => const Size(S.regW, S.regH),
  QWindowKind.panel => const Size(S.mainCanvasW, S.mainCanvasH),
  QWindowKind.chat => const Size(S.chatW, S.chatH),
  QWindowKind.friendsManager => const Size(S.fmW, S.fmH),
  QWindowKind.settings => const Size(S.settingsW, S.settingsH),
  QWindowKind.about => const Size(S.aboutW, S.aboutH),
};

/// 可拖拽标题栏高度（窗口局部坐标 0..dragH）。
/// 登录/主面板的窗口本体分别下沉 42/32，故条带要覆盖到标题栏底部。
double qDragHeight(QWindowKind kind) => switch (kind) {
  QWindowKind.login => S.loginWinTop + S.loginTitleH,
  QWindowKind.register => S.dlgBarH,
  QWindowKind.panel => S.mainWinTop + S.glassHeadH,
  QWindowKind.chat => S.chatTitleH,
  QWindowKind.friendsManager => S.fmTitleH + S.fmBar2H,
  QWindowKind.settings => S.settingsBarH,
  QWindowKind.about => S.dlgBarH,
};

class QWindow {
  QWindow({
    required this.id,
    required this.kind,
    this.friend,
    this.pos,
    this.minimized = false,
    this.z = 0,
  });

  final String id;
  final QWindowKind kind;

  /// 仅聊天窗口使用，用于按好友开多个会话。
  final String? friend;

  /// null 表示尚未拖动，由桌面按当前屏幕尺寸计算默认位置。
  Offset? pos;
  bool minimized;
  int z;
}

/// 好友数据（自绘头像替身，无真实素材）。
class QFriend {
  const QFriend(
    this.name,
    this.sig,
    this.bg,
    this.skin,
    this.hair, [
    this.sel = false,
  ]);

  final String name;
  final String sig;
  final Color bg;
  final Color skin;
  final Color hair;

  /// 设计稿里的默认选中行（苏禾），交互态下会被 state.activeFriend 覆盖。
  final bool sel;
}

const List<QFriend> kFriends = [
  QFriend(
    '阿澈',
    '拍拍网友情，别来无恙…',
    Color(0xFF6B4526),
    Color(0xFFE8C49C),
    Color(0xFF35231A),
  ),
  QFriend(
    '周小满',
    '★[转] 穷人为什么穷？富人为什…',
    Color(0xFFDFE4E8),
    Color(0xFFE8C49C),
    Color(0xFF4A3A2A),
  ),
  QFriend(
    '苏禾',
    '/kh//等待是这么的漫长，可是人的一…',
    Color(0xFFD8A8BC),
    Color(0xFFF2DCC8),
    Color(0xFF8A3F5A),
    true,
  ),
  QFriend(
    '林岚',
    '/kh//zyz/ 努力就有收获。',
    Color(0xFF8FA8BC),
    Color(0xFFE8D5B8),
    Color(0xFF3A2E26),
  ),
  QFriend(
    '陈默',
    '明天太阳会照常升起，世界…',
    Color(0xFF3A5A7A),
    Color(0xFFF2D8B0),
    Color(0xFF2E2620),
  ),
  QFriend(
    '何小满',
    '/kh/ 不问世事，与技术…',
    Color(0xFF9AB88A),
    Color(0xFFF0D8B8),
    Color(0xFF5A3A28),
  ),
];

/// 主面板好友分组（API 模式下由服务端 friend_groups 驱动）。
class QFriendGroup {
  const QFriendGroup(this.label, this.members);
  final String label;
  final List<QFriend> members;
}

/// 把服务端好友映射到设计稿里的自绘头像替身。
/// 同名好友沿用 [kFriends] 的配色，保证视觉零漂移；新好友按名字取稳定色。
QFriend qFriendFromApi(String name, String signature) {
  for (final f in kFriends) {
    if (f.name == name) {
      return QFriend(
        name,
        signature.isEmpty ? f.sig : signature,
        f.bg,
        f.skin,
        f.hair,
        f.sel,
      );
    }
  }
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  const palettes = <List<Color>>[
    [Color(0xFF6B4526), Color(0xFFE8C49C), Color(0xFF35231A)],
    [Color(0xFFDFE4E8), Color(0xFFE8C49C), Color(0xFF4A3A2A)],
    [Color(0xFFD8A8BC), Color(0xFFF2DCC8), Color(0xFF8A3F5A)],
    [Color(0xFF8FA8BC), Color(0xFFE8D5B8), Color(0xFF3A2E26)],
    [Color(0xFF3A5A7A), Color(0xFFF2D8B0), Color(0xFF2E2620)],
    [Color(0xFF9AB88A), Color(0xFFF0D8B8), Color(0xFF5A3A28)],
  ];
  final p = palettes[hash % palettes.length];
  return QFriend(name, signature, p[0], p[1], p[2]);
}

class QMessage {
  const QMessage(
    this.text,
    this.self,
    this.at, {
    this.clientMsgId,
    this.seq,
    this.pending = false,
  });

  final String text;
  final bool self;
  final DateTime at;

  /// 服务端幂等键：本地乐观消息与 WS `msg.ack` / `msg.new` 靠它对齐。
  final String? clientMsgId;

  /// 会话内递增序号，断线补偿时用于去重。
  final int? seq;
  final bool pending;

  QMessage confirmed({int? seq}) => QMessage(
    text,
    self,
    at,
    clientMsgId: clientMsgId,
    seq: seq ?? this.seq,
    pending: false,
  );
}

class QRecentChat {
  const QRecentChat(this.friend, this.message, this.unread);

  final QFriend friend;
  final QMessage message;
  final int unread;
}

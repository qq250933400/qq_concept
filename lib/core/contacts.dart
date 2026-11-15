/// 关系链数据对象：好友分组 / 好友 / 好友申请 / 搜索命中。
///
/// 纯 Dart，不依赖 Flutter、HTTP 或 WebSocket：
/// [QAppState] 持有这些列表，[QBackend] 负责回填，UI 只读不改。
/// 这样「接真实 API」与「离线画廊演示」共用同一套渲染与交互代码。
library;

class QContactGroup {
  const QContactGroup({
    required this.id,
    required this.name,
    this.sort = 0,
    this.count = 0,
  });

  /// 服务端 UUID；空串表示「未分组」虚拟分组，或离线演示生成的本地分组。
  final String id;
  final String name;
  final int sort;
  final int count;

  QContactGroup copyWith({String? name, int? sort, int? count}) =>
      QContactGroup(
        id: id,
        name: name ?? this.name,
        sort: sort ?? this.sort,
        count: count ?? this.count,
      );
}

class QContact {
  const QContact({
    required this.id,
    required this.name,
    this.account = '',
    this.signature = '',
    this.groupId,
  });

  /// 服务端 user id；离线演示为 `local-<name>`。
  final String id;
  final String name;
  final String account;
  final String signature;

  /// null = 未分组。
  final String? groupId;

  QContact copyWith({String? name, String? signature, String? groupId,
      bool clearGroup = false}) =>
      QContact(
        id: id,
        name: name ?? this.name,
        account: account,
        signature: signature ?? this.signature,
        groupId: clearGroup ? null : (groupId ?? this.groupId),
      );
}

class QUserHit {
  const QUserHit({
    required this.id,
    required this.account,
    required this.name,
    this.signature = '',
    this.isFriend = false,
  });

  final String id;
  final String account;
  final String name;
  final String signature;
  final bool isFriend;
}

class QFriendRequestInfo {
  const QFriendRequestInfo({
    required this.id,
    required this.account,
    required this.name,
    this.message = '',
    this.status = 0,
    this.direction = 'in',
    this.createdAt = '',
  });

  final String id;
  final String account;
  final String name;
  final String message;

  /// 0 待处理 / 1 已通过 / 2 已拒绝。
  final int status;

  /// `in` 收到的申请 / `out` 发出的申请。
  final String direction;
  final String createdAt;

  bool get pending => status == 0 && direction == 'in';

  QFriendRequestInfo copyWith({int? status, String? message}) =>
      QFriendRequestInfo(
        id: id,
        account: account,
        name: name,
        message: message ?? this.message,
        status: status ?? this.status,
        direction: direction,
        createdAt: createdAt,
      );
}

/// 好友管理窗口内的浮层对话框。具体目标由 QAppState 的 dialogTarget 携带。
enum QContactDialog {
  none,
  addFriend,
  requests,
  groups,
  friendActions,
  moveFriend,
  renameGroup,
  confirm,
}

/// 离线 / 设计稿画廊模式的默认分组（与 seed 里的 6 个分组同名）。
const List<String> kLocalGroupNames = <String>[
  '高中挚友',
  '大学好友',
  'WOW好友',
  '亲戚家人',
  '已知网友',
  '淘宝好友',
];

import 'profile.dart';
import 'models.dart';

/// 状态层与真实后端之间的抽象边界。
///
/// [QAppState] 只依赖这个接口，不 import 任何 HTTP / WebSocket 代码：
/// - 接真实 API 时由 `lib/api/api_bridge.dart` 实现；
/// - 不接（`QQ_USE_API=false` 或设计稿画廊）时为 null，走本地演示数据。
/// 这样画布桌面与 OS 级多窗口共用同一套状态，UI 无需感知数据来源。
///
/// 关系链方法统一「执行请求 → 成功后回填 state」，不返回业务对象，
/// 避免把 DTO 直接暴露给 UI；错误以异常抛出，由 QAppState 转成内联提示。
abstract class QBackend {
  /// 登录成功后由实现负责回填好友、会话、设置等数据。
  Future<void> login(String account, String password);

  /// 用注册窗口提交的完整资料注册并直接登录（含昵称 / 性别 / 内置头像）。
  Future<void> register(QRegistration reg);

  Future<void> logout();

  /// 打开某个好友的聊天窗时调用：取或建会话、拉历史、上报已读。
  Future<void> openConversation(String friendName);

  Future<void> send(String friendName, String text);

  /// 设置页「保存」时批量写入。
  Future<void> saveSettings(Map<String, bool> values);

  Future<void> setPresence(QPresence status);

  Future<String> updateNickname(String nickname);

  // ---------------------------------------------------------------- 关系链
  /// 重新拉取分组 + 好友 + 收到的/发出的申请（登录、窗口打开、写操作后）。
  Future<void> refreshContacts();

  /// 按帐号 / 昵称搜索全站用户，结果回填 state.searchResults。
  Future<void> searchContacts(String query);

  /// 向指定帐号发送好友申请（附言可空）。
  Future<void> sendFriendRequest(String account, String message);

  Future<void> acceptFriendRequest(String id);

  Future<void> rejectFriendRequest(String id);

  Future<void> createFriendGroup(String name);

  Future<void> renameFriendGroup(String id, String name);

  Future<void> deleteFriendGroup(String id);

  /// groupId 为 null = 移回「未分组」。
  Future<void> moveFriendToGroup(String friendName, String? groupId);

  Future<void> deleteFriend(String friendName);

  /// WS 是否已连上（供主面板状态点显示）。
  bool get connected;
}

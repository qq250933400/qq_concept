/// 状态层与真实后端之间的抽象边界。
///
/// [QAppState] 只依赖这个接口，不 import 任何 HTTP / WebSocket 代码：
/// - 接真实 API 时由 `lib/api/api_bridge.dart` 实现；
/// - 不接（`QQ_USE_API=false` 或设计稿画廊）时为 null，走本地演示数据。
/// 这样画布桌面与 OS 级多窗口共用同一套状态，UI 无需感知数据来源。
abstract class QBackend {
  /// 登录成功后由实现负责回填好友、会话、设置等数据。
  Future<void> login(String account, String password);

  /// 用当前输入的帐号密码注册并直接登录。
  Future<void> register(String account, String password);

  Future<void> logout();

  /// 打开某个好友的聊天窗时调用：取或建会话、拉历史、上报已读。
  Future<void> openConversation(String friendName);

  Future<void> send(String friendName, String text);

  /// 设置页「保存」时批量写入。
  Future<void> saveSettings(Map<String, bool> values);

  /// WS 是否已连上（供主面板状态点显示）。
  bool get connected;
}

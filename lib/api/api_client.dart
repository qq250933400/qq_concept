import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_models.dart';

class QApiException implements Exception {
  const QApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  @override
  String toString() => message.isEmpty ? code : message;
}

/// 无状态 REST 客户端：token 只在内存里，`401 TOKEN_EXPIRED` 自动轮换一次并重放。
/// 任意 API 实例都能服务任意请求，因此客户端不需要粘滞会话。
class QApiClient {
  QApiClient({String? baseUrl, http.Client? httpClient})
    : baseUrl = baseUrl ?? qResolveApiBase(),
      deviceId = qNewDeviceId(),
      _http = httpClient ?? http.Client();

  String baseUrl;
  final String deviceId;
  final http.Client _http;

  String? accessToken;
  String? refreshToken;
  String? userId;

  bool get signedIn => accessToken != null;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('$baseUrl$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
    bool retried = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    late final http.Response res;
    final uri = _uri(path, query);
    try {
      switch (method) {
        case 'GET':
          res = await _http.get(uri, headers: headers);
        case 'POST':
          res = await _http.post(uri, headers: headers, body: _body(body));
        case 'PUT':
          res = await _http.put(uri, headers: headers, body: _body(body));
        case 'PATCH':
          res = await _http.patch(uri, headers: headers, body: _body(body));
        case 'DELETE':
          res = await _http.delete(uri, headers: headers);
        default:
          throw QApiException(0, 'CLIENT', '不支持的 HTTP 方法 $method');
      }
    } on QApiException {
      rethrow;
    } catch (error) {
      throw QApiException(0, 'NETWORK', '无法连接服务：$error');
    }

    final json = _safeDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return json;

    final code = json['code']?.toString() ?? 'HTTP_${res.statusCode}';
    final message = json['message']?.toString() ?? '请求失败（${res.statusCode}）';
    if (res.statusCode == 401 && code == 'TOKEN_EXPIRED' && !retried &&
        refreshToken != null) {
      try {
        await refresh();
        return await _request(method, path,
            body: body, query: query, auth: auth, retried: true);
      } catch (_) {
        clearTokens();
        throw const QApiException(401, 'TOKEN_EXPIRED', '登录已过期，请重新登录');
      }
    }
    throw QApiException(res.statusCode, code, message);
  }

  static String? _body(Map<String, dynamic>? body) =>
      body == null ? null : jsonEncode(body);

  static Map<String, dynamic> _safeDecode(String raw) {
    if (raw.isEmpty) return const <String, dynamic>{};
    try {
      return qDecode(raw);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  void clearTokens() {
    accessToken = null;
    refreshToken = null;
    userId = null;
  }

  // ------------------------------------------------------------ 认证 / 用户
  Future<Map<String, dynamic>> register(
    String account,
    String password, {
    String? nickname,
    int gender = 0,
    String? avatarUrl,
  }) =>
      _request('POST', '/auth/register', auth: false, body: <String, dynamic>{
        'account': account,
        'password': password,
        'nickname': (nickname == null || nickname.trim().isEmpty)
            ? account
            : nickname.trim(),
        'gender': gender,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      });

  Future<Map<String, dynamic>> login(String account, String password) async {
    final platform = deviceId.split('-').first;
    clearTokens();
    final json = await _request('POST', '/auth/login', auth: false,
        body: <String, dynamic>{
          'account': account.trim(),
          'password': password,
          'device_id': deviceId,
          'platform': platform,
          'client_version': '1.0.0',
        });
    accessToken = json['access_token']?.toString();
    refreshToken = json['refresh_token']?.toString();
    userId = (json['user'] is Map)
        ? json['user']['id']?.toString()
        : null;
    if (accessToken == null || refreshToken == null || userId == null) {
      throw const QApiException(500, 'BAD_RESPONSE', '登录响应缺少令牌');
    }
    return json;
  }

  Future<void> refresh() async {
    final token = refreshToken;
    if (token == null) {
      throw const QApiException(401, 'TOKEN_EXPIRED', '登录已过期，请重新登录');
    }
    final json = await _request('POST', '/auth/refresh', auth: false,
        body: <String, dynamic>{'refresh_token': token});
    accessToken = json['access_token']?.toString();
    refreshToken = json['refresh_token']?.toString();
    if (accessToken == null || refreshToken == null) {
      throw const QApiException(401, 'TOKEN_INVALID', '刷新令牌无效');
    }
  }

  Future<void> logout() async {
    if (!signedIn) return;
    try {
      await _request('POST', '/auth/logout', body: <String, dynamic>{
        'refresh_token': refreshToken,
      });
    } catch (_) {
      // 网络断开时仍允许本地退出。
    }
    clearTokens();
  }

  Future<ApiUser> me() async =>
      ApiUser.fromJson(await _request('GET', '/users/me'));

  Future<void> setPresence(String status) async {
    await _request('PUT', '/users/me/presence', body: {'status': status});
  }

  Future<Map<String, dynamic>> updateMe({
    String? nickname,
    String? signature,
  }) =>
      _request('PATCH', '/users/me', body: <String, dynamic>{
        if (nickname != null) 'nickname': nickname,
        if (signature != null) 'signature': signature,
      });

  // ------------------------------------------------------------ 关系链
  Future<Map<String, dynamic>> friends() => _request('GET', '/friends');

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final json = await _request('GET', '/users/search',
        query: <String, String>{'q': q, 'limit': '20'});
    return qList(json['items']);
  }

  Future<Map<String, dynamic>> createFriendRequest(
    String toAccount, {
    String message = '',
  }) =>
      _request('POST', '/friend-requests', body: <String, dynamic>{
        'to_account': toAccount,
        if (message.trim().isNotEmpty) 'message': message.trim(),
      });

  Future<List<Map<String, dynamic>>> friendRequests(
      [String direction = 'in']) async {
    final json = await _request('GET', '/friend-requests',
        query: <String, String>{'direction': direction});
    return qList(json['items']);
  }

  Future<Map<String, dynamic>> acceptRequest(String id) =>
      _request('POST', '/friend-requests/$id/accept');

  Future<Map<String, dynamic>> rejectRequest(String id) =>
      _request('POST', '/friend-requests/$id/reject');

  Future<Map<String, dynamic>> createGroup(String name, int sort) =>
      _request('POST', '/friend-groups',
          body: <String, dynamic>{'name': name, 'sort': sort});

  Future<Map<String, dynamic>> renameGroup(String id, String name) =>
      _request('PATCH', '/friend-groups/$id',
          body: <String, dynamic>{'name': name});

  Future<Map<String, dynamic>> deleteGroup(String id) =>
      _request('DELETE', '/friend-groups/$id');

  /// [clearGroup] 为 true 时显式传 `group_id: null`，把好友移回「未分组」。
  /// 不能靠 `groupId == null` 判断：那同时表示「本次不修改分组」。
  Future<Map<String, dynamic>> patchFriend(
    String friendId, {
    String? groupId,
    String? remark,
    bool clearGroup = false,
  }) =>
      _request('PATCH', '/friends/$friendId', body: <String, dynamic>{
        if (groupId != null) 'group_id': groupId,
        if (clearGroup) 'group_id': null,
        if (remark != null) 'remark': remark,
      });

  Future<Map<String, dynamic>> deleteFriend(String friendId) =>
      _request('DELETE', '/friends/$friendId');

  // ------------------------------------------------------------ 会话 / 消息
  Future<Map<String, dynamic>> conversations() =>
      _request('GET', '/conversations');

  Future<Map<String, dynamic>> createConversation(String peerId) =>
      _request('POST', '/conversations',
          body: <String, dynamic>{'peer_id': peerId});

  Future<Map<String, dynamic>> messages(
    String conversationId, {
    int? afterSeq,
    int? beforeSeq,
    int limit = 50,
  }) =>
      _request('GET', '/conversations/$conversationId/messages',
          query: <String, String>{
            'limit': '$limit',
            if (afterSeq != null) 'after_seq': '$afterSeq',
            if (beforeSeq != null) 'before_seq': '$beforeSeq',
          });

  Future<Map<String, dynamic>> markRead(
          String conversationId, int upToSeq) =>
      _request('POST', '/conversations/$conversationId/read',
          body: <String, dynamic>{'up_to_seq': upToSeq});

  // ------------------------------------------------------------ 设置
  Future<Map<String, dynamic>> settings() => _request('GET', '/settings');

  Future<Map<String, dynamic>> putSettings(Map<String, bool> values) =>
      _request('PUT', '/settings', body: <String, dynamic>{'settings': values});

  void dispose() => _http.close();
}

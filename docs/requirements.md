# QQ 概念版后端 · 需求规格与实施说明

| 项 | 内容 |
|---|---|
| 版本 | v1.0 |
| 状态 | 待评审 → 可开工 |
| 读者 | 后端开发、前端（Flutter）对接、测试 |
| 前置 | 前端交互已实现：登录 / 主面板 / 聊天 / 设置 / 好友管理（见 `docs/multiwindow-analysis.md`） |
| 配套 | `docs/backend-requirements.md`（选型论证与技术背景，本文是其落地版本） |

---

## 1. 背景与目标

### 1.1 现状

Flutter 桌面端已用官方 Windowing API 实现「1 控制台 + N 个原生窗口」，交互闭环完整：
登录 → 主面板（好友/群组/最近消息三 tab、分组展开、搜索、双击开会话）→ 每个会话一个独立窗口
→ 齿轮 3D 翻转进入设置。但**数据全部是内存假数据**，集中在 `lib/core/app_state.dart`：

- `login()` 只把 `loggedIn = true`，不做任何校验；
- `sendMessage()` 用 `Future.delayed(900ms)` + `_reply()` 本地伪造对方回复；
- 好友、分组、会话是 `main_panel.dart` 里的 `const` 常量；
- 设置项只存在内存，重启即丢。

### 1.2 目标

用最小可用后端替换上述四处假实现，让两个真实账号能互相加好友、聊天、看到已读，
并且**重启不丢消息**。不追求高并发，追求「正确 + 可扩展」。

### 1.3 成功判据（一期）

1. 两个账号分别在两台设备（或本机双实例）登录，互发消息延迟 P95 < 150ms；
2. 断网 30s 后恢复，消息不丢、不重、不乱序；
3. 关闭应用重开，会话列表与历史消息与关闭前一致；
4. 前端不需要为「多窗口」做任何额外改造（多窗口共享同一份 state 的架构已具备）。

---

## 2. 范围

### 2.1 本期做（M0 + M1）

登录注册、好友申请与关系链、分组、单聊文本消息、会话列表、未读与已读、多端登录、
断线重连与增量补偿、设置云同步（部分项）。

### 2.2 本期不做

群聊、图片/文件消息（M2）、语音视频、消息撤回、离线推送、端到端加密、
举报与内容审核、运营后台、Qzone、注册短信验证。

> 边界原则：任何「让界面多一个按钮」的需求都推到 M2，一期只保证现有按钮全部真实可点。

---

## 3. 角色与主要用例

| 角色 | 用例 |
|---|---|
| 普通用户 | 注册/登录、加好友、发消息、看历史、改设置、退出登录 |
| 系统 | 定序、去重、未读累加、断线补偿、顶号踢下线 |

---

## 4. 功能需求

> 编号规则：`FR-模块-序号`。每条都要能在验收时判定通过与否，不接受「体验良好」这类描述。

### 4.1 账号与登录（FR-A）

| 编号 | 需求 | 验收标准 |
|---|---|---|
| FR-A-01 | 账号密码登录 | 正确凭证返回 token 与用户资料；错误凭证返回 401 `AUTH_BAD_CREDENTIAL`，且不区分「账号不存在/密码错」 |
| FR-A-02 | 注册 | 账号唯一、密码 ≥ 6 位；昵称 / 性别 / 内置头像随注册提交；重复账号返回 409 `ACCOUNT_EXISTS` |
| FR-A-03 | Token 刷新 | access 过期（15min）后，用 refresh（7d）静默换新；refresh 失效则前端回登录窗 |
| FR-A-04 | 多端登录 | 同一账号可在 3 台设备并存；第 4 台登录踢掉最早的一台，被踢端收到 `kick` 帧并回登录窗 |
| FR-A-05 | 记住密码 | 前端只持久化 refreshToken（Keychain），不保存明文密码；取消勾选则退出后清空 |
| FR-A-06 | 退出登录 | 服务端注销当前设备 session；前端关闭全部内容窗口、清空本地缓存 |
| FR-A-07 | 登录失败限流 | 同账号 5 次/5 分钟失败后返回 429，冷却 5 分钟 |

**规则细节**

- 密码哈希用 `argon2id`（memory 19MB, iterations 2, parallelism 1），禁止 md5/sha1。
- `account` 大小写不敏感：入库统一 lowercase，唯一索引建在 lowercase 上。
- 登录成功要顺带返回：`user`、`friendsVersion`（关系链版本号，用于判断是否需要重拉好友）。

### 4.2 关系链（FR-F）

| 编号 | 需求 | 验收标准 |
|---|---|---|
| FR-F-01 | 好友列表 | 返回按分组聚合的好友，含在线状态、备注名、会话未读数；单次 ≤ 500 条 |
| FR-F-02 | 搜索用户 | 支持按账号精确、昵称模糊（`pg_trgm`）搜索；不返回已是好友之外的隐私字段（手机/邮箱） |
| FR-F-03 | 发起好友申请 | 同一对用户只能有一条 pending 申请；对方已是好友返回 409 `ALREADY_FRIENDS` |
| FR-F-04 | 处理申请 | 通过时事务内：改申请状态 + 写双向 `friendships` + 建单聊会话；任一步失败整体回滚 |
| FR-F-05 | 备注与分组 | 备注 ≤ 32 字符；移动分组立即生效（`friendships.group_id`） |
| FR-F-06 | 删除好友 | 删双向关系与会话成员，**保留**历史消息；双方会话列表移除该会话 |
| FR-F-07 | 分组管理 | 支持新增/重命名/排序；删除分组时其下好友移到默认分组（不允许悬空） |

**规则细节**

- `friendships` 双向各存一行（`(user_id, friend_id)` 主键），读路径只需一次索引扫描。
- 好友申请通过后，双方各自能看到对方；`friendsVersion` +1，用于其它设备增量刷新。

### 4.3 会话与消息（FR-C）

| 编号 | 需求 | 验收标准 |
|---|---|---|
| FR-C-01 | 取或建单聊会话 | 同一对用户重复调用返回同一 `conversationId`（幂等） |
| FR-C-02 | 发送文本消息 | 返回 `msgId` 与 `seq`；空消息/超 2000 字返回 400 |
| FR-C-03 | 消息幂等 | 相同 `clientMsgId` 重复提交只落一条，第二次返回首次的 `msgId/seq` |
| FR-C-04 | 消息定序 | 同一会话 `seq` 严格 +1 递增，客户端可据此排序、去重、补洞 |
| FR-C-05 | 历史消息 | 按 `beforeSeq` 向上翻页，默认 30 条；返回 `hasMore` |
| FR-C-06 | 增量补偿 | `afterSeq` 拉取遗漏消息，单次 ≤ 200 条 |
| FR-C-07 | 会话列表 | 按 `lastMsgAt` 倒序，含最后一条摘要、未读数、置顶标记 |
| FR-C-08 | 已读上报 | 上报 `upToSeq` 后未读归零；对方收到 `msg.read`，发送端气泡显示「已读」 |
| FR-C-09 | 未读数 | 未读 = `lastSeq - readSeq`，多端登录时取各设备 `readSeq` 最大值 |
| FR-C-10 | 会话置顶/免打扰 | 单用户维度生效，不影响对方 |
| FR-C-11 | 删除会话 | 只删自己的会话成员行（软删），对方不受影响；重新收到消息会重新出现 |
| FR-C-12 | 离线消息 | 对方离线时不推送，上线后由 `ready.seqs` + `afterSeq` 补齐 |

**规则细节**

- 消息体 `content` 用 `jsonb`：`{"text":"..."}`，为 M2 的图片/文件留结构位。
- `seq` 由 `INCR conv:{id}:seq` 生成，DB 唯一索引 `(conversation_id, seq)` 兜底；Redis 丢数据时用 `max(seq)+1` 重建。
- 发送成功即刻广播给**双方所有在线设备**（写扩散），包括发送者自己的其它端，保证多端一致。
- 单条消息上限 2000 字符、单会话单用户 20 条/10s 限流。

### 4.4 设置（FR-S）

| 编号 | 需求 | 验收标准 |
|---|---|---|
| FR-S-01 | 读取设置 | 返回已存云端项 + 客户端本地项默认值 |
| FR-S-02 | 保存设置 | 只写云端项（`sendCtrlEnter`、`sound`），本地项不回传 |
| FR-S-03 | 跨端一致 | A 设备改 `sendCtrlEnter` 后，B 设备下次登录读到新值 |

**存储归属**

| 设置项 | 归属 | 说明 |
|---|---|---|
| 自启动 / 窗口置顶 / 自动隐藏 | 本地 | 与系统行为绑定，上云无意义 |
| 声音提示 | 云端 | 换设备希望一致 |
| Ctrl+Enter 发送 | 云端 | 跨端一致 |
| 窗口位置与大小 | 本地 | 每窗口独立记忆 |

### 4.5 文件（FR-M，M2 预留）

| 编号 | 需求 | 验收标准 |
|---|---|---|
| FR-M-01 | 预签名直传 | 返回带过期时间的 PUT URL；服务端只校验大小/类型/哈希，不中转流量 |

> 一期只留接口形状，不实现 UI。

---

## 5. 非功能需求（NFR）

| 编号 | 项 | 指标 |
|---|---|---|
| NFR-01 | 消息延迟 | 在线 P95 < 150ms（同城同机房） |
| NFR-02 | 连接容量 | 单机 5k 长连接稳定 30min，内存 < 1.5GB |
| NFR-03 | 可用性 | 单实例重启期间，客户端 30s 内自动重连成功 |
| NFR-04 | 安全 | 全链路 TLS；密码 argon2id；日志不打印 token/密码/消息正文 |
| NFR-05 | 可观测 | 结构化日志（traceId）、`/healthz`、关键指标：在线连接数、发送 QPS、ack 延迟、重连率 |
| NFR-06 | 兼容 | 客户端版本号随请求上报，服务端保留一个版本的接口兼容 |
| NFR-07 | 数据 | 消息永久保留（一期），用户可删除本地会话 |

---

## 6. HTTP 接口契约

- 统一前缀 `/v1`，JSON，`snake_case`（与 Dart 模型生成一致）。
- 除 `/auth/*` 外均需 `Authorization: Bearer <accessToken>`。
- 时间统一 ISO8601 UTC 字符串；ID 统一 UUID v4 字符串。
- 分页统一游标：`{ "items": [], "next_cursor": "..." }`，禁止 offset。

### 6.1 接口清单

| 方法 | 路径 | 说明 | 需求 |
|---|---|---|---|
| POST | `/auth/register` | 注册 | FR-A-02 |
| POST | `/auth/login` | 登录 | FR-A-01/04 |
| POST | `/auth/refresh` | 换 token | FR-A-03 |
| POST | `/auth/logout` | 注销本设备 | FR-A-06 |
| GET | `/users/me` | 当前用户 | FR-A-01 |
| PATCH | `/users/me` | 改昵称/签名 | FR-F-01 |
| GET | `/devices` | 设备列表 | FR-A-04 |
| DELETE | `/devices/{id}` | 踢下线 | FR-A-04 |
| GET | `/friends` | 分组 + 好友 | FR-F-01 |
| GET | `/users/search?q=` | 搜用户 | FR-F-02 |
| POST | `/friend-requests` | 发起申请 | FR-F-03 |
| GET | `/friend-requests?direction=` | 申请列表 | FR-F-03 |
| POST | `/friend-requests/{id}/accept` | 通过 | FR-F-04 |
| POST | `/friend-requests/{id}/reject` | 拒绝 | FR-F-04 |
| PATCH | `/friends/{userId}` | 备注/分组 | FR-F-05 |
| DELETE | `/friends/{userId}` | 删好友 | FR-F-06 |
| POST | `/friend-groups` | 建分组 | FR-F-07 |
| PATCH | `/friend-groups/{id}` | 改名/排序 | FR-F-07 |
| DELETE | `/friend-groups/{id}` | 删分组 | FR-F-07 |
| GET | `/conversations` | 会话列表 | FR-C-07 |
| POST | `/conversations` | 取或建单聊 | FR-C-01 |
| GET | `/conversations/{id}/messages` | 历史/增量 | FR-C-05/06 |
| POST | `/conversations/{id}/read` | 已读 | FR-C-08 |
| PATCH | `/conversations/{id}` | 置顶/免打扰 | FR-C-10 |
| DELETE | `/conversations/{id}` | 删会话 | FR-C-11 |
| GET | `/settings` | 读设置 | FR-S-01 |
| PUT | `/settings` | 写设置 | FR-S-02 |

### 6.2 登录示例

```http
POST /v1/auth/login
Content-Type: application/json

{
  "account": "10001",
  "password": "Passw0rd!",
  "device_id": "mac-9f3a...",
  "platform": "macos",
  "client_version": "1.0.0"
}
```

```json
{
  "access_token": "eyJhbGciOi...",
  "refresh_token": "rt_8f2c...",
  "expires_in": 900,
  "user": {
    "id": "0f2a...",
    "account": "10001",
    "nickname": "云帆",
    "avatar_url": "https://...",
    "signature": "在路上"
  },
  "friends_version": 12
}
```

### 6.3 拉消息示例

```http
GET /v1/conversations/{id}/messages?before_seq=&limit=30
```

```json
{
  "items": [
    {
      "id": "m_1",
      "seq": 42,
      "sender_id": "u_a",
      "type": 1,
      "content": { "text": "在吗" },
      "created_at": "2026-11-14T12:00:00Z"
    }
  ],
  "has_more": true
}
```

### 6.4 错误响应

```json
{ "code": "AUTH_BAD_CREDENTIAL", "message": "账号或密码不正确", "trace_id": "9f3a..." }
```

| HTTP | code | 场景 |
|---|---|---|
| 400 | `VALIDATION_FAILED` | 参数非法（附 `fields`） |
| 401 | `AUTH_BAD_CREDENTIAL` / `TOKEN_EXPIRED` | 登录失败 / token 过期 |
| 403 | `FORBIDDEN` / `ACCOUNT_FROZEN` | 无权限 / 冻结 |
| 404 | `NOT_FOUND` | 对象不存在 |
| 409 | `ACCOUNT_EXISTS` / `ALREADY_FRIENDS` / `DUPLICATE_REQUEST` | 幂等或冲突 |
| 429 | `RATE_LIMITED` / `AUTH_TOO_MANY_ATTEMPTS` | 限流 |
| 500 | `INTERNAL` | 未知错误（不返回堆栈） |

---

## 7. 实时协议（WebSocket）

`wss://<host>/ws?token=<accessToken>&device_id=<id>`，文本帧，JSON：

```json
{ "type": "msg.send", "id": "c-1", "ts": 1763121600000, "data": { } }
```

### 7.1 帧类型

| 方向 | type | data | 说明 |
|---|---|---|---|
| S→C | `ready` | `{session_id, server_time, seqs:{"<convId>": 42}}` | 建连成功，给增量基线 |
| C→S | `ping` | `{}` | 30s 一次 |
| S→C | `pong` | `{}` | 3 次未回则重连 |
| C→S | `msg.send` | `{client_msg_id, conversation_id, type, content}` | 发消息 |
| S→C | `msg.ack` | `{client_msg_id, msg_id, seq, created_at}` | 落库成功 |
| S→C | `msg.new` | `{message}` | 新消息（多端同步也走这里） |
| C→S | `msg.read` | `{conversation_id, up_to_seq}` | 已读上报 |
| S→C | `msg.read` | `{conversation_id, user_id, up_to_seq}` | 对方已读 |
| C→S | `typing` | `{conversation_id}` | 输入中（3s 节流，M2） |
| S→C | `presence` | `{user_id, status}` | 在线状态 |
| S→C | `kick` | `{reason}` | 顶号/封禁 |

### 7.2 发送消息完整示例

```json
{ "type": "msg.send", "id": "c-1", "ts": 1763121600000,
  "data": { "client_msg_id": "6f1c...", "conversation_id": "cv_1",
            "type": 1, "content": { "text": "在吗" } } }
```

```json
{ "type": "msg.ack", "id": "c-1", "ts": 1763121600120,
  "data": { "client_msg_id": "6f1c...", "msg_id": "m_9", "seq": 43,
            "created_at": "2026-11-14T12:00:00Z" } }
```

### 7.3 可靠性规则（必须实现）

1. **有序**：客户端按 `seq` 排序去重；发现缺口（`seq > last+1`）先拉 `afterSeq` 补齐再渲染。
2. **至少一次**：`msg.send` 10s 无 `ack` 则重发，服务端按 `(sender_id, client_msg_id)` 唯一索引去重。
3. **补偿**：重连后对比 `ready.seqs` 与本地 `lastSeq`，缺口走 HTTP，不在 WS 上回溯。
4. **背压**：单连接待发队列 > 500 帧时丢弃 `typing`/`presence`，消息帧不丢。
5. **路由**：`presence:{uid} → gateway_id` 存 Redis；跨网关用 pubsub 转发。

---

## 8. 数据模型

```sql
create table users (
  id uuid primary key,
  account varchar(32) not null,
  account_lower varchar(32) not null unique,
  phone varchar(20),
  email varchar(120),
  password_hash text not null,
  nickname varchar(32) not null,
  avatar_url text,
  signature varchar(140),
  status smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table devices (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  device_id varchar(64) not null,
  platform varchar(16) not null,
  last_seen_at timestamptz not null default now(),
  push_token text,
  unique (user_id, device_id)
);

create table friend_groups (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  name varchar(32) not null,
  sort int not null default 0
);

create table friendships (
  user_id uuid not null references users(id) on delete cascade,
  friend_id uuid not null references users(id) on delete cascade,
  group_id uuid references friend_groups(id) on delete set null,
  remark varchar(32),
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id)
);
create index idx_friendships_group on friendships(user_id, group_id);

create table friend_requests (
  id uuid primary key,
  from_user_id uuid not null references users(id) on delete cascade,
  to_user_id uuid not null references users(id) on delete cascade,
  message varchar(140),
  status smallint not null default 0,
  created_at timestamptz not null default now()
);
create unique index uq_friend_requests_pending
  on friend_requests(from_user_id, to_user_id) where status = 0;

create table conversations (
  id uuid primary key,
  type smallint not null default 1,
  last_msg_id uuid,
  last_msg_at timestamptz,
  last_seq bigint not null default 0,
  created_at timestamptz not null default now()
);

create table conversation_members (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  peer_id uuid,
  read_seq bigint not null default 0,
  muted boolean not null default false,
  pinned boolean not null default false,
  deleted_at timestamptz,
  primary key (conversation_id, user_id)
);
create index idx_members_user on conversation_members(user_id, pinned desc);

create table messages (
  id uuid primary key,
  conversation_id uuid not null references conversations(id) on delete cascade,
  seq bigint not null,
  sender_id uuid not null references users(id),
  type smallint not null default 1,
  content jsonb not null,
  client_msg_id varchar(64),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (conversation_id, seq),
  unique (sender_id, client_msg_id)
);
create index idx_messages_conv_seq on messages(conversation_id, seq desc);

create table user_settings (
  user_id uuid not null references users(id) on delete cascade,
  key varchar(48) not null,
  value jsonb not null,
  primary key (user_id, key)
);
```

**迁移**：Flyway 或 Prisma Migrate，命名 `V1__init.sql`。

---

## 9. 关键流程

### 9.1 登录 → 建连 → 补增量

```mermaid
sequenceDiagram
  participant C as 客户端
  participant A as API
  participant G as 网关
  participant R as Redis
  C->>A: POST /v1/auth/login
  A->>R: 写 session(uid, deviceId)
  A-->>C: access/refresh + user + friendsVersion
  C->>G: WSS ?token=
  G->>R: 绑定 presence:{uid} → gatewayId
  G-->>C: ready{seqs}
  C->>A: GET /conversations（列表 + 未读）
  C->>A: GET /messages?after_seq=（有缺口时）
  C->>C: 渲染主面板，恢复未读
```

### 9.2 发消息

```mermaid
sequenceDiagram
  participant A as 发送端
  participant S as 服务端
  participant B as 接收端
  A->>S: msg.send(clientMsgId)
  S->>S: INCR seq → 事务落库 → 幂等校验
  S-->>A: msg.ack(msgId, seq)
  S->>B: msg.new(seq)（含发送者其它端）
  B->>S: msg.read(upToSeq)
  S-->>A: msg.read（显示已读）
```

### 9.3 断线重连

```mermaid
flowchart LR
  D[断线] --> R[指数退避重连 1s→30s]
  R --> C{连接成功?}
  C -- 否 --> R
  C -- 是 --> S[ready.seqs 对比本地 lastSeq]
  S --> G{有缺口?}
  G -- 是 --> P[HTTP afterSeq 拉增量]
  G -- 否 --> OK[恢复在线]
  P --> OK
```

---

## 10. 前端改造清单（文件级）

| 文件 | 改动 |
|---|---|
| `lib/core/app_state.dart` | `login()` 改调 `AuthRepository`；`sendMessage()` 改走 `MessageRepository`（删掉 `_reply()`）；新增 `connection` 状态 |
| `lib/core/models.dart` | 增加 `userId/conversationId/seq/status` 等字段，与后端 DTO 对齐 |
| 新增 `lib/data/api_client.dart` | Dio/HttpClient 封装：baseUrl、拦截器（注入 token、统一错误码→异常） |
| 新增 `lib/data/auth_repository.dart` | 登录/刷新/登出 + token 持久化（Keychain） |
| 新增 `lib/data/chat_repository.dart` | 会话列表、历史/增量、发送、已读 |
| 新增 `lib/data/socket_client.dart` | WS 连接、心跳、重连退避、帧分发、待发队列 |
| 新增 `lib/data/local_store.dart` | `drift` 本地库：会话表 + 最近 50 条消息，冷启动先渲染缓存 |
| `lib/screens/*.dart` | 不改结构；仅把常量数据换成 repository 数据，空态/加载态按需补 |

**开关（原规划）**：`--dart-define=QQ_API_BASE=` 为空时走现有假数据；有值时走真实后端。

> **落地状态（2026-11-14 更新，T07 与关系链客户端侧已完成）**：实际实现与上面的目录规划有差异，以代码为准。
> - 后端工程为平级 `../qq-server/`（NestJS + MySQL + Redis），不在 `server/`；
> - 客户端新增 `lib/api/`（`api_config / api_models / api_client / ws_gateway / api_bridge`）
>   与 `lib/core/backend.dart` 抽象层；`QAppState` 只依赖 `QBackend`，UI 不感知数据来源；
> - 用官方 `http` / `web_socket_channel` 代替 Dio，token 仅存内存（未做 Keychain / drift
>   本地缓存，冷启动仍从服务端拉历史）；
> - 开关改为 `QQ_USE_API`（默认 true，preset=login 时生效）、`QQ_API_BASE`
>   （默认本机 3000）、`QQ_DEMO_PASSWORD`；设计稿 URL 预设自动走本地假数据；
> - 已接入：登录/注册/登出与 refresh 自动重放、好友分组、会话历史/已读、WS 收发与
>   ack/ready 补偿、设置云同步、kick/presence。
> - **注册窗口（2026-11-15 新增）**：登录窗「注册新帐号」打开独立 OS 窗口
>   `QWindowKind.register`（480×470，`lib/screens/register_screen.dart`），字段
>   登录帐号 / 用户昵称 / 登录密码 / 重复密码 / 性别 / 内置头像；`lib/core/profile.dart`
>   定义 `QGender`（0 保密 / 1 男 / 2 女）与 `QRegistration` 值对象，`lib/core/avatars.dart`
>   定义 8 款自绘矢量头像与 `builtin://avatar/N` 编解码；提交 `POST /auth/register`
>   带 `nickname + gender + avatar_url`，注册即登录，头像显示在主面板相框。
>   服务端 `V2__user_gender.sql` 给 `users` 加 `gender TINYINT`（默认 0），
>   register / updateMe / me 均透传；资料字段只透传字符串，客户端负责绘制。
> - **关系链（本次补齐）**：`QBackend` 扩展 `refreshContacts / searchContacts /
>   sendFriendRequest / accept | rejectFriendRequest / create | rename | deleteFriendGroup /
>   moveFriendToGroup / deleteFriend`；`api_client.dart` 补 `GET /users/search`、
>   好友申请收/发/处理、分组增删改、`PATCH/DELETE /friends/{id}`；`api_bridge.dart`
>   同时回填 `QFriendGroup/QFriend` 与 `QContactGroup/QContact`，写操作成功后统一重拉
>   `/friends` 与申请列表。
> - **好友管理页已从静态设计稿改为数据驱动**：新增 `lib/core/contacts.dart` DTO、
>   `lib/screens/contacts_dialogs.dart` 浮层；`friends_manager_screen.dart` 改为
>   `AnimatedBuilder(animation: state)`，气泡球 / 照片卡 / 信息卡 / 搜索 / 分组筛选均由
>   真实关系链驱动；标题栏提供「+ 添加好友」「好友申请 (N)」「分组管理」，主面板「+」
>   直达添加好友；长按 / 右键支持改名分组、移动分组、删除好友。`staticPreview: true`
>   仅在 `#design` 画廊保留 V6.1 静态像素对照。
> - `backend == null`（`QQ_USE_API=false` 或画廊）时用 `_localContacts` / `_localDirectory`
>   做内存兜底，可完整演示「搜索 → 申请 → 通过 → 建/改/删分组 → 移动 → 删除」。
> - 验收：`test/api_integration_test.dart`、`test/contacts_integration_test.dart`
>   （`RUN_API_TEST=true` 打真实服务）、`test/contacts_state_test.dart`（离线全链路 +
>   浮层 + 画廊回归）全通过；macOS 真机自动登录、Web 无头交互冒烟
>   （REST + WS + 服务端分组渲染 + 关系链操作）均通过，截图见 `../verify/qq_contacts_*.png`。
> - 仍未做：好友备注编辑 UI（后端 `PATCH /friends/{id}` 已支持 `remark`）、
>   token 持久化与本地消息缓存、图片 / 群聊 / 撤回（M2）。

---

## 11. 工程结构与本地环境

```
server/
├─ docker-compose.yml          # postgres:16 + redis:7
├─ .env.example
├─ prisma/schema.prisma        # 或 migrations/V1__init.sql
└─ src/
   ├─ main.ts
   ├─ common/                  # 过滤器、拦截器、guards、错误码
   ├─ auth/                    # controller / service / jwt
   ├─ users/
   ├─ friends/
   ├─ conversations/
   ├─ messages/
   ├─ gateway/                 # WS 网关（Nest Gateway）
   └─ infra/                   # prisma、redis、storage 客户端
```

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: qqconcept
      POSTGRES_USER: qq
      POSTGRES_PASSWORD: qq_dev_pwd
    ports: ["5432:5432"]
    volumes: ["pgdata:/var/lib/postgresql/data"]
  redis:
    image: redis:7
    ports: ["6379:6379"]
volumes:
  pgdata:
```

```bash
cd server
cp .env.example .env
docker compose up -d
pnpm i
pnpm prisma migrate dev
pnpm start:dev          # http://localhost:3000  ws://localhost:3000/ws
```

`.env.example`

```
DATABASE_URL=postgresql://qq:qq_dev_pwd@localhost:5432/qqconcept
REDIS_URL=redis://localhost:6379
JWT_ACCESS_SECRET=dev_access_change_me
JWT_REFRESH_SECRET=dev_refresh_change_me
ACCESS_TTL=900
REFRESH_TTL=604800
PORT=3000
```

---

## 12. 任务拆解

> 估时按 1 人全职；`依赖` 列决定并行度。

### M0（约 1 周，可跑通双人聊天）

| ID | 任务 | 依赖 | 产出 | 验收 |
|---|---|---|---|---|
| T01 | 工程骨架 + compose + Prisma 初始迁移 | — | 表建好、`/healthz` 通 | `docker compose up` 后能连库 |
| T02 | 用户模型 + 注册/登录 + argon2 + JWT | T01 | `/auth/*` | 错误码表 4 条用例通过 |
| T03 | 统一响应/异常过滤器 + traceId | T01 | `common/` | 任意错误返回统一结构 |
| T04 | WS 网关：握手鉴权、ready、心跳 | T02 | `gateway/` | 连接后 5s 内收到 ready |
| T05 | 发消息闭环：定序、落库、ack、广播 | T04 | `messages/` | 两账号互发，seq 连续 |
| T06 | 会话列表 + 历史分页 | T05 | `/conversations*` | 重启后列表与消息一致 |
| T07 ✅ | Flutter 接入：api_client + auth + chat + 关系链（已落地 `lib/api/*`、`lib/core/contacts.dart`、`lib/screens/contacts_dialogs.dart`） | T02/T05 | `lib/api/*`, `lib/core/backend.dart` | 关掉假数据仍可用；真实服务集成测试通过 |
| T08 | M0 联调与缺陷修复 | 全部 | — | §1.3 判据 1、3 通过 |

### M1（约 2 周）

| ID | 任务 | 依赖 | 验收 |
|---|---|---|---|
| T09 ✅ | 好友申请/通过/拒绝（事务） | T02 | 通过后双方互见，双向关系正确 |
| T10 ✅ | 好友列表 + 分组 + 搜索 | T09 | 500 条内返回 < 200ms |
| T11 ◐ | 备注/移动分组/删除好友 | T10 | 删除后历史消息仍在 |
| T12 | 已读回执 + 未读计数 | T05 | 对方已读 200ms 内可见 |
| T13 | 多端登录 + 顶号踢下线 | T04 | 第 4 台登录，最早端收到 kick |
| T14 | 断线重连 + afterSeq 补偿 | T13 | 断网 30s 恢复不丢不重 |
| T15 | 设置云同步 | T02 | 两设备读到同一值 |
| T16 | e2e 用例（auth/消息/好友） | 全部 | CI 跑通 |

> **M1 落地状态（2026-11-14）**：服务端接口由 `../qq-server/` 全部提供（27 REST + WS 帧，
> 双实例 29 项冒烟覆盖已读回执、顶号 kick、after_seq 补偿、设置跨实例一致）；
> 客户端已接线 T09/T10（好友申请收发与处理、好友列表 / 分组 / 搜人、分组增删改、
> 移动分组、删除好友）。
> **T11 为部分完成**：`api_client.patchFriend()` 已支持 `remark`，但好友管理页尚未提供
> 备注编辑入口；移动分组与删除好友已完成。
> 其余 M1 项的状态以 `qq-server/docs/api.md` 与 `qq_concept/README.md` 的验证章节为准。

### 开发约定

- 分支：`feat/<模块>-<简述>`；提交遵循 Conventional Commits。
- DTO 命名：`XxxRequest` / `XxxResponse`；DTO 只出现在 controller 边界。
- 每个 Service 方法一个事务边界；跨聚合（如加好友）必须显式 `$transaction`。
- 错误码集中在 `common/error-codes.ts`，禁止魔法字符串。
- 每个接口至少一条 e2e；消息相关必须覆盖「重复 clientMsgId」「乱序到达」。

---

## 13. 风险与开放问题

| 风险 | 影响 | 对策 |
|---|---|---|
| Redis 丢 seq | 消息序号回退 | 落库唯一索引冲突时用 `max(seq)+1` 重建并告警 |
| 断线风暴 | 网关被打挂 | 客户端指数退避 + 抖动；服务端按 IP/用户限流 |
| 大群扇出（M2） | CPU 打满 | 200 人以上转读扩散 + 拉取 |
| 本地缓存与服务器不一致 | 显示错乱 | 以 `seq` 为唯一真值，缓存只做加速 |

**待定（需产品确认）**

1. 注册是否需要手机验证码？（一期不做，账号密码即可）
2. 消息保留策略：一期永久，是否需要 TTL？
3. 是否需要「已读」对双方可见？当前按 QQ 习惯默认可见，可开关。
4. 头像存储：一期用对象存储直传，是否需要图片审核？

---

## 14. 术语

| 术语 | 含义 |
|---|---|
| seq | 会话内消息序号，单调递增，客户端排序与补洞的唯一依据 |
| clientMsgId | 客户端生成的消息唯一 ID，用于服务端幂等 |
| 写扩散 | 发一条消息时给每个接收者的每个在线设备各推一份 |
| 增量补偿 | 断线重连后按 afterSeq 拉取遗漏消息 |
| 顶号 | 同一账号在新设备登录，旧设备被强制下线 |

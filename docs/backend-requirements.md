# QQ 概念版 · 后端需求与系统架构（从现有 UI 反推）

> **落地版见 [`requirements.md`](./requirements.md)**（带需求编号、验收标准、任务拆解、
> 建库 DDL 与本地环境），本文保留选型论证与技术背景。
>
> 输入：本仓库已实现的 Flutter 前端（6 类窗口、单 `QAppState`、纯内存假数据）。
> 目标：把「界面已经长出来的交互」翻译成可落地实现的产品需求、接口契约与技术架构。

---

## 0. 结论摘要

| 项 | 结论 |
|---|---|
| 后端框架 | **NestJS (Node 22 + Fastify + Prisma)** 起步；协议与分层严格照 MVC 规范写，为后续换 Java 留迁移面 |
| 存储 | PostgreSQL 16（主库）+ Redis 7（会话/在线状态/未读/seq/跨网关 pubsub）+ S3 兼容对象存储（文件/头像） |
| 实时通道 | 原生 WebSocket（不复用 HTTP 轮询），单会话单调 `seq` + 客户端 `ack` + 断线增量补偿 |
| 认证 | JWT（access 15min / refresh 7d）+ 设备维度 session，多端并行登录 |
| 一期范围 | 登录、单聊（文本）、好友与分组、最近会话、未读/已读、设置云同步 |
| 明确不做（一期） | 群聊、音视频、端到端加密、离线推送、运营后台 |

选型理由与「什么时候该换 Java」见 §7，架构图与关键时序见 §8。

---

## 1. 现状盘点：界面已经承诺了哪些能力

前端所有状态集中在 `lib/core/app_state.dart`（412 行、无网络层）。按窗口归类：

| 窗口 | 已实现的交互 | 隐含的后端需求 |
|---|---|---|
| 登录 | 账号/密码输入、记住密码、登录、注册（占位）、最小化/关闭 | 账号体系、密码校验、token、记住密码=本地凭证 |
| 主面板 | 三 tab（好友/群组/最近消息）、分组展开、搜索过滤、双击开会话、齿轮→设置翻转、企鹅球→主菜单 | 关系链（分组/好友）、会话列表与排序、搜索、未读计数 |
| 聊天 | 发送、Enter/Ctrl+Enter 切换、自动回复（假）、消息列表、文件/邮件入口（占位）、最小化/最大化/关闭 | 消息收发与持久化、seq 顺序、已读、文件上传、多窗口会话共享 |
| 好友管理 | 照片卡、好友点选开会话、窗口按钮 | 好友资料、备注/分组、增删好友、申请审批 |
| 设置 | 5 个开关（自启动/置顶/自动隐藏/声音/Ctrl+Enter）、保存、取消、3D 翻转返回 | 设置项存储（本地 vs 云端）、部分项需写回客户端偏好 |
| 关于 | 版本信息、确定 | 版本/更新检查（可选） |

**关键结论**：界面里已经有 3 个「假实现」需要替换为真实调用 ——
`login()`（无校验）、`sendMessage()` + `_reply()`（本地定时回复）、`handleMenuAction()` 中的 Qzone 占位。

---

## 2. 真实产品应有的能力地图

### 2.1 能力分层

```
账号与安全  注册/登录/改密/设备管理/多端互踢/风控
关系链      好友申请/通过/删除/备注/分组/黑名单
消息        单聊/群聊/富媒体/撤回/引用/已读/未读/漫游
会话        会话列表/置顶/免打扰/草稿/删除
文件        头像/图片/文件上传下载、秒传、缩略图
状态        在线/离开/忙碌/自定义签名
设置        本地偏好 + 云端偏好（跨端一致）
运营        举报/审核/敏感词/统计（后期）
```

### 2.2 分期（MVP → P1 → P2）

| 期 | 内容 | 判定标准 |
|---|---|---|
| M0 | 登录、单聊文本、好友列表（只读）、最近会话、未读 | 两个账号能互发消息、重启不丢 |
| M1 | 好友申请/通过/删除/备注、分组、搜索、已读回执、多端同步、断线补偿 | 三端（Mac 双开 + Web）消息一致 |
| M2 | 图片/文件消息、群聊、撤回、会话置顶/免打扰、设置云同步 | 群内 50 人并发不丢消息 |
| M3 | 离线推送、举报与敏感词、运营后台、可观测与容量压测 | 单机 5k 长连接稳定 |

---

## 3. 核心交互流程（可直接转成验收用例）

### 3.1 登录

1. 输入账号密码 → `POST /v1/auth/login`（带 `deviceId`、`platform`）
2. 服务端校验 argon2id 哈希 → 生成 `accessToken`/`refreshToken`，登记设备
3. 客户端拿到 token 后立刻 `wss://…/ws?token=`，服务端回 `ready{sessionId, serverTime, lastSeqMap}`
4. 客户端用 `lastSeqMap` 拉各会话增量（HTTP），完成后主面板可用
5. 勾选「记住密码」→ 只存 refreshToken 到 Keychain，不存明文密码

**异常**：账号或密码错（401 `AUTH_BAD_CREDENTIAL`）、频繁失败（429 `AUTH_TOO_MANY_ATTEMPTS`，5 次/5 分钟）、账号被冻结（403）。

### 3.2 打开会话并发消息

1. 主面板双击好友 → 本地先创建会话窗口（乐观 UI），同时 `POST /v1/conversations {peerId}` 拿 `conversationId`
2. 发送：本地生成 `clientMsgId`（uuid），消息先入本地队列并渲染为「发送中」
3. 通过 WS 发 `msg.send{clientMsgId, conversationId, type, content}`
4. 服务端事务内：分配 `seq = INCR conv:{id}:seq` → 落库 → 返回 `msg.ack{clientMsgId, msgId, seq}` → 广播 `msg.new` 给双方所有在线设备
5. 客户端收到 `ack` 把「发送中」改为已发送；超时 10s 未 ack → 重发（服务端按 `(sender_id, client_msg_id)` 唯一索引幂等）
6. 对方在线：`msg.new` 直达；离线：只更新未读，上线用增量拉取

### 3.3 已读与未读

- 客户端在会话可见且窗口聚焦时上报 `msg.read{conversationId, upToSeq}`（节流 500ms）
- 服务端更新 `conversation_members.read_seq`，并在 Redis 维护 `unread:{uid}:{conv}` 计数
- 会话列表未读数 = `last_seq - read_seq`（Redis 计数用于快速列表，DB 用于补偿）

### 3.4 设置

| 设置项 | 存储位置 | 说明 |
|---|---|---|
| 自启动 / 置顶 / 自动隐藏 | 本地（客户端偏好） | 与系统行为绑定，不上云 |
| 声音提示 | 本地 + 云端 | 换设备后希望保持一致 |
| Ctrl+Enter 发送 | 云端（`user_settings`） | 跨端一致 |
| 窗口位置/尺寸 | 本地 | 多窗口各自记忆 |

---

## 4. 领域模型与表设计

只列一期必需表，字段给出类型与关键约束。

```sql
users(id uuid pk, account varchar(32) unique, phone varchar(20) null,
      email varchar(120) null, password_hash text, nickname varchar(32),
      avatar_url text, signature varchar(140), status smallint default 0,
      created_at timestamptz, updated_at timestamptz)

devices(id uuid pk, user_id uuid, device_id varchar(64), platform varchar(16),
        last_seen_at timestamptz, push_token text null,
        unique(user_id, device_id))

friend_groups(id uuid pk, user_id uuid, name varchar(32), sort int default 0)

friendships(user_id uuid, friend_id uuid, group_id uuid null,
            remark varchar(32) null, created_at timestamptz,
            primary key(user_id, friend_id))        -- 双向各存一行，读快写双

friend_requests(id uuid pk, from_user_id uuid, to_user_id uuid,
                message varchar(140), status smallint, created_at timestamptz,
                unique(from_user_id, to_user_id, status))
  -- status: 0 待处理 / 1 通过 / 2 拒绝 / 3 过期

conversations(id uuid pk, type smallint,          -- 1 单聊 2 群聊
              last_msg_id uuid null, last_msg_at timestamptz, last_seq bigint,
              created_at timestamptz)

conversation_members(conversation_id uuid, user_id uuid,
                     read_seq bigint default 0, muted bool, pinned bool,
                     peer_id uuid null,              -- 单聊冗余，便于列表查询
                     primary key(conversation_id, user_id))

messages(id uuid pk, conversation_id uuid, seq bigint, sender_id uuid,
         type smallint,                          -- 1 文本 2 图片 3 文件 4 系统
         content jsonb, client_msg_id varchar(64) null,
         created_at timestamptz, revoked_at timestamptz null,
         unique(conversation_id, seq),
         unique(sender_id, client_msg_id))       -- 幂等

user_settings(user_id uuid, key varchar(48), value jsonb,
              primary key(user_id, key))

files(id uuid pk, owner_id uuid, object_key text, size bigint,
      mime varchar(80), sha256 char(64), status smallint, created_at timestamptz)
```

**索引**
- `messages(conversation_id, seq desc)` —— 分页拉历史
- `conversation_members(user_id, pinned desc, conversation_id)` —— 会话列表
- `friendships(user_id, group_id)` —— 分组展开
- `users(account)` / `users(phone)` —— 登录与搜索（昵称搜索走 `pg_trgm`）

**seq 生成**：`INCR conv:{id}:seq`（Redis），落库唯一索引兜底；Redis 丢数据时用 `max(seq)+1` 重建。

---

## 5. HTTP API 契约

统一前缀 `/v1`，除登录/注册外全部需要 `Authorization: Bearer <accessToken>`。

### 5.1 认证

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` | 注册（账号+密码+昵称） |
| POST | `/auth/login` | 登录，返回 token + user + 设备信息 |
| POST | `/auth/refresh` | 用 refreshToken 换新 accessToken |
| POST | `/auth/logout` | 注销当前设备 session |
| GET | `/users/me` | 当前用户 |
| PATCH | `/users/me` | 改昵称/签名/头像 |
| GET | `/devices` | 登录设备列表（可踢下线） |

### 5.2 关系链

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/friends` | 返回分组 + 好友（含在线状态、未读数） |
| POST | `/friend-groups` | 新建分组 |
| PATCH | `/friend-groups/{id}` | 重命名/排序 |
| GET | `/users/search?q=&limit=20` | 按账号/昵称搜索 |
| POST | `/friend-requests` | 发起申请 |
| GET | `/friend-requests?direction=in|out&status=0` | 申请列表 |
| POST | `/friend-requests/{id}/accept` | 通过（事务内建双向 friendship + 建会话） |
| POST | `/friend-requests/{id}/reject` | 拒绝 |
| PATCH | `/friends/{userId}` | 改备注/移动分组 |
| DELETE | `/friends/{userId}` | 删除好友（不删历史消息） |

### 5.3 会话与消息

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/conversations?cursor=&limit=50` | 会话列表（按 last_msg_at 倒序） |
| POST | `/conversations` | 取或建单聊会话 → `{conversationId}`（幂等） |
| GET | `/conversations/{id}/messages?beforeSeq=&limit=30` | 历史消息（向上翻页） |
| GET | `/conversations/{id}/messages?afterSeq=&limit=200` | 增量补偿（重连/多端） |
| POST | `/conversations/{id}/messages` | HTTP 兜底发消息（WS 不可用时） |
| POST | `/conversations/{id}/read` | 上报已读 `{upToSeq}` |
| PATCH | `/conversations/{id}` | 置顶/免打扰 |
| DELETE | `/conversations/{id}` | 删除会话（本地视图） |

### 5.4 文件

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/files/presign` | 申请直传 URL `{name,size,mime,sha256}` → `{fileId,url,headers}` |
| POST | `/files/{id}/complete` | 直传完成回调，服务端校验大小/哈希 |
| GET | `/files/{id}/url` | 取下载 URL（私有桶签名） |

### 5.5 错误码

```json
{ "code": "AUTH_BAD_CREDENTIAL", "message": "账号或密码不正确", "traceId": "..." }
```

| HTTP | code | 场景 |
|---|---|---|
| 400 | `VALIDATION_FAILED` | 参数校验（附 `fields`） |
| 401 | `AUTH_BAD_CREDENTIAL` / `TOKEN_EXPIRED` | 登录失败 / token 过期 |
| 403 | `FORBIDDEN` / `ACCOUNT_FROZEN` | 无权限 / 冻结 |
| 404 | `NOT_FOUND` | 对象不存在 |
| 409 | `DUPLICATE_REQUEST` / `ALREADY_FRIENDS` | 幂等冲突 |
| 429 | `RATE_LIMITED` | 限流 |
| 500 | `INTERNAL` | 未知错误（不返回堆栈） |

分页统一游标：`{ items, nextCursor }`，禁止 offset 分页。

---

## 6. 实时通道协议

`wss://host/ws?token=<accessToken>`，二进制/文本帧统一 JSON：

```json
{ "type": "msg.send", "id": "c-1", "ts": 1731600000000, "data": { } }
```

### 6.1 帧类型

| 方向 | type | data | 说明 |
|---|---|---|---|
| S→C | `ready` | `{sessionId, serverTime, seqs:{convId:seq}}` | 建连成功，给增量基线 |
| C→S | `ping` / S→C `pong` | `{ts}` | 30s 心跳，3 次无 pong 重连 |
| C→S | `msg.send` | `{clientMsgId, conversationId, type, content}` | 发消息 |
| S→C | `msg.ack` | `{clientMsgId, msgId, seq, createdAt}` | 落库成功 |
| S→C | `msg.new` | `{message}` | 新消息（含自己的多端同步） |
| C→S | `msg.read` | `{conversationId, upToSeq}` | 已读上报 |
| S→C | `msg.read` | `{conversationId, userId, upToSeq}` | 对方已读（显示「已读」） |
| C→S | `typing` | `{conversationId}` | 输入中（3s 节流） |
| S→C | `presence` | `{userId, status}` | 在线状态变化 |
| S→C | `kick` | `{reason}` | 顶号/被封 |

### 6.2 可靠性规则

1. **有序**：同一会话内 `seq` 严格递增，客户端按 `seq` 排序、去重、补洞。
2. **至少一次 + 幂等**：客户端重发带同一 `clientMsgId`，服务端唯一索引去重。
3. **断线补偿**：重连后 `ready.seqs` 与服务端一致则无缺口；有缺口用 `afterSeq` 拉增量，禁止在 WS 上回溯。
4. **跨网关路由**：`presence:{uid} → gatewayId` 存 Redis；网关通过 Redis pubsub 互转，避免会话粘滞。
5. **背压**：单连接发送队列 > 500 帧则丢弃非关键帧（typing/presence），消息帧不丢。

---

## 7. 技术选型：Java 还是 Node

### 7.1 对比矩阵（权重按「本项目一期」的实际需求设定）

| 维度 | 权重 | Spring Boot 3 | NestJS |
|---|---|---|---|
| 实时长连接（WS 网关、心跳、路由） | 20 | 8（WebFlux/Netty，需自写编解码与路由） | 8（Gateway 装饰器 + ws/socket.io 开箱） |
| 迭代速度（UI 驱动、频繁改契约） | 20 | 6 | 9 |
| 与 Flutter 的契约一致性 | 15 | 7（springdoc 生成 OpenAPI） | 9（TS 类型 → OpenAPI → 生成 Dart 模型） |
| 事务与一致性 | 15 | 9 | 7（需自己划事务边界，Prisma 交互式事务够用） |
| 生态与中间件 | 10 | 9 | 7 |
| 水平扩展 | 10 | 8 | 8 |
| 长期可维护/招人 | 10 | 9（国内 Java 供给大） | 7 |
| **加权** | 100 | **78** | **80** |

### 7.2 结论

**一期选 NestJS**。理由：

1. 这套后端的流量特征是**长连接 + 小消息 IO 密集**，不是 CPU 密集，Node 事件循环正好对口；单机 5k~1w 空闲连接属于常规水平。
2. 前端是 Flutter，NestJS 用 TypeScript 写 DTO，可直接产出 OpenAPI 并用 `openapi-generator` 生成 Dart 客户端与模型 —— 契约漂移的成本几乎为零，这对「UI 还在频繁调整」的阶段价值最大。
3. NestJS 的 Module / Provider / Guard / Interceptor 与 Spring 一一对应，**分层写法可以完全照 Spring 来**，将来换 Java 是平移而不是重写。

**什么时候该换 Spring Boot 3（或局部换 Java/Go）**：

- 需要强一致的跨服务分布式事务（好友双向关系 + 会话 + 通知同时落库，且拆了服务）；
- 单机连接数想上 5w 以上、或消息扇出（大群）把 CPU 打满 → 把 WS 网关单独用 Netty/Go 重写，协议不变；
- 团队以 Java 为主、或要对接公司既有 Java 中台。

### 7.3 若选 Java 的等价组合

`Spring Boot 3.3` + `spring-boot-starter-web`（REST）+ `spring-websocket`（或 Netty 自建）+ `MyBatis-Plus` + `PostgreSQL` + `Redis(Lettuce)` + `springdoc-openapi` + `Flyway`。除语言外，§5/§6 的契约与 §8 的架构完全一致。

---

## 8. 系统架构

### 8.1 部署拓扑（单机可跑，按需横向扩）

```
Flutter 客户端（多窗口，共享一份 state）
      │ HTTPS(REST)          │ WSS
      ▼                      ▼
  ┌───────────────┐   ┌──────────────────┐
  │ API 服务      │   │ 实时网关 Gateway  │  ← 无状态，可 N 副本
  │ (NestJS/Fastify)│  │ (WS，心跳/路由)   │
  └───────┬───────┘   └────────┬─────────┘
          │                    │
          ├──── Redis ◄────────┤   session/在线表/未读/seq/pubsub
          │
          ├──── PostgreSQL（主库；消息、关系链、用户）
          │
          └──── 对象存储（S3/MinIO：头像、图片、文件）
```

> 一期 API 与 Gateway 可同进程（NestJS 里就是两个 Module），单机 `docker compose up` 即可跑；
> 连接数上来后把 Gateway 拆成独立进程，`presence` 与 `pubsub` 已经预留了拆分面。

### 8.2 分层职责

| 层 | 职责 | 禁止 |
|---|---|---|
| Controller / Gateway | 参数校验、鉴权、DTO 转换 | 写业务规则、直接碰 DB |
| Service（领域） | 事务边界、领域规则（加好友要双写、发消息要定序） | 依赖 HTTP 上下文 |
| Repository | 单表/聚合的读写 | 跨聚合事务 |
| Infra | Redis/队列/对象存储客户端 | 业务判断 |

### 8.3 关键设计取舍

1. **消息写扩散还是读扩散**：一期单聊，写扩散（给双方每个在线设备推一份）最简单；群聊（M2）超过 200 人再转读扩散 + 拉取。
2. **未读数**：Redis 计数为主、DB `read_seq` 为真值，二者不一致时以 DB 重算（允许短暂偏差）。
3. **多端**：同一 user 的多个 device 都订阅 `msg.new`；已读以 `max(read_seq)` 合并上报。
4. **文件**：客户端直传对象存储，服务端只签名与校验，避免大文件穿过后端。

---

## 9. Flutter 侧改造点（后端接入面）

| 现状 | 改造 |
|---|---|
| `QAppState.login()` 直接置 `loggedIn` | 调 `AuthApi.login`，成功后写 token（Keychain）+ 建 WS |
| `sendMessage()` + `_reply()` | 改为 `MessageRepository.send()`：本地乐观入列 → WS 发送 → ack 更新；删除假回复 |
| 好友/会话写死在 `main_panel.dart` 常量里 | 由 `FriendRepository` / `ConversationRepository` 提供，UI 只吃数据 |
| 无本地缓存 | 引入 `drift`（SQLite）：会话列表 + 最近 50 条消息，冷启动先读缓存再拉增量 |
| 无网络状态 | 加 `ConnectionState`（在线/重连中/离线），窗口顶栏显示；离线时消息入待发队列 |

关键：**多窗口共享同一份 state 的架构正好适配**，`QNativeWindows` 已保证所有窗口读同一个 `QAppState`，接入真实数据后无需改窗口层。

---

## 10. 里程碑与验收

| 里程碑 | 交付 | 验收标准 |
|---|---|---|
| M0（约 1 周） | 工程骨架、认证、单聊文本、好友只读、最近会话 | 两个账号在 Mac 双开互发消息；杀掉进程重开消息不丢 |
| M1（约 2 周） | 好友申请、备注/分组、搜索、已读回执、断线补偿、多端同步 | 断网 30s 后恢复，消息不丢不重；Web 与 Mac 同时在线消息一致 |
| M2（约 3 周） | 图片/文件、群聊、撤回、置顶/免打扰、设置云同步 | 50 人群发 1000 条不丢不乱序 |
| M3 | 推送、举报/敏感词、运营后台、可观测 | 单机 5k 长连接稳定 30 分钟，P95 发送延迟 < 150ms |

**风险与对策**

| 风险 | 对策 |
|---|---|
| WS 断线风暴（网络抖动） | 客户端指数退避 + 抖动（1s→30s），服务端按 IP/用户限流 |
| seq 生成成为瓶颈 | Redis INCR 单会话内串行，不同会话并行；必要时按 convId 分片 |
| 消息乱序/重复 | 客户端以 `seq` 排序去重；服务端 `(sender_id, client_msg_id)` 唯一索引 |
| 假数据遗留 | 用 `--dart-define=QQ_API_BASE=` 切换 mock/真实两种数据源，便于对照回归 |

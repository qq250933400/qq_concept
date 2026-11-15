# QQ 概念版 · Flutter 交互前端

按 `ui-v4.html` V6.1 高保真设计稿复刻的**可交互应用页面**（不是静态设计稿）。
桌面优先，UI 全部用 Flutter SDK 自绘；素材全部为自绘矢量替身。
运行时依赖仅 `http` / `web_socket_channel` 两个跨平台包（用于接入独立 API 工程）。

## 运行

> **SDK 要求**：本机已切到 Flutter **master 渠道**（3.50.0-1.0.pre，Dart 3.15），
> 并开启 `flutter config --enable-windowing`——官方实验性 Desktop Windowing API
> 只在 master 渠道可用（stable 3.47 的框架里虽有实现但被渠道门控禁用）。
> 切换回稳定版：`flutter channel stable && flutter upgrade`。

```bash
flutter pub get
./run_macos.sh               # macOS 调试运行（含 Hot Reload，推荐）
flutter run -d macos         # 等价命令；若报调试连接失败见下方说明
flutter build web --release
python3 -m http.server 8765 --directory build/web
```

`run_macos.sh` 做两件事：把 `127.0.0.1,localhost` 加入 `NO_PROXY`（否则本机代理会
拦截 VM Service 的 WebSocket 升级，报 502 / "log reader stopped unexpectedly"），
以及固定 `--host-vmservice-port=55177`。
另外 `macos/Runner/DebugProfile.entitlements` 在 Debug/Profile 关闭了 App Sandbox
（Release 仍保留）——macOS 26 从非 GUI 终端启动沙箱调试版会在
`libsecinit_appsandbox` 直接 SIGTRAP 退出，导致 `flutter run` 无法附加调试连接。

> **macOS Runner 已按官方窗口化示例改造**：`MainMenu.xib` 不再含
> `MainFlutterWindow`，`AppDelegate.swift` 手动 `FlutterEngine(...).run()`，
> 所有 NSWindow 由 Dart 创建。这是硬性要求——引擎的 `enableMultiView`
> 断言「注册任何 view controller 之前」调用，标准模板的隐式
> `FlutterViewController` 会让它抛
> `Multiview can only be enabled before adding any view controllers.`。
> 因此该 macOS 工程**必须**用 master + `--enable-windowing` 运行；
> 旧 nib 备份在 `docs/backup/MainMenu.xib.pre-windowing.bak`。

## 默认入口

默认进入 `lib/frontend/desktop.dart` 的**应用桌面**：壁纸、顶栏快捷启动、任务栏、
toast，以及 6 类可交互窗口。九屏设计稿画廊 `lib/app_shell.dart` 仅在
`#design` / `?mode=design` 下作为对照，也可点顶栏「设计稿对照」切换。

### 桌面端独立窗口（无控制台，只有内容窗口）

macOS 下 `main()` 走 `runWidget(ViewCollection)`，根只有**内容窗口**：
登录、主面板、每个聊天会话、好友管理、设置、关于各自一扇 NSWindow。
没有「桌面控制台」——不画壁纸、顶栏、任务栏，也不再有快捷启动入口；
桌面版对外就是一台正常的 IM 客户端。所有窗口共享同一个 Engine / isolate
和同一份 `QAppState`，消息收发与状态天然一致。

**页面流转（与 `docs/requirements.md` §9 的产品流程一致）**

| 时机 | 窗口变化 |
|---|---|
| 启动 | 只有登录窗（居中），未登录 |
| 登录成功 | 登录窗销毁 → 主面板创建（屏幕右上） |
| 双击好友 / 群组 / 最近消息行 | 打开或聚焦该会话的聊天窗（屏幕偏左上，逐窗 28pt 级联） |
| 主面板齿轮 / 菜单「系统设置」 | 主面板内 3D 翻转到背面设置（不新开窗口） |
| 企鹅球菜单「好友管理」「关于」 | 各自开一扇独立窗口 |
| 关闭最后一扇窗口 | 退出应用（没有托盘，关掉即退出） |
| 退出登录 / 更换用户 | 销毁全部内容窗口，重建登录窗 |

`QAppState.windows` 是唯一真值源，`QNativeWindows` 监听它并 diff 出 OS 窗口的
创建 / 销毁 / 最小化 / 置前；画布模式与原生窗口共用
`lib/frontend/window_content.dart` 的接线，UI 不会漂移。

- 预开多个聊天窗：`./run_macos.sh --dart-define=QQ_INITIAL_CHATS=阿澈,苏禾,林岚`
- 指定初始状态：`./run_macos.sh --dart-define=QQ_PRESET=login`（默认就是 login）
- 验证登录→主面板切换：
  `./run_macos.sh --dart-define=QQ_PRESET=login --dart-define=QQ_AUTO_LOGIN=true`
- 官方 API 没有 `setPosition` / frameless。`macos/Runner/AppDelegate.swift`
  通过 `qq_concept/windows` 通道拿 NSWindow 句柄：
  - `setup`：内容窗口先按 `.titled` 起窗（首帧前改 styleMask 会让 Impeller
    面尺寸错位直接崩），0.3s 后转 **borderless**：`styleMask = []` +
    `hasShadow = false` → 没有系统边框白线、没有矩形阴影灰雾；把 NSWindow /
    contentView / 各层 CALayer 背景全部清成透明，露出异形轮廓；再按锚点摆位。
  - **窗口出现时序 + 动画**：引擎首帧 `setIsVisible:YES` 就把窗口按默认坐标
    （屏幕左侧）显示，而 `setup` 摆位异步到达，中间会「从左侧闪一下」。原生层
    在 `setContentViewController:`（窗口尚未显示的创建期）就把 `alpha=0`，并在
    `setIsVisible:` / `orderFront:` 调用原实现之前再同步补压；摆位 / 透明 /
    去边框 / 重钉 frame 全在不可见阶段做完，再用 0.26s 淡入。`setup` 的 result
    这时才返回，Dart 侧 `_WindowReveal` 同步播放 340ms 的内容淡入 + 上浮 +
    轻微缩放。默认 frame 另挪到屏幕中央兜底，2.5s 兜底保证异常路径不会留下
    隐形窗口；只动 alpha 不动 frame 做动画，避免 Flutter surface 被 resize
    （详见 `docs/multiwindow-analysis.md` §14）。
  - **不能换类**：`object_setClass` 会让窗口 dealloc 走另一个类，关闭时打
    `NSAutoreleasePool ... double release`。改为替换 `NSWindow` 的
    `canBecomeKey/canBecomeKeyWindow` 实现：承载 `FlutterViewController` 的
    窗口一律返回 true，其它窗口仍按 styleMask 判断。
  - `drag`：自绘标题栏拖动交给 `performWindowDragWithEvent:`（Window Server
    自己跑鼠标追踪），窗口逐帧跟手，不再逐帧过通道。
  - 摆位用锚点（`center` / `top-right` / `center-right` / `cascade`），
    由原生按 `NSScreen.visibleFrame` 换算，换显示器不用改 Dart 常量。
  - 排查开关：`QQ_BORDERLESS=0 ./run_macos.sh` 可退回原生 titled 外观。
- **Web 与未开启窗口化的环境**自动回退到原来的单画布浮动桌面，所有 URL 预设、
  九屏画廊、3D 翻转、自定义滚动条均不受影响。

Web URL 预设（用于逐状态核对）：

| URL | 状态 |
|---|---|
| 根路径 / `#demo` | 已登录，主面板 + 聊天 + 关于可见，好友管理/设置最小化 |
| `#login` | 未登录，仅登录窗口 |
| `#register` | 未登录，登录窗 + 注册窗（接真实 API） |
| `#main` `#friends` `#menu` `#bamboo` | 主面板四态 |
| `#chat` `#fm` `#settings` `#about` | 已登录并打开对应窗口 |
| `?mode=design&shot=menu` | 设计稿对照（指定 shot） |

## 目录

- `lib/core/tokens.dart` — 设计 token（尺寸 / 颜色 / 字阶 / 渐变）
- `lib/core/widgets.dart` — 公共窗口壳、按钮、输入框、毛玻璃面板、自绘图标
- `lib/core/models.dart` — 窗口 / 好友 / 消息数据模型
- `lib/core/contacts.dart` — 关系链 DTO（分组 / 好友 / 申请 / 搜索结果）
- `lib/core/avatars.dart` — 8 款内置自绘矢量头像与 `builtin://avatar/N` 编解码
- `lib/core/profile.dart` — `QGender`（0 保密 / 1 男 / 2 女）与注册表单值对象
- `lib/core/app_state.dart` — `ChangeNotifier` 状态（会话、窗口栈、消息、设置）
- `lib/core/app_theme.dart` — 主窗口与原生子窗口共用的 Theme / 无系统滚动条行为
- `lib/core/window_chrome.dart` — 原生窗口模式下关闭卡片外阴影的开关
- `lib/frontend/desktop.dart` — 交互桌面容器（窗口化时仅作控制台：壁纸 / 顶栏 / 任务栏）
- `lib/frontend/native_windows.dart` — 官方 Windowing API：控制台 + 全部独立 OS 窗口
- `lib/frontend/window_content.dart` — 画布 / 原生窗口共用的窗口内容接线
- `macos/Runner/AppDelegate.swift` — 引擎启动 + 无标题栏 / 透明背景 / 摆位 / 原生拖动
- `lib/screens/*.dart` — 登录 / 注册 / 主面板 / 聊天 / 好友管理 / 设置 / 关于
- `lib/app_shell.dart` — 设计稿对照画廊（非默认）
- `docs/requirements.md` — **后端需求规格（落地版）**：需求编号 / 验收标准 / 接口契约 / 建表 DDL / 任务拆解
- `docs/backend-requirements.md` — 后端选型论证与架构背景（配套阅读）

## 主面板交互约定

| 操作 | 结果 |
|---|---|
| 点击分组标题（如「大学好友(21/66)」） | 展开该分组下的好友行；再点收起；点其他分组切换 |
| **双击**好友 / 群组 / 最近消息行 | 打开或聚焦该好友聊天窗（桌面端为独立 OS 窗口） |
| 点击**左下角企鹅球** | 打开/切换毛玻璃主菜单（点击菜单外部关闭） |
| 点击右上角**齿轮** / 菜单「系统设置」「个人设置」 | 主面板**绕 Y 轴 3D 翻转**到背面设置页（不新开窗口） |
| 设置页**返回 ← / 保存 / 取消** | 反向 3D 翻转回主面板；翻转期间忽略指针，设置状态保留 |
| 搜索框输入 | 按昵称 / 签名 / 拼音过滤，只显示匹配好友 |
| 点击上方 tab | 切换视图并收起已展开的分组 |

设计稿画廊 `AppShell` 用 `staticPreview: true` 保留 V6.1 四态的静态像素；
应用桌面用 `expandedGroup` / `panelTab` / `panelMenu` 驱动真实交互，两者互不干扰。

登录窗口的太阳 / 叶丛 / 云装饰层全部包了 `IgnorePointer`：
`CustomPaint` 默认吸收命中，否则叶层会盖住账号输入框导致无法聚焦。

## 状态与数据

纯内存 `QAppState`：登录态、**窗口注册表**（画布与 OS 窗口的唯一真值源）、
好友与分组、关系链（`contactGroups` / `contacts` / `friendRequests` /
`searchResults`）、会话消息、5 项设置、`expandedGroup`（当前展开分组）、
`panelTab`（三 tab）、`panelMenu`（主菜单）、`panelSettings`
（面板 3D 翻转到设置背面）、toast。不落盘。

数据源有两套，UI 代码完全共用：

- **真实 API**（默认，见下一节）：`QAppState.backend` 是一个 `QBackend`
  接口实现，由 `lib/api/api_bridge.dart` 负责 REST + WS 同步；
- **本地演示**（`QQ_USE_API=false` 或设计稿 URL 预设）：好友用 `kFriends`，
  发消息触发 900ms 后的本地模拟回复，零网络请求。

## 接入 API 服务端

后端是**平级独立工程** `../qq-server/`（NodeJS / NestJS + MySQL + Redis），
与 Flutter 代码零混用。先启动它：

```bash
cd ../qq-server
npm install && npm run build && npm run migrate
npm run seed          # 幂等：6 个分组 / 6 位好友 / 6 个会话与历史消息
npm start             # http://127.0.0.1:3000/v1
```

演示账号 `10001` / `Passw0rd!`（其余好友 10002~10007 同密码）。

客户端默认从登录窗起步时自动接入（`main.dart` 里 `preset == 'login'`）；
设计稿画廊 / `#demo`、`#main` 等 URL 预设保持纯本地数据，方便逐屏对照。

| dart-define | 默认 | 说明 |
|---|---|---|
| `QQ_USE_API` | `true` | 设 `false` 回到纯演示数据 |
| `QQ_API_BASE` | 桌面 `http://127.0.0.1:3000/v1`；Web 同源推导 `:3000/v1` | 也可传 `/v1` 走 Nginx 同源代理 |
| `QQ_DEMO_PASSWORD` | 空 | 自动化联调时预填登录密码，配合 `QQ_AUTO_LOGIN=true` |

```bash
# 桌面真机自动登录联调
flutter run -d macos --dart-define=QQ_AUTO_LOGIN=true \
  --dart-define=QQ_DEMO_PASSWORD='Passw0rd!'

# 客户端对真实服务的集成测试（默认跳过，离线 flutter test 不受影响）
NO_PROXY=127.0.0.1,localhost flutter test \
  --dart-define=RUN_API_TEST=true \
  test/api_integration_test.dart test/contacts_integration_test.dart
```

**接线清单**（`lib/api/`）

| 能力 | 实现 |
|---|---|
| 登录 / 登出 | `POST /auth/login`、`/auth/logout`；JWT 内存保存，`401 TOKEN_EXPIRED` 自动 `refresh` 并重放请求 |
| 注册 | 登录窗「注册新帐号」打开独立注册窗口（480×470），字段：登录帐号 / 用户昵称 / 登录密码 / 重复密码 / 性别 / 内置头像；`POST /auth/register` 提交昵称 + `gender` + `builtin://avatar/N`，成功即登录进主面板，头像显示在左上角相框 |
| 好友分组 | `GET /friends` → `QFriendGroup` + `QFriend` + `QContactGroup`/`QContact`；同名好友沿用设计稿配色，新好友按名字取稳定色 |
| 添加好友 / 申请 | `GET /users/search` → `POST /friend-requests` → `GET /friend-requests?direction=in\|out` → `accept` / `reject`；通过后自动重拉好友列表 |
| 关系链实时通知 | 服务端 `friend_request.new` / `friend.accepted` / `friend_request.rejected` / `friend.deleted` 通过 WS 跨节点广播，客户端收到即 toast 提示并自动重拉关系链，无需重开窗口 |
| 分组管理 | `POST /friend-groups`、`PATCH /friend-groups/{id}`（改名）、`DELETE /friend-groups/{id}`（好友回落未分组） |
| 移动 / 删除好友 | `PATCH /friends/{userId}`（`group_id` 可为 `null`）、`DELETE /friends/{userId}` |
| 会话 / 历史 / 已读 | 开窗时取或建单聊、拉 `limit=50` 历史并 `markRead`；`QMessage` 带 `seq` / `clientMsgId` / `pending` |
| 实时收发 | WS `msg.send` → 乐观插入 → `msg.ack` 确认；`msg.new` 按 `conversation_id` 路由到对应聊天窗 |
| 断线补偿 | `ready.seqs` 与本地 seq 比较，`after_seq` 补洞；WS 断线期间帧排队、指数退避重连（任意实例均可） |
| 设置 | 设置页保存时一次 `PUT /settings`；登录时 `GET /settings` 回填 |
| 顶号 / 在线 | `kick` 直接回登录窗并提示；`presence` 存入 `state.presence` |

macOS 已加 `NSAppTransportSecurity/NSAllowsLocalNetwork`（放行本机明文 HTTP）
与 `com.apple.security.network.client`（沙箱出站）；生产应改用 HTTPS。
服务不可达时登录失败会在登录窗底部内联显示错误，不会偷偷进入假数据主面板。

## 注册窗口

登录窗「注册新帐号」弹出独立 OS 窗口（480×470，深色玻璃 / 细线按钮，与好友管理
浮层同语言）。字段与行为：

| 字段 | 规则 |
|---|---|
| 登录帐号 | 3~32 位，仅字母 / 数字 / `_` / `.` / `-` |
| 用户昵称 | 1~32 位（为空时服务端回落为帐号） |
| 登录密码 | 至少 6 位 |
| 重复登录密码 | 必须与密码一致 |
| 性别 | 保密（默认）/ 男 / 女，映射服务端 `gender` 0 / 1 / 2 |
| 头像 | 8 款内置自绘矢量（`builtin://avatar/0..7`），左侧大图实时预览 |

提交前先本地校验（逐项中文提示，不请求服务）；通过后 `POST /auth/register` 落库
并**注册即登录**，登录窗 + 注册窗销毁 → 主面板创建，所选头像显示在左上角相框
（`builtin://avatar/N` → 配色回填）。`QQ_USE_API=false` 或离线时提交会内联提示
「注册需要连接 API 服务」，不会进入假数据。资料字段服务端只做字符串透传，客户端
用 `lib/core/avatars.dart` 解析绘制，不依赖任何真实图片素材。

## 添加好友与好友分组

好友管理窗口（959×597 木质桌面）现在是**真实数据驱动**；气泡球显示服务端分组
与人数，照片卡显示当前分组的真实好友，右上信息卡显示选中好友资料。
`#design` 画廊仍保留 V6.1 的 7 个静态气泡 / 13 张照片卡用于逐屏对照。

| 入口 | 动作 |
|---|---|
| 主面板「+」 | 打开好友管理窗口并直接进入「添加好友」 |
| 标题栏「+ 添加好友」 | 按帐号 / 昵称搜人 → 点「添加」发送带附言的申请 |
| 标题栏「好友申请 (N)」 | 收到的申请可「通过 / 拒绝」，发出的申请可查看状态 |
| 标题栏「分组管理」 | 新建、改名、删除分组；删除后组内好友回落「未分组」 |
| 点击气泡球 | 按分组筛选照片卡（「全部好友」= 不筛选） |
| 长按 / 右键气泡球 | 直接改名该分组（系统「未分组」则打开分组管理） |
| 点击照片卡 | 右上信息卡显示资料，同时打开聊天窗 |
| 长按 / 右键照片卡 | 好友操作：打开聊天、移动到分组、移回未分组、删除好友 |
| 第二栏搜索框 | 按昵称 / 帐号 / 签名实时过滤照片卡 |

数据流：`QAppState` → `QBackend` 抽象 → `QApiBridge`（REST 写操作成功后自动
重拉 `/friends` 并回填主面板）。关系链变更（来申请 / 对方同意 / 被拒 / 被删）
由服务端通过 WS `friend_*` 帧实时推送，客户端 toast 提示并自动重拉，双方无需
刷新窗口即可看到最新好友与申请。不接 API 时（`QQ_USE_API=false` 或画廊预设）
走本地内存兜底，同样能完整演示「搜索 → 申请 → 通过 → 分组 → 移动 → 删除」
链路。浮层对话框在 `lib/screens/contacts_dialogs.dart`，状态与离线兜底在
`lib/core/app_state.dart`，DTO 在 `lib/core/contacts.dart`。

## 验证

- `flutter analyze` → No issues found
- `flutter build web --release` / `flutter build macos --debug` → 通过
- 第二期独立窗口真机验证（`docs/multiwindow-analysis.md` §9）：
  `CGWindowListCopyWindowInfo` 实测同一 PID 下 **1 个 1440×868 控制台 +
  8 个内容窗口**（272×645 主面板 / 490×435 聊天 ×4 / 357×160 关于 /
  959×597 好友管理 / 268×645 设置），尺寸全部精确等于设计稿 → 原生标题栏已去掉；
  聊天窗按 28px 级联；`QQ_PRESET=login` 下登录窗为 372×282 且 `key:true`；
  `QQ_AUTO_LOGIN=true` 验证登录窗销毁 → 主面板独立窗创建；启动日志无 exception
- Chrome 无头交互冒烟：登录→主面板、齿轮菜单、发消息+自动回复、拼音/中文搜索、
  窗口拖拽、设置保存、好友卡开窗、打开全部，共 9 项均通过；console/pageerror = NONE
- 交互逻辑修正复验：账号框可输入（8899 参与登录）、点分组展开/收起、点左下角
  企鹅球弹菜单、齿轮打开设置、设计稿画廊未回归；截图 `../refs/flutter/f3/`
- 截图：`../refs/flutter/f2/`，总览 `f2_overview.png`
- `NO_PROXY=127.0.0.1,localhost flutter test` → All tests passed
  （不加 NO_PROXY 时本机代理会拦 flutter_tester 的 WebSocket 升级，非代码问题）
- **真实 API 集成测试**（`test/api_integration_test.dart`，打本机 3000）：
  登录 → 6 位好友 / 6 分组 / 6 会话历史回填 → 打开会话 → 发消息 `msg.ack`
  确认 pending → 另一账号 WS 发消息本端实时收到 → 服务端 REST 查到落库
  → 设置写后读回 → 登出，全通过
- **macOS 真机自动登录联调**：`[QQ][API] 登录成功：6 位好友 / 6 个分组 /
  6 个会话` → 主面板独立窗创建 → `WS 已连接`；`info` 自检
  `borderless:true / styleMask:0 / shadow:false / bgAlpha:0 / key:true`，
  窗口出现时序与透明修复无回归
- **Web 无头浏览器冒烟**：`POST /auth/login` 201、`/friends`、
  `/conversations`、6 个 `messages`、`/settings`、`/users/me` 全部 200，
  `ws://127.0.0.1:3000/ws` 握手成功，console/pageerror = NONE；
  截图确认主面板显示服务端分组，展开「大学好友(2/6)」显示苏禾 / 阿澈
- 独立窗口改造后 Web 单画布回归：Playwright 无头真实加载 + 展开分组 + tab 切换，
  console/pageerror = NONE，截图 `../verify/native_web_smoke.png`
- 拖拽 / 异形透明修复（`docs/multiwindow-analysis.md` §10）：
  - 原生回传 `content=FlutterViewWrapper / bgAlpha=0 / opaque=false`
    → 引擎给 FlutterView 涂的黑色占位底已清空；
  - `screencapture -l <windowID>` 按窗口取图，PNG 保留 alpha，
    主面板与好友管理窗口四角 `rgba(0,0,0,0)` → 圆角/相框之外真透明；
  - 真机拖动主面板 `@1098,232 → @390,416`，窗口跟随移动且无抖动
- 灰雾清理（`docs/multiwindow-analysis.md` §12）：主面板顶部装饰带 alpha
  `0.03/0.05/0.09/0.15 → 0.00`，登录窗 `0.01/0.03 → 0.00`
- 白边 / 阴影灰雾修复（`docs/multiwindow-analysis.md` §11）：
  `info` 自检 `{class: QQBorderlessWindow, styleMask: 0, borderless: true,
  shadow: false, canKey: true}`；窗口抓图上边缘 alpha≈0（无描边），
  整屏截图里木框/云叶四周直接是控制台壁纸
- **关系链功能（添加好友 / 好友分组）**：
  `test/contacts_state_test.dart` 离线全链路 + 浮层 + 画廊回归 3 项通过；
  `test/contacts_integration_test.dart` 用两个全新注册账号打真实 MySQL 服务
  （搜人 → 申请 → 对方通过 → 建/改/删分组 → 移动/删好友）通过；
  `flutter analyze` / `flutter test`（4 通过、2 个真实服务测试默认跳过）/
  `flutter build web` / `flutter build macos` 全绿
- **关系链实时通知（WS 推送，无需手动刷新）**：
  `test/friend_notify_integration_test.dart`（`RUN_API_TEST=true`）用两个真实账号
  验证：A 发申请 → B 端 `friend_request.new` 触发（申请数即时 +1）→ B 同意 →
  A 端 `friend.accepted` 触发（好友列表即时出现 B）→ B 删好友 → A 端
  `friend.deleted` 触发（好友列表即时移除），全流程不手动 refresh
- **注册窗口（本次新增）**：
  `test/register_state_test.dart` 头像编解码、表单校验、性别枚举、注册窗开关、
  离线拒绝、6 字段渲染 + 本地校验 6 项通过；
  `test/register_integration_test.dart`（`RUN_API_TEST=true`）注册 `r<suffix>`
  带昵称 / 性别 / 内置头像，`/users/me` 回读 `gender` 与 `builtin://avatar/N`
  一致；服务端 `V2__user_gender.sql` 迁移 + 单测 9 + e2e 3（含 `gender` 越界
  校验）全绿；`smoke.ts` 新增「注册资料跨实例一致」断言
- **Web 无头注册交互冒烟**（`?preset=register`，console/pageerror = NONE）：
  填 6 字段 → 选「男」+ 第 6 个头像 → 注册并登录；MySQL 回查确认
  `account` / `nickname='自动化注册'` / `gender=1` / `avatar_url='builtin://avatar/5'`
  落库。截图：`../verify/qq_register_initial.png`、`../verify/qq_register_filled.png`、
  `../verify/qq_register_after_login.png`
- **Web 无头交互回归**（`#fm`，console/pageerror = NONE）：
  浮层打开 → 搜 `10009` 命中「许知远」→ 点「添加」出现
  「好友申请已发送」→ 好友申请「发出的 (1)」→ 通过「沈星回」后
  「全部好友 (7)」且照片卡新增「沈星回」→ 分组管理 6 行 + 新建「同事」
  后标题栏变「7 个分组」并出现「共 7 个分组 · 点此管理」。
  截图：`../verify/qq_contacts_overview.png`、
  `../verify/qq_contacts_add_friend.png`、`../verify/qq_contacts_requests.png`、
  `../verify/qq_contacts_groups.png`、`../verify/qq_contacts_accepted.png`、
  `../verify/qq_contacts_group_created.png`

## 已知限制

- 内容窗口为 `floating` 层级以获得稳定置前效果，切换其它应用时仍会浮在其上方
- 原生内容窗口已转为 **borderless**（`styleMask = 0`、`hasShadow = false`），
  通过 `method_setImplementation` 补 `canBecomeKey*` 保证输入框仍可聚焦；
  详见 `docs/multiwindow-analysis.md` §11 / §12
- 好友管理页已消费 API（气泡 / 照片卡 / 搜索 / 信息卡 + 添加好友、好友申请、
  分组增删改、移动与删除好友）；设计稿画廊仍保留静态对照。
  气泡球沿用设计稿固定 7 位，最多展示 6 个真实分组，更多分组从
  「分组管理」浮层或木桌左上提示进入
- 仍未做：好友备注编辑 UI（后端 `PATCH /friends/{id}` 已支持 `remark`）、
  图片消息 / 群聊 / 消息撤回、token 持久化与本地消息缓存（M2）
- 拖动交给 Window Server 后，拖动期间 Flutter 收不到 pointer up，
  属正常现象（标题栏拖拽条不带状态，下一次按下会重置）
- 内容窗口是 borderless 且关掉了系统阴影，窗口之间没有系统投影；
  卡片自带的 `boxShadow` 在原生窗口里也会被裁在窗口内（变成一层灰雾），
  因此由 `qOuterShadow()` 在原生模式下一律不画
- 透明只影响窗口自身的空白像素；窗口仍是矩形，点击透明区域仍会命中该窗口
- macOS 合成点击受系统辅助功能权限限制，窗口按钮命中测试未做自动化回归
- 仅 macOS 做过 Runner 适配与真机验证；Windows/Linux  Runner 需同样改造后才启用
- experimental / master 渠道：窗口 API 可能在 patch 版本间 breaking
- 素材为自绘矢量替身，无腾讯原版 logo / 头像 / 表情
- Web 端中文字形与 HTML 的 PingFang SC 有细微差异
- Web 端不适用原生多窗口，保留单画布浮动桌面

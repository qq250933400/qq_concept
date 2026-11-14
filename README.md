# QQ 概念版 · Flutter 交互前端

按 `ui-v4.html` V6.1 高保真设计稿复刻的**可交互应用页面**（不是静态设计稿）。
桌面优先，纯 Flutter SDK，运行时零第三方依赖。素材全部为自绘矢量替身。

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
| `#main` `#friends` `#menu` `#bamboo` | 主面板四态 |
| `#chat` `#fm` `#settings` `#about` | 已登录并打开对应窗口 |
| `?mode=design&shot=menu` | 设计稿对照（指定 shot） |

## 目录

- `lib/core/tokens.dart` — 设计 token（尺寸 / 颜色 / 字阶 / 渐变）
- `lib/core/widgets.dart` — 公共窗口壳、按钮、输入框、毛玻璃面板、自绘图标
- `lib/core/models.dart` — 窗口 / 好友 / 消息数据模型
- `lib/core/app_state.dart` — `ChangeNotifier` 状态（会话、窗口栈、消息、设置）
- `lib/core/app_theme.dart` — 主窗口与原生子窗口共用的 Theme / 无系统滚动条行为
- `lib/core/window_chrome.dart` — 原生窗口模式下关闭卡片外阴影的开关
- `lib/frontend/desktop.dart` — 交互桌面容器（窗口化时仅作控制台：壁纸 / 顶栏 / 任务栏）
- `lib/frontend/native_windows.dart` — 官方 Windowing API：控制台 + 全部独立 OS 窗口
- `lib/frontend/window_content.dart` — 画布 / 原生窗口共用的窗口内容接线
- `macos/Runner/AppDelegate.swift` — 引擎启动 + 无标题栏 / 透明背景 / 摆位 / 原生拖动
- `lib/screens/*.dart` — 6 个屏幕、9 个界面状态
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
6 个好友、会话消息、5 项设置、`expandedGroup`（当前展开分组）、
`panelTab`（三 tab）、`panelMenu`（主菜单）、`panelSettings`
（面板 3D 翻转到设置背面）、toast。
不接后端、不落盘、不请求网络；消息回复为本地模拟。

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

## 已知限制

- 内容窗口为 `floating` 层级以获得稳定置前效果，切换其它应用时仍会浮在其上方
- 原生窗口仍保留 `.titled` styleMask 与系统阴影（保证可成为 key 窗口），
  但 NSTitlebarView / 红黄绿按钮已隐藏，视觉上无原生 chrome
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

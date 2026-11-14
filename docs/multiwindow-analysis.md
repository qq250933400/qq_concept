# QQ 概念版桌面端「真·多窗口」技术可行性与实现记录

> 结论：**可行，已实现并真机验证**。方案 C（升级 SDK + 官方实验性 Desktop
> Windowing API）。SDK = Flutter **3.50.0-1.0.pre / master**（Dart 3.15），
> `flutter config --enable-windowing`。首期范围 = **聊天窗多开**；
> 第二期 = **全部 6 类窗口独立 + 去掉原生标题栏**（见 §9）。
>
> 重要修正（相对早期草稿）：
> 1. 实际 API **没有** `RegularWindowController` / `RegularWindow` 这些类；
>    真实类型是 `WindowController`（factory，构造即创建原生窗口）、
>    `Window`、`WindowControllerDelegate`、`WindowManager` /
>    `WindowRegistry` / `WindowEntry` / `WindowScope`、`ViewCollection` /
>    `ViewAnchor`，全部在内部文件
>    `package:flutter/src/widgets/_window.dart`（需 `implementation_imports`
>    + `invalid_use_of_internal_member` 忽略）。
> 2. 官方是 **单引擎多窗口**（同一 widget 树 / 同一 isolate），共享同一份
>    `QAppState`，不需要跨 isolate 通信协议。
> 3. **macOS 必须改造 Runner**：引擎 `enableMultiView` 断言「注册任何 view
>    controller 之前」调用，标准模板的隐式 `MainFlutterWindow` 会直接崩溃。
>    所以主窗口也必须由 Dart 创建，入口用 `runWidget(ViewCollection)`，
>    不能沿用 `runApp` + 隐式 view。早期草稿「主窗口保留 runApp、
>    聊天窗用 ViewAnchor 旁挂」的方案在真机上不可行。

---

## 1. 现状（改造前）

单 OS 窗口里自绘整个桌面（壁纸、窗口栈、z-order、标题栏拖拽、最小化/任务栏）。
窗口不能移出画布、不能并排到别的屏幕、不能被 OS 窗口管理接管。

## 2. 生态现状（2026-11 实测查证）

| 路线 | 状态 | macOS | Windows | Web | 备注 |
|---|---|---|---|---|---|
| **C. 官方 Desktop Windowing API** | **experimental，仅 master** | ✅ | ✅ | ❌ | 3.50.0-1.0.pre；`--enable-windowing`；单引擎多窗口 |
| Flutter 3.47.9 stable | stable，窗口 API 被渠道门控禁用 | ❌ | ❌ | ❌ | `windowingFeature.stable.available=false`，开关/env 均无法绕过 |
| `desktop_multi_window` 0.3.1 | 成熟社区方案（多引擎） | ✅ | ✅ | ❌ | 0.x 版本、引入第三方依赖、需跨 isolate 协议 |
| 手写 macOS 多引擎 | 可行（多引擎） | ✅ | 需另写 C++ | ❌ | 零依赖但只覆盖 macOS |
| Web 多窗口 | 可行 | — | — | ✅ | `window.open` + URL fragment + BroadcastChannel |

渠道门控：`packages/flutter_tools/lib/src/features.dart` 的 `windowingFeature`
仅 `master: available:true`；框架侧 `isWindowingEnabled` 来自编译期
`FLUTTER_ENABLED_FEATURE_FLAGS=windowing` dart define。

## 3. 真实 API 模型

```
一个 OS 窗口 = 一个 FlutterView（同一个 Engine、同一个 isolate）
WindowController(...)  → 立刻创建原生 NSWindow / HWND / GtkWindow
Window(controller:, child:) → View(view: controller.rootView, child: child)
ViewCollection(views: [...]) → runWidget 的根
```

- `WindowController` 可用成员：`title` / `isActivated` / `isMaximized` /
  `isMinimized` / `isFullscreen` / `contentSize` / `setSize` /
  `setConstraints` / `setTitle` / `activate` / `setMaximized` /
  `setMinimized` / `setFullscreen` / `destroy` / `isDestroyed`。
- **没有 `setPosition`**：新建窗口默认叠在同一坐标。
- 生命周期：`WindowControllerDelegate.onWindowCloseRequested()` 默认调用
  `destroy()`；原生窗口关闭后 `onWindowDestroyed()` 触发，在此摘除
  `Window` widget。
- macOS 常规窗口由引擎用
  `NSWindowStyleMaskTitled | Closable | Miniaturizable | Resizable` 创建，
  **无 frameless 选项**。第二期通过 Runner 原生通道改造窗口外观解决（§9）。

## 4. 实际改造设计（首期：聊天窗多开）

1. **入口分流**（`lib/main.dart`）
   - macOS + `isWindowingEnabled` → `runWidget(QQConceptApp)`，根是
     `QNativeWindows.rootView(...)` 产出的 `ViewCollection`；
   - web / 其他平台 → `runApp(QQConceptApp)`，保持单画布，零回归。
2. **主窗口**：`QNativeWindows.tryCreate()` 在 `main()` 里、任何 view
   controller 注册之前创建 `WindowController(1440×900, min 1100×720)`，
   内容仍是原来的 `QDesktop`（壁纸 + 顶栏 + 任务栏 + 主面板等）。
3. **聊天子窗**：`QAppState.chatWindowOpener` 钩子把「打开聊天」从画布窗口
   栈改接到 `QNativeWindows.openChat(friend)`；创建
   `WindowController(490×435, min 490×435, title='与 X 聊天')`，`Window`
   里挂现有 `ChatScreen`（外面单独包一份 `MaterialApp`，因为新
   FlutterView 没有主窗口的 Directionality / Theme / MediaQuery）。
   同一好友重复双击 → `activate()`，不新开窗。
4. **状态共享**：`QAppState.thread(friend)` / `sendMessage` 原样可用，
   每个子窗用 `ListenableBuilder(listenable: state)` 刷新。
5. **生命周期**：退出登录 / 更换用户 → `closeAllChats()` 销毁所有子窗；
   关闭主窗口 → `ServicesBinding.exitApplication(AppExitType.required)`。
6. **任务栏**：`QAppState.windows` 不再登记聊天窗，自绘任务栏改显示
   「OS 窗口」标签，点击 `activate()` 把窗口置前；系统 Dock 负责最小化。
7. **预设迁移**：`#demo` / `#chat` 在构造 `QAppState` 时已建了画布内聊天窗，
   首帧后 `migrateChatsToNative()` 把它们转成原生窗口。
8. **级联**：官方 API 无 `setPosition`，`macos/Runner/AppDelegate.swift`
   通过 `qq_concept/windows` 方法通道接收 `NSWindow` 句柄（Dart 侧用
   `dynamic` 取 controller 的 `windowHandle`，避免在非 macOS 平台编译
   dart:ffi 平台实现），按 28px 步长 `setFrameOrigin` 错开。
9. **共享主题**：`lib/core/app_theme.dart` 抽出 `qqTheme()` 与
   `QNoSystemScrollbarBehavior`，主窗口 / 子窗口两份 `MaterialApp` 共用。

### macOS Runner（关键）

与官方 `examples/multiple_windows` 一致：

- `AppDelegate.swift`：手动 `FlutterEngine(name: "project", project: nil)`
  + `run(withEntrypoint: nil)`；不再由 nib 创建 `FlutterViewController`。
- `Base.lproj/MainMenu.xib`：去掉 `<window>`（`MainFlutterWindow`）与
  `mainFlutterWindow` outlet，只保留菜单栏。
- `MainFlutterWindow.swift`：留空壳兼容 Xcode 工程引用，不再创建
  `FlutterViewController`。
- 旧 nib 备份：`docs/backup/MainMenu.xib.pre-windowing.bak`。

### 文件清单

| 文件 | 作用 |
|---|---|
| `lib/main.dart` | 入口分流、URL 预设、根 `ViewCollection` |
| `lib/frontend/native_windows.dart` | 主窗口 + 聊天子窗注册表 / 生命周期 / 级联 |
| `lib/core/app_state.dart` | `chatWindowOpener` 钩子、预设迁移、登出清理 |
| `lib/core/app_theme.dart` | 共享 Theme / 滚动条行为 |
| `lib/frontend/desktop.dart` | 顶栏「独立窗口 · N」、任务栏 OS 窗口标签 |
| `macos/Runner/AppDelegate.swift` | 引擎启动 + `qq_concept/windows` 级联通道 |
| `macos/Runner/Base.lproj/MainMenu.xib` | 无初始窗口的菜单栏 |
| `test/widget_test.dart` | 单画布入口冒烟测试 |

## 5. 代价与风险

1. **experimental / master**：API 可能在 patch 版本间 breaking；IDE 与 CI
   需固定同一 SDK。`package:flutter/material.dart` 在 3.50 已标 deprecated，
   `analysis_options.yaml` 统一忽略。
2. **macOS 工程强依赖窗口化**：Runner 已改为无隐式 view，若切回 stable /
   关闭 flag，`runApp` 会因拿不到 `implicitView` 而报错。恢复方式见备份 nib
   与 README。
3. **系统标题栏**：官方 API 无 frameless 选项。第二期已在 Runner 侧隐藏
   NSTitlebarView 与红黄绿按钮解决；代价是仍需保留 `.titled` styleMask
   （否则登录框收不到键盘），并自行实现标题栏拖拽（见 §9）。
4. **平台覆盖**：仅 macOS 完成 Runner 适配与真机验证；Windows / Linux
   Runner 需同样改造，`QNativeWindows.isSupported` 目前只放行 macOS。
5. **Web 不适用**：保持单画布；`kIsWeb` 分流，所有 URL 预设与九屏画廊不受影响。
6. **Hot restart**：实验性 API 下旧 isolate 持有的原生窗口可能不会自动销毁；
   完整重新开始用 `flutter run` 重启进程。
7. 运行方式：macOS 26 从非 GUI 终端启动沙箱调试版会 SIGTRAP；已关闭
   Debug/Profile 的 App Sandbox，并提供 `run_macos.sh`（NO_PROXY + 固定
   VM Service 端口）。

## 6. 环境准备阶段验证

- `flutter analyze` → No issues found；
- `flutter build web --release` / `flutter build macos --debug` → 成功；
- `./run_macos.sh` → app 启动、Dart VM Service 就绪、Hot reload 可用；
- 排障确认：`flutter run -d macos` 原先报
  `Error waiting for a debug connection: The log reader stopped unexpectedly`，
  根因是 App Sandbox 初始化崩溃（`_libsecinit_appsandbox` / SIGTRAP）叠加
  本机代理拦截 VM Service WebSocket（502），**不是应用代码错误**。

## 7. 实现阶段验证（2026-11-11 真机）

- 第一次试跑按草稿方案（`runApp` + `ViewAnchor` 旁挂）→ 崩溃：
  `NSInternalInconsistencyException: Multiview can only be enabled before
  adding any view controllers.`（栈：`-[FlutterEngine enableMultiView]` ←
  `InternalFlutter_WindowController_CreateRegularWindow`）。由此定位到
  Runner 隐式 view controller，改为 `runWidget` + 无窗口 nib。
- 改造后 `./run_macos.sh --no-pub --ci` 启动日志：
  ```
  [QQ] 窗口化模式已启用：主桌面窗口已创建
  [QQ] 原生独立聊天窗口已创建：云帆（共 1 个）
  ```
  无 exception / 无崩溃。
- 多开验证：
  `./run_macos.sh --dart-define=QQ_INITIAL_CHATS=阿澈,苏禾,林岚`
  日志依次创建云帆 / 阿澈 / 苏禾 / 林岚共 4 个；
  `CGWindowListCopyWindowInfo` 实测同一 PID 下 5 个 OS 窗口：
  `1297×782 @140,78`（主桌面）+
  `442×421 @165,332`、`@190,357`、`@216,383`、`@241,408`（4 个聊天窗，
  约 28px 级联；CGWindowList 坐标为本机缩放后的点）。
- `flutter analyze` → No issues found；
  `NO_PROXY=127.0.0.1,localhost flutter test` → All tests passed；
  `flutter build web --release` / `flutter build macos --debug` → 通过。
- Web 单画布回归：`verify/native_web_smoke.js` 无头加载 + 展开分组 + tab 切换，
  console/pageerror = NONE，深色桌面 / 主面板 / 聊天窗 / 关于窗 / 顶栏 /
  任务栏完整渲染，顶栏没有「独立窗口」标识（正确走 web 分支）。

## 8. 后续可扩展

- Windows / Linux Runner 适配。
- 用 `WindowController.satellite` / `popup` 承载主菜单浮层、好友资料卡等瞬时窗口。
- floating 层级按应用激活状态降层，避免切换其它应用时内容窗口一直置顶。

## 9. 第二期：全部窗口独立 + 无原生标题栏（2026-11-11）

### 需求

去掉原生 macOS 标题栏；登录窗、主面板也从桌面画布提升为独立 OS 窗口。

### 架构改动

1. **单一真值源**：删除 `QAppState.chatWindowOpener` / `closeAllChatWindows` /
   `migrateChatsToNative()` 这些首期特例。`open()` 只登记 `QWindow` 到 `windows`；
   `QNativeWindows` 注册 `state.addListener(_sync)`，diff 出 OS 窗口的创建 /
   销毁 / `setMinimized` / `activate`。登录 → 主面板、退出登录因此自动生效。
2. **共享接线**：新增 `lib/frontend/window_content.dart`，把 QDesktop 的
   `_screen()` 抽成 `buildQWindowContent(state, window, onWindowButton)`；
   画布与原生窗口各自只负责「窗口按钮落到哪里」（z-order vs NSWindow 状态）。
3. **窗口清单**：`rootView` = `ViewCollection([Window(console), ...内容窗口])`。
   控制台只保留壁纸 / 顶栏 / 任务栏；6 类窗口各占一个 NSWindow。
   每窗独立跑一份 `MaterialApp` + `Material(type: transparency)`：新 FlutterView
   缺 Theme / Directionality，且不能套 Scaffold（登录 / 主面板的圆角需透出壁纸）。
4. **窗口状态**：`minimized` → `setMinimized(true)`；新建 / 置顶 → `activate()`；
   用户在 OS 层关窗 → delegate 回调 `state.close(id)` 同步回注册表。
   只在顶层窗口 id 集合变化时 `notifyListeners()`，避免逐键输入打断输入框焦点。
5. **原生无边框**（`macos/Runner/AppDelegate.swift` 的 `qq_concept/windows`）：
   - `setup(handle, w, h, x, y, floating, resize)`：
     `styleMask |= fullSizeContentView`、`titlebarAppearsTransparent`、
     `titleVisibility = .hidden`、`isOpaque = false` + clearColor、隐藏三个
     standardWindowButton 及其 superview（NSTitlebarView）；`setContentSize(w,h)`
     让 1x 像素稿精确铺满；内容窗口 `level = .floating` 浮在控制台之上。
     **保留 `.titled`**：borderless 窗口默认 cannot become key，登录框会收不到键盘。
   - `move(handle, dx, dy)`：自绘标题栏 `onPanUpdate` → `setFrameOrigin`
     （Flutter y 向下、AppKit y 向上，dy 取负）。
   - 默认坐标由 `_initialPos()` 按 QDesktop 的 `_defaultPos` 换算，聊天窗 28px 级联。
6. **生命周期**：`QQConceptApp.dispose()` 不再 dispose state / native
   （所有权在 `main()`），否则热重载会误关全部原生窗口。

### 真机排障记录

- `No Material widget found`：原生窗口没套 Scaffold，TextField 缺 Material 祖先
  → 补 `Material(type: MaterialType.transparency)`。
- `NSInternalInconsistencyException: window behavior cannot be both
  CanJoinAllSpaces and MoveToActiveSpace`：两个 collectionBehavior 互斥
  → 只保留 `.canJoinAllSpaces`。
- `Incorrect use of ParentDataWidget`：密码框传给 `PillField` 的 child 自带
  `Positioned.fill`，而 `PillField` 内部又包一层；原生窗口侧也多套了一层
  `Positioned.fill` → 两处都去掉（顺带修复了画布模式的既有隐患）。
- 过程中出现「窗口重复创建 / preset 跳变」：`flutter run` 在运行中检测到
  Dart 源码改动会自动热重载；代码定稿后干净启动不再出现。

### 验证（2026-11-11 真机）

- `QQ_PRESET=login`：控制台 `1440×868` + 登录窗 **`372×282`**，
  原生回传 `visible:true / key:true / level:3 / styleMask=32783`
  （= titled | closable | miniaturizable | resizable | fullSizeContentView）。
- `QQ_PRESET=login QQ_AUTO_LOGIN=true`：登录窗销毁，主面板 **`272×645`**
  独立窗创建并成为 key，验证 diff 的删除 + 新增链路。
- 默认 demo + `QQ_INITIAL_CHATS=阿澈,苏禾,林岚`：同一 PID 下
  **1 控制台 + 8 内容窗口**，尺寸 `272×645` / `490×435`×4 / `357×160` /
  `959×597` / `268×645` 全部精确等于设计稿——首期聊天窗是 `490×467`，
  多出的 32px 正是原生标题栏，现已消失；好友管理 / 设置 minimized
  对应 `onscreen=absent`；聊天窗 `@201,323 → @229,351 → @257,379 → @285,407`。
- `flutter analyze` / `flutter build web --release` / `flutter build macos --debug`
  均通过；Web 单画布回归无 console / pageerror。
- macOS 合成点击需「辅助功能」权限（本机 `AXIsProcessTrusted=false`），
  窗口按钮命中测试未做自动化回归；已由 styleMask / key 状态、以及画布模式
  的同类交互复验覆盖。

## 10. 第三期：拖拽闪烁 + 异形窗口黑底（2026-11-12）

### 症状

1. 拖动自绘标题栏时窗口不停闪烁，而且跟不上鼠标（越拖越偏离光标）。
2. 主面板的「动感相框」、登录窗太阳/云/叶等异形轮廓之外的区域是**纯黑**，
   不是透出后面的控制台壁纸。

### 根因

**拖拽**：原实现是 `onPanUpdate` → 每帧把 `details.delta` 过 MethodChannel
→ 原生 `setFrameOrigin(origin + delta)`。两个问题叠加：

- Flutter 的 pointer 坐标是**相对窗口**的。窗口跟着鼠标移动后，指针的窗口内
  坐标几乎不变，下一帧 delta 就接近 0 —— 形成负反馈，越拖越黏，抖动明显。
- 每帧一次通道往返（毫秒级）必然落后于 60/120Hz 的鼠标事件。

**黑底**：引擎的 `FlutterView` 在 `initWithMTLDevice:` 里执行
`[self setBackgroundColor:[NSColor blackColor]]`（首帧前的占位色，内部即
`self.layer.backgroundColor = black`）。窗口本身虽然设了 `isOpaque = false`，
但 contentView 图层的黑色背景仍会填满所有 alpha=0 的像素 → 异形轮廓外显示黑色。

### 改法

1. **拖拽交还 Window Server**：Dart 侧不再计算位移，只判定「这是拖动不是点击」。
   `_DragHandle` 用 `Listener`（不是 `GestureDetector`：pan 手势要先赢竞技场，
   `kPanSlop` 约 36px，标题栏才 30~60px 高，那点位移就足以让窗口明显滞后），
   按下后位移 > 3px 才发 `drag` 请求；原生执行
   `performWindowDragWithEvent:`，由 Window Server 接管整段拖动。
   - `NSApp.currentEvent` 此时往往已经是 mouseDragged，而 API 文档要求传
     原始 mouseDown → 用 `addLocalMonitorForEvents(.leftMouseDown)` 缓存
     `lastMouseDown`（只记录、照常放行事件，不影响点击）。
   - 该方法在部分 SDK 头文件里被裁剪（Swift 侧调用不到），改用
     `responds(to:) + perform(_:with:)` 动态发送。
2. **清掉 FlutterView 的黑色底**：`makeContentTransparent()` 递归遍历
   contentView → 每个 `NSView` 的 `layer.backgroundColor = clear`，
   每个 `CALayer` 的 `isOpaque = false`，并对实现 `setBackgroundColor:` 的
   视图（`FlutterView`）用 `perform` 传 `NSColor.clear`。首帧前视图可能还没
   挂好，再 `DispatchQueue.main.async` 补一次。

### 验证

- 原生 `setup` 回传自检字段：
  `content=FlutterViewWrapper / bgAlpha=0.0 / opaque=false /
  layers=FlutterViewWrapper:0.00[FlutterView:0.00,_FlutterDisplayLinkView:0.00]`，
  `canDrag=true`。
- `screencapture -l <windowID>` 按窗口取图（PNG 保留 alpha），
  主面板 544×1290、好友管理 1918×1194 的四角均为 `rgba(0,0,0,0)`
  —— 圆角与相框之外确实是透明像素，不再是黑色。
- 真机拖动主面板，窗口坐标 `@1098,232 → @390,416`，日志两次
  `[QQ] 标题栏拖动：panel`，窗口跟随移动、无抖动。
- `flutter analyze` / `flutter test` / `flutter build web --release` /
  `flutter build macos --debug` 全部通过。

## 11. 第四期：去掉残留的 1px 白边与窗口阴影灰雾（2026-11-12）

### 症状

第三期清掉 FlutterView 的黑色底之后，异形窗口能透出后面的壁纸了，但仍然：

1. 窗口轮廓上有一条奇怪的白色细线；
2. 透明区域不是完全透明，蒙着一层浅灰（对比外部背景约暗 4%）。

### 根因

两者都不是 Flutter 画的 —— 窗口抓图（`screencapture -l`）里透明像素的 alpha 是 0：

- **白线**：`.titled` 窗口即使 `titlebarAppearsTransparent = true` + 隐藏
  `NSTitlebarView`，`NSThemeFrame` 仍会沿窗口矩形画一圈 1px 边框；
- **灰雾**：`hasShadow = true` 时系统阴影是画在**窗口之后**的，窗口透明像素会
  把它透出来。登录窗的透明装饰带只有 42pt 高，正好整片落在面板边缘的阴影
  扩散范围里，于是看起来像蒙了一层灰。

### 改法

内容窗口改成 **borderless**（`styleMask = []`）+ `hasShadow = false`：
AppKit 不再绘制任何 frame，也就没有边框线，也没有矩形阴影。

两个必须注意的点：

1. **borderless 默认 `canBecomeKey == false`**，登录框会完全收不到键盘。
   在运行时用 `object_setClass(window, QQBorderlessWindow.self)` 换成重写了
   `canBecomeKey` / `canBecomeMain` 的子类；换类前先比 `class_getInstanceSize`，
   布局不一致就不换并退回 titled（宁可留边框也不冒内存布局风险）。
2. **顺序不能反**：必须先 `styleMask = []` 再换类。反过来先在 KVO 的
   `NSKVONotifying_NSWindow` 上换成自定义类，`NSTitlebarView` 摘除时注销观察者
   会抛 `Cannot remove an observer ... for the key path "_titlebarBackdropGroupName"`。
3. **不能在首帧前改 `styleMask`**：引擎的 surface 此刻正在按窗口尺寸建立，
   改 styleMask 会导致 texture 与视图尺寸不一致，直接崩在
   `Impeller ... The texture and its descriptor disagree about its size`。
   因此 `setup` 里先按 titled 起窗，`asyncAfter(0.3s)` 再做 borderless 转换。

### 验证

- `info` 通道自检：`{class: QQBorderlessWindow, styleMask: 0, borderless: true,
  shadow: false, canKey: true}`；
- 拖动仍然有效（borderless 不影响 `performWindowDragWithEvent:`）：
  面板 `@1098,232 → @789,127`；
- 整屏截图检查（先把应用 activate 到前台，否则窗口在另一个 Space，
  `CGWindowList` 会显示 `onscreen=absent`）：主面板左上角木框、登录窗
  云/叶区域四周直接是控制台壁纸，无白线、无灰雾；
- `flutter analyze` / `flutter test` / `build web` / `build macos` 通过。

## 12. 第五期：透明区残留的「半透明灰雾」（2026-11-12）

### 症状

去掉白边和窗口阴影后，异形窗口的透明区域仍然蒙着一层半透明灰色 ——
主面板「动感相框」周围、登录窗太阳/云上方那条装饰带最明显。

### 根因

不是窗口，也不是引擎 —— 是 **Dart 侧画在卡片上的 `boxShadow`**。

- 画布模式下窗口是桌面画布里的卡片，`QShadow.win`（黑 60% / blur 40 /
  offset 0,10）可以溢出到壁纸上，看起来像真实投影；
- 原生窗口的边界**正好等于画布尺寸**，阴影无处可去，只能在窗口内部糊成
  一层渐变灰雾：面板顶部 32px 装饰带里 alpha 从 0.03 一路涨到 0.15，
  登录窗 42px 装饰带里是 0.01→0.03。窗口越大、越靠近卡片，雾越浓。

### 改法

新增 `lib/core/window_chrome.dart`：

```dart
bool qNativeWindowChrome = false;
List<BoxShadow> qOuterShadow(List<BoxShadow> canvas) =>
    qNativeWindowChrome ? const <BoxShadow>[] : canvas;
```

`QNativeWindows.tryCreate()` 成功后置位，`dispose()` 复位；五处窗口卡片的
`boxShadow: QShadow.xxx` 改成 `boxShadow: qOuterShadow(QShadow.xxx)`
（主面板 / 聊天 / 登录 / 好友管理 / DlgFrame）。画布模式与设计稿画廊不受影响。

### 验证

按窗口截图对比顶部装饰带 alpha（`screencapture -l` 保留 alpha）：

| 窗口 | 修复前 | 修复后 |
|---|---|---|
| 主面板（x=400, y=8/20/36/52） | 0.03 / 0.05 / 0.09 / 0.15 | 0.00 / 0.00 / 0.00 / 0.00 |
| 登录窗（x=560, y=6/20/40） | 0.00 / 0.01 / 0.03 | 0.00 / 0.00 / 0.00 |

`flutter analyze` / `flutter test` / `build web` / `build macos` 通过。

### 取舍

原生窗口模式下完全不再有「窗口外投影」，窗口之间的层次只靠系统窗口层级。
如果之后想要真实的投影，正解是用系统窗口阴影（`hasShadow`）而不是在
Dart 里画 —— 系统阴影画在窗口**之后**，不会污染窗口内部的透明像素。

## 13. 第六期：去掉「桌面控制台」，按产品流程重排窗口（2026-11-14）

### 变更

原来的 1 个「桌面控制台」（壁纸 + 顶栏快捷启动 + 任务栏）+ N 个内容窗口，
是开发期的脚手架。`docs/requirements.md` 定义的目标产品是**一台正常的 IM**：
启动只有登录窗，登录后是主面板，其余窗口按用户操作打开。据此：

1. `QNativeWindows` 不再创建控制台控制器，`rootView()` 只返回内容窗口；
   `console` / `_setupConsole` / `onConsoleDestroyed` 全部删除。
2. 启动预设：**桌面版默认 `login`**（未登录），web 画布仍按 URL 预设。
3. 入口拆分：`main()` 在窗口化时走 `runWidget(NativeWindowsRoot(...))`，
   画布模式才用 `QQConceptApp`（`QDesktop` 不再参与原生模式）。
4. 窗口层级从 `.floating` 降为 `.normal`：不再有「浮在控制台之上」的需求，
   切换其它应用时也不会盖住别人的窗口。
5. 摆位改为锚点：Dart 传 `anchor`（center / top-right / center-right /
   cascade）+ `index`，原生按 `NSScreen.visibleFrame` 换算，屏幕分辨率变了
   也不用改常量。
6. 关闭最后一扇窗口 → 退出应用（没有托盘）：`_sync` 检测到注册表空即
   `exitApplication`，并且**不销毁**残留窗口，避免用已销毁的 controller 重建。

### 由此发现并修掉的两个坑

- **`object_setClass` 会双重释放**：为了让 borderless 窗口能成为 key，
  之前把窗口类换成自定义子类。结果每次关闭窗口都打
  `-[NSAutoreleasePool drain]: This pool has already been drained`。
  用 `QQ_NO_SWAP=1` 做对照（只改 styleMask、不换类）确认告警消失
  → 根因就是换类让 dealloc 走了另一套布局。
  改为 `method_setImplementation` 替换 `NSWindow` 的
  `canBecomeKey/canBecomeKeyWindow`：承载 `FlutterViewController` 的窗口
  返回 true，其余按 styleMask 判断，实例类不再变动。
- **AppKit 问的是 `canBecomeKeyWindow`**：只补 `canBecomeKey` 时，
  换类后 `canBecomeKey` 仍返回 false（日志实测），补上旧名 `canBecomeKeyWindow`
  才生效。

### 验证

- 启动日志：`窗口化模式已启用：1 个窗口（无控制台）`；
- 登录窗居中 `x=570`（1512 宽屏）、主面板 `x=1216`（右 24pt）、
  好友管理居中、聊天窗 `x=514` 并逐窗 +28pt；
- `info` → `{borderless: true, class: NSWindow, styleMask: 0, canKey: true, key: true}`，
  关闭窗口时无 `NSAutoreleasePool` 告警；
- 桌面截图只剩应用窗口，没有壁纸/顶栏/任务栏；
- `flutter analyze` / `flutter test` / `build web` / `build macos` 通过。

## 14. 第七期：窗口打开时的位置跳变 + 出现动画（2026-11-14）

### 现象与根因

用户反馈「打开窗口时从左侧闪一下到目标位置」，登录窗与主面板都有。查引擎源码
`engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterWindowController.mm`
的 `createRegularWindow`（L682）：

```
[[NSWindow alloc] init]                       ← frame 在屏幕左侧默认坐标
window.styleMask = ...
window.contentViewController = controller    ← 唯一「窗口还没显示」的早时机
[window flutterSetContentSize:...]
owner.onFirstFrame = ^{
  [window setIsVisible:YES];                ← 这一刻就被 Window Server 合成
  [window makeKeyAndOrderFront:nil];
}
```

Dart 侧 `WindowController(...)` 构造后立刻发的 `setup` 是 MethodChannel 异步消息，
摆位晚于首帧，于是「可见的默认位置 → 摆位后的目标位置」之间至少有一帧被看到。
`WindowController` 没有初始 frame / visible 参数（`WindowPositioner` 只服务于
tooltip / popup 这类 satellite 窗口），只能在原生层管显示时序。

**第一版为什么没修好（关键教训）**：靠替换 `orderFront:` +
`NSWindowDidBecomeVisibleNotification` 在「窗口出现之后」压 alpha。引擎首帧是
`setIsVisible:YES` → `makeKeyAndOrderFront:`，两者都不走 `orderFront:`；通知又是
异步投递到主队列，block 执行时那一帧已经被画出来了。20ms 探针只看到「左侧
alpha=0」（那是 `setup` 到达后压的），漏掉了中间那一帧可见窗口，因此误判为已修复。
正确的判据是 **`setup` 到达那一刻 alpha 已经是 0**，而不只是「最终位置正确」。

### 方案：创建期就透明 → 全部就绪 → 淡入

1. `installWindowShowHook()` 早于 `FlutterEngine.run` 安装，四层保险：
   - ① **关键**：替换 `NSWindow.setContentViewController:`，引擎给窗口挂
     `FlutterViewController` 时（窗口尚未显示）立刻 `alphaValue = 0`、登记
     `pendingReveal`，并把默认 frame 从屏幕左侧挪到屏幕中央作为位置兜底；
   - ② 替换 `setIsVisible:` 与 `orderFront:`，在调用原 IMP **之前**压 alpha，
     同步拦住首帧；
   - ③ `NSWindowDidBecomeVisibleNotification` 覆盖 `activate()` 等其它路径；
   - ④ `NSWindowWillCloseNotification` 清理身份记录（NSWindow 地址会复用）。
   - **绝不替换 `makeKeyAndOrderFront:`**：实测换掉后所有窗口
     `isKeyWindow=false`（登录框收不到键盘）。
2. `setup` 开头记录 `preSetupAlpha`（诊断值，应为 0）并再压一次 alpha=0，随后
   同步完成 `setContentSize`、按锚点 `place`、透明化，把最终 frame 存进
   `targetFrames`。
3. 0.3s 后（等首帧 / Impeller surface 稳定）转 borderless；`styleMask` 变化
   可能让 AppKit 微调原点，因此**再钉一次** `setFrame(target)`。所有可能改位置的
   动作都发生在 alpha=0 的「幕布」后面。
4. `reveal()` 按 easeOut 曲线把 alpha 从 0 逐帧写到 1（0.26s / 13 帧）；同时
   `setup` 的 result 才返回给 Dart，Dart 侧 `_WindowReveal` 播放 340ms 的内容
   淡入 + 上浮 14px + 缩放 0.97→1，两层动画几乎同帧起步。
5. 兜底：窗口出现 2.5s 后仍未收到 `setup` 就强制 alpha=1（留足启动耗时余量，
   避免兜底先于 setup 触发把窗口在旧坐标上亮出来）；`setup` 通道失败 / 句柄
   拿不到时 Dart 侧也直接放行动画初态，绝不留下隐形窗口。

### 实测踩坑

- **异步通知 / `orderFront:` 拦不住首帧**：见「第一版为什么没修好」。显示时序
  必须在创建期 / `setIsVisible:` 同步拦，通知只能当兜底。探针采样率也要够：
  20ms 会整帧漏掉，改 4ms 才能对「肉眼可见、探针看不见」的现象下结论。
- **`window.animator().alphaValue = 1` 不生效**：放在
  `NSAnimationContext.runAnimationGroup` 里，窗口会永久停在 alpha=0
  （探针全程 0.00，界面完全看不见）。改成 `DispatchQueue.main.asyncAfter`
  逐帧显式写 `alphaValue`，曲线用 `1-(1-t)^3`。
- **不要把 `makeKeyAndOrderFront:` 也换掉**：替换它之后所有窗口
  `isKeyWindow=false`（登录框收不到键盘）。AppKit 的聚焦路径必须原样保留，
  拦在更早的 `setIsVisible:` 即可；首帧 alpha=0 时 AppKit 本来就不会把窗口
  设为 key，所以淡入结束后补一次
  `NSApp.activate(ignoringOtherApps:) + makeKeyAndOrderFront(nil)`。
  本次真机 `appActive:true` 时每扇窗口 `key:true`，证明补聚焦有效；早期
  `key:false` 是后台终端启动时 `NSApp.isActive=false` 的环境限制。
- **`setIsVisible:` 的 ABI**：ObjC BOOL 用 `Int8` 接收再逐位透传给原 IMP，
  避免 Swift `Bool` 与 AppKit overlay 的类型编码差异把 YES 变成 NO
  （那会让窗口永远不显示）。
- **SDK Swift overlay 缺符号**：`NSWindow.didBecomeVisibleNotification` /
  `willCloseNotification` 在本 SDK 编译不过，直接用稳定的 ObjC 通知名字符串
  `NSWindowDidBecomeVisibleNotification` / `NSWindowWillCloseNotification`
  （与之前 `performWindowDragWithEvent:` 头文件裁剪同类问题）。

### 验证（`CGWindowListCopyWindowInfo` 高频探针，4ms 一采 / 7308 次 / 45s）

一次启动覆盖登录窗 → 主面板 → 3 个聊天窗共 5 扇窗口，每窗 `setup` 自检均为
`hiddenAtCreation:true, preSetupAlpha:0.0, key:true, revealed:true`，且
`borderless:true, styleMask:0, shadow:false, bgAlpha:0, opaque:false`。

```
t=10.013s  登录 (570,342) 372x282              alpha=0.00  ← 首次被观测即在目标坐标
t=10.296~10.505s  alpha 0.21 → 1.00            坐标全程不变
t=18.732s  主面板 (755,33) 272x677             alpha=0.00  ← 中心兜底位，不可见
t=18.784s  主面板 (1216,57) 272x645            alpha=0.00  ← 摆位/改尺寸，仍不可见
t=19.080~19.285s  alpha 0.21 → 1.00            坐标全程不变
（3 个聊天窗同型，级联 514 / 542 / 570）
LEFT_VISIBLE_FLASH_FRAMES = 0
```

判据 `LEFT_VISIBLE_FLASH_FRAMES` 统计「x<200 且 alpha>0.05」的采样帧，为 0
即表示用户不可能看到左侧默认坐标。`[QQ] 窗口出现动画：login / panel / chat:*`
日志确认内容动画逐窗播放。`flutter analyze` / `flutter test` /
`build macos --debug` 通过，此前修掉的白线 / 黑底 / 灰雾无回归。屏幕录制权限
仍限制像素级截图，视觉复核以 CGWindow 层的坐标 / alpha 数据为准。

### 取舍

只动 alpha 不动 frame：给窗口做位移动画会让 Flutter surface 跟着 resize，
异形透明窗口上会出现拉伸，甚至触发 Impeller 的 texture 尺寸不一致崩溃。
「窗口淡入 + 内容上浮」既能表达出现感，又完全不碰窗口几何。

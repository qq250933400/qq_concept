import Cocoa
import FlutterMacOS
import ObjectiveC
import UserNotifications

private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner])
    } else {
      completionHandler([.alert])
    }
  }
}

/// 窗口化（Desktop Windowing）启动方式：
/// 所有 NSWindow 都由 Dart 侧的 WindowController 创建，不能在 nib 里
/// 预先注册 FlutterViewController —— 否则引擎的 enableMultiView 会抛
/// "Multiview can only be enabled before adding any view controllers."
/// 这里与 Flutter 官方 examples/multiple_windows 保持一致：手动创建并
/// 运行引擎，MainMenu.xib 只保留菜单栏、不含窗口。
///
/// 官方 Windowing API 没有 frameless / setPosition，所以额外提供
/// `qq_concept/windows` 方法通道：
///   - setup：去掉原生标题栏、让内容区域透明、按设计稿坐标摆位；
///   - drag ：自绘标题栏拖动时把事件交给 AppKit 的窗口拖动循环。
@main
class AppDelegate: FlutterAppDelegate {
  var engine: FlutterEngine?
  private var windowChannel: FlutterMethodChannel?
  private let notificationDelegate = NotificationDelegate()
  private var shakingWindows = Set<ObjectIdentifier>()

  /// 最近一次 leftMouseDown。performWindowDragWithEvent: 要求传「原始
  /// mouseDown 事件」，而 Dart 侧的拖动判定要等位移超过阈值才触发，
  /// 等通道回调到达时 NSApp.currentEvent 往往已经是 mouseDragged 了。
  private var lastMouseDown: NSEvent?
  private var mouseDownMonitor: Any?

  // ------------------------------------------------------------ 窗口出现时序
  // 引擎 createRegularWindow 的顺序（FlutterWindowController.mm:682）：
  //   [[NSWindow alloc] init]                ← frame 停在屏幕左侧默认坐标
  //   window.styleMask = ...
  //   window.contentViewController = ...    ← 此刻窗口还没显示（唯一可靠的早时机）
  //   flutterSetContentSize: ...
  //   owner.onFirstFrame = ^{
  //     [window setIsVisible:YES];          ← 这一刻就被 Window Server 合成显示
  //     [window makeKeyAndOrderFront:nil];
  //   }
  // Dart 的 `setup` 摆位是异步消息，晚于首帧；所以「靠通知 / setup 到达后再
  // 压 alpha」都来不及 —— 那一帧窗口已经以 alpha=1 出现在左侧默认坐标了。
  //
  // 修复必须发生在**窗口显示之前**：在 `setContentViewController:` 这个创建期
  // 钩子里就把 alpha 压成 0，窗口从出生起就是透明的。显示期再补一层同步前置
  // 拦截（setIsVisible: / orderFront:），绝不依赖异步通知当主力。之后摆位、
  // 透明化、去边框都在不可见阶段完成，最后统一淡入。
  private var pendingReveal = Set<ObjectIdentifier>()
  private var revealedWindows = Set<ObjectIdentifier>()
  /// 是否在创建期就压住了 alpha。诊断用：为 true 才证明首帧不可能被看到。
  private var hiddenAtCreation = Set<ObjectIdentifier>()
  /// setup 到达那一刻的 alpha。诊断用：应为 0；若为 1 说明拦截失败。
  private var preSetupAlpha: [ObjectIdentifier: CGFloat] = [:]
  private var targetFrames: [ObjectIdentifier: NSRect] = [:]
  private var revealFallbacks: [ObjectIdentifier: DispatchWorkItem] = [:]
  private static var showHookInstalled = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = notificationDelegate
    engine = FlutterEngine(name: "project", project: nil)
    // 必须早于引擎创建任何 NSWindow，否则拦不住首帧那一次显示。
    installWindowShowHook()
    engine?.run(withEntrypoint: nil)

    // 只做记录，事件照常放行给 Flutter（不拦截点击）。
    mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
      [weak self] event in
      self?.lastMouseDown = event
      return event
    }

    guard let engine = engine else { return }
    let channel = FlutterMethodChannel(
      name: "qq_concept/windows",
      binaryMessenger: engine.binaryMessenger)
    windowChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleWindowCall(call, result: result)
    }
  }

  private func handleWindowCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "notify" {
      guard let args = call.arguments as? [String: Any],
            let title = args["title"] as? String,
            let body = args["body"] as? String else {
        result(FlutterError(code: "INVALID_NOTIFICATION", message: "通知内容无效", details: nil))
        return
      }
      if (args["sound"] as? Bool) == true {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
          sound.play()
        } else {
          NSSound.beep()
        }
      }
      if let address = args["handle"] as? NSNumber,
         let pointer = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: address.int64Value)),
         let window = NSApp.windows.first(where: { Unmanaged.passUnretained($0).toOpaque() == pointer }),
         window.isVisible, !window.isMiniaturized {
        shake(window)
        result(nil)
      } else {
        showNotification(title: title, body: body, result: result)
      }
      return
    }
    guard let args = call.arguments as? [String: Any],
          let address = args["handle"] as? NSNumber,
          let pointer = UnsafeRawPointer(
            bitPattern: UInt(truncatingIfNeeded: address.int64Value)) else {
      result(FlutterMethodNotImplemented)
      return
    }

    let window = Unmanaged<NSWindow>.fromOpaque(pointer).takeUnretainedValue()

    switch call.method {
    case "setup":
      // result 延迟到「摆位 + 去边框 + 淡入」全部就绪之后再回给 Dart：
      // Dart 收到它才播放内容出现动画，两层动画因此几乎同帧起步。
      setupFrameless(window: window, args: args) { [weak self] in
        result(self?.windowDiagnostics(window) ?? [:])
      }
    case "info":
      // 诊断：确认窗口外观是否已切到 borderless（无边框 / 无阴影 / 仍可输入）。
      result([
        "styleMask": Int(window.styleMask.rawValue),
        "borderless": !window.styleMask.contains(.titled),
        "shadow": window.hasShadow,
        "canKey": window.canBecomeKey,
        "key": window.isKeyWindow,
        "class": String(describing: type(of: window)),
        "alpha": window.alphaValue,
        "x": window.frame.origin.x,
        "y": window.frame.origin.y,
        "w": window.frame.width,
        "h": window.frame.height,
        // key 为 false 时先看这项：自动化启动的应用可能压根不是 active app。
        "appActive": NSApp.isActive,
      ])
    case "drag":
      // 交给 Window Server：它自己接管鼠标追踪，窗口逐帧跟随光标。
      // 千万不要在这里按 delta 手动 setFrameOrigin —— Flutter 的 pointer
      // 坐标是相对窗口的，窗口一动位移就被抵消，形成抖动 + 跟不上鼠标。
      // Swift 侧没有暴露 performWindowDragWithEvent:（SDK 头文件裁剪过），
      // 用动态消息发送调用。
      if let event = lastMouseDown ?? NSApp.currentEvent {
        let selector = NSSelectorFromString("performWindowDragWithEvent:")
        if window.responds(to: selector) {
          _ = window.perform(selector, with: event)
        }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func shake(_ window: NSWindow) {
    let id = ObjectIdentifier(window)
    guard window.isVisible, !window.isMiniaturized, !shakingWindows.contains(id) else { return }
    shakingWindows.insert(id)
    let origin = window.frame.origin
    let offsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
    for (index, offset) in offsets.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) { [weak self, weak window] in
        guard let self else { return }
        guard let window, window.isVisible, !window.isMiniaturized else {
          self.shakingWindows.remove(id)
          return
        }
        window.setFrameOrigin(NSPoint(x: origin.x + offset, y: origin.y))
        if index == offsets.count - 1 { self.shakingWindows.remove(id) }
      }
    }
  }

  private func showNotification(title: String, body: String, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert]) { granted, error in
      guard granted, error == nil else {
        DispatchQueue.main.async {
          result(FlutterError(code: "NOTIFICATION_DENIED",
                              message: "请在系统设置中允许 QQ 通知", details: error?.localizedDescription))
        }
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                       content: content, trigger: nil)) { error in
        DispatchQueue.main.async {
          if let error {
            result(FlutterError(code: "NOTIFICATION_FAILED",
                                message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }

  /// 把带系统标题栏的常规窗口改成「自绘标题栏 + 真透明」窗口，并管住
  /// 整个出现时序：**先隐藏 → 摆位 / 去边框 → 淡入**。
  ///
  /// 两种模式：
  /// - 内容窗口（`shadow:false`）：改成 **borderless**。`.titled` 窗口即使在
  ///   `titlebarAppearsTransparent` 下，NSThemeFrame 仍会画一圈 1px 亮边
  ///   （截图上就是那条「奇怪的白色线」）；而且窗口的矩形阴影会从透明的
  ///   像素里透出来，看起来像蒙了一层浅灰。borderless 不画边框，再关掉
  ///   `hasShadow` 就彻底干净。
  /// - 控制台窗口：保持 `.titled`（壁纸铺满，不需要异形），只去标题栏。
  private func setupFrameless(window: NSWindow,
                              args: [String: Any],
                              onReady: @escaping () -> Void) {
    let windowId = ObjectIdentifier(window)
    // 诊断：读到 1 说明创建期钩子没命中、那一帧确实被用户看到了；
    // 读到 0 才证明窗口从出生起就是透明的。
    preSetupAlpha[windowId] = window.alphaValue
    // 窗口可能已经被首帧显示出来了；无论如何先压回不可见，后面所有会改
    // frame 的操作都在这一层「幕布」后面完成。
    holdHiddenIfNeeded(window)
    window.alphaValue = 0
    let wantsShadow = (args["shadow"] as? NSNumber)?.boolValue ?? true

    window.isOpaque = false
    window.backgroundColor = .clear

    if wantsShadow {
      // 隐藏按钮前先拿到标题栏容器（NSTitlebarView）。
      let titlebar = window.standardWindowButton(.closeButton)?.superview
      window.styleMask = window.styleMask.union(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.hasShadow = true
      for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(type)?.isHidden = true
      }
      // NSTitlebarView 覆盖在 FlutterView 顶部，会吞掉自绘 – / ☐ / × 的点击。
      titlebar?.isHidden = true
    } else {
      // 先去标题栏、关阴影，但**不要在首帧前**改 styleMask：引擎的 surface
      // 尺寸在这一刻正在建立，改成 borderless 会让 texture 与视图尺寸对不上
      // （Impeller: "texture and its descriptor disagree about its size"）。
      let titlebar = window.standardWindowButton(.closeButton)?.superview
      window.styleMask = window.styleMask.union(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.hasShadow = false
      titlebar?.isHidden = true
    }

    let width = (args["width"] as? NSNumber)?.doubleValue ?? window.frame.width
    let height = (args["height"] as? NSNumber)?.doubleValue ?? window.frame.height
    if (args["resize"] as? NSNumber)?.boolValue == true {
      // contentSize == frame.size，1x 像素稿才不会偏移。
      window.setContentSize(NSSize(width: width, height: height))
    }

    if (args["floating"] as? NSNumber)?.boolValue == true {
      // 内容窗口浮在控制台（壁纸 + 顶栏 + 任务栏）之上；控制台保持 normal。
      window.level = .floating
      // canJoinAllSpaces 与 moveToActiveSpace 互斥，同时设置会抛
      // NSInternalInconsistencyException；只用前者即可跨 Space 可见。
      window.collectionBehavior = window.collectionBehavior.union(.canJoinAllSpaces)
    }

    if let anchor = args["anchor"] as? String {
      place(window: window, anchor: anchor,
            index: (args["index"] as? NSNumber)?.intValue ?? 0)
    } else if let dx = (args["x"] as? NSNumber)?.doubleValue,
              let dy = (args["y"] as? NSNumber)?.doubleValue {
      let screen = NSScreen.main?.visibleFrame
        ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
      let x = screen.origin.x + dx
      let y = screen.maxY - dy - window.frame.height
      window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    // styleMask 切成 borderless 时 AppKit 有机会微调窗口原点，先把设计稿
    // 坐标存下来，淡入前再钉一次，用户看到的位置就必然是最终位置。
    targetFrames[windowId] = window.frame

    makeContentTransparent(window)
    // FlutterView 可能晚一拍才挂到 contentView 上（首帧前），再补一次。
    DispatchQueue.main.async { [weak window] in
      guard let window else { return }
      self.makeContentTransparent(window)
    }

    // 等首帧 + surface 稳定后再改 styleMask（提前改会崩 Impeller）。
    // 这段等待窗口始终是 alpha=0，所以去边框、重钉 frame 都不会被看到。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak window] in
      guard let self else {
        onReady()
        return
      }
      if let window {
        if !wantsShadow {
          self.makeBorderlessKeyable(window)
          if let target = self.targetFrames[ObjectIdentifier(window)] {
            window.setFrame(target, display: false)
          }
        }
        self.reveal(window)
      }
      // Dart 侧的窗口内容动画等这个 result 才起步，与原生淡入同帧。
      onReady()
    }
  }

  /// `setup` 的自检结果。延迟到窗口外观定型之后采集，日志才有意义。
  private func windowDiagnostics(_ window: NSWindow) -> [String: Any] {
    let content = window.contentView
    let layer = content?.layer
    let bg = layer?.backgroundColor
    return [
      "visible": window.isVisible,
      "miniaturized": window.isMiniaturized,
      "key": window.isKeyWindow,
      "main": window.isMainWindow,
      "level": window.level.rawValue,
      "styleMask": Int(window.styleMask.rawValue),
      "alpha": window.alphaValue,
      "x": window.frame.origin.x,
      "y": window.frame.origin.y,
      "w": window.frame.width,
      "h": window.frame.height,
      // 出现时序自检：hiddenAtCreation=true / preSetupAlpha=0 才说明
      // 首帧之前就压住了窗口，用户不可能看到左侧默认坐标。
      "hiddenAtCreation": hiddenAtCreation.contains(ObjectIdentifier(window)),
      "preSetupAlpha": preSetupAlpha[ObjectIdentifier(window)] ?? -1,
      "revealed": revealedWindows.contains(ObjectIdentifier(window)),
      "pending": pendingReveal.contains(ObjectIdentifier(window)),
      // 透明度自检：清掉引擎的黑色占位底之后，这些值应为
      // content=FlutterViewWrapper / bgAlpha=0 / opaque=false。
      "content": content.map { String(describing: type(of: $0)) } ?? "nil",
      "bgAlpha": bg.map { $0.alpha } ?? -1,
      "opaque": layer?.isOpaque ?? false,
      "layers": content.map { describe($0) } ?? "nil",
      // performWindowDragWithEvent: 在部分 SDK 头文件里被裁剪，运行时自检。
      "canDrag": window.responds(to: NSSelectorFromString("performWindowDragWithEvent:")),
      "canKey": window.canBecomeKey,
      "borderless": !window.styleMask.contains(.titled),
    ]
  }

  // ------------------------------------------------------------ 出现时序
  /// 在引擎创建任何 NSWindow 之前装好钩子（applicationDidFinishLaunching 里
  /// 早于 `FlutterEngine.run`）。四层保险，关键是第 ① 层：
  ///
  /// ① `setContentViewController:` —— 引擎给窗口挂 FlutterViewController 时
  ///    窗口还没显示，在这里压 alpha 才能做到「一帧都不会露出默认坐标」。
  /// ② `setIsVisible:` / `orderFront:` —— 在调用原实现**之前**压 alpha，
  ///    覆盖首帧的 `[window setIsVisible:YES]`。通知做不到这一点：它异步投递
  ///    到主队列，等 block 执行时那一帧已经被 Window Server 合成过了。
  ///    **不要替换 `makeKeyAndOrderFront:`**：实测换掉它之后所有窗口都拿不到
  ///    key 状态（登录框收不到键盘），AppKit 的聚焦路径必须原样保留；拦在更早
  ///    的 `setIsVisible:` 即可，alpha 已是 0，后面的 order front 也看不见。
  /// ③ `didBecomeVisibleNotification` 覆盖其它显示路径（如 `activate()`）。
  /// ④ `willCloseNotification` 清理窗口身份记录。
  private func installWindowShowHook() {
    if AppDelegate.showHookInstalled { return }
    AppDelegate.showHookInstalled = true

    installContentViewControllerHook()
    installSetIsVisibleHook()
    installOrderFrontHook()

    // 本 SDK 的 AppKit Swift overlay 没暴露 didBecomeVisibleNotification /
    // willCloseNotification 这两个符号，直接用稳定的 ObjC 通知名字符串。
    NotificationCenter.default.addObserver(
      forName: Notification.Name("NSWindowDidBecomeVisibleNotification"),
      object: nil, queue: .main) { [weak self] note in
        guard let window = note.object as? NSWindow else { return }
        self?.holdHiddenIfNeeded(window)
      }

    // NSWindow 地址会被复用，窗口关闭时必须清掉身份记录，否则下一个窗口
    // 可能被误判成「已经淡入过」而不再隐藏。
    NotificationCenter.default.addObserver(
      forName: Notification.Name("NSWindowWillCloseNotification"),
      object: nil, queue: .main) { [weak self] note in
        guard let window = note.object as? NSWindow else { return }
        self?.forget(window)
      }
  }

  /// ① 创建期钩子：这是整个修复的核心。
  private func installContentViewControllerHook() {
    let selector = NSSelectorFromString("setContentViewController:")
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
    let original = method_getImplementation(method)
    typealias SetterIMP = @convention(c) (NSWindow, Selector, AnyObject?) -> Void
    let callOriginal = unsafeBitCast(original, to: SetterIMP.self)
    let replacement: @convention(block) (NSWindow, AnyObject?) -> Void = { [weak self] w, vc in
      // 先让 AppKit 完成挂载，随后 contentViewController 的判断才成立。
      callOriginal(w, selector, vc)
      guard let self, vc is FlutterViewController else { return }
      self.prepareNewFlutterWindow(w)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  /// ② `setIsVisible:`：ObjC BOOL 用 Int8 逐位透传，避免 Swift Bool 与
  /// AppKit overlay 的 ABI 差异把 YES 变成 NO（那会让窗口永远不显示）。
  private func installSetIsVisibleHook() {
    let selector = NSSelectorFromString("setIsVisible:")
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
    let original = method_getImplementation(method)
    typealias VisibleIMP = @convention(c) (NSWindow, Selector, Int8) -> Void
    let callOriginal = unsafeBitCast(original, to: VisibleIMP.self)
    let replacement: @convention(block) (NSWindow, Int8) -> Void = { [weak self] w, flag in
      if flag != 0 { self?.holdHiddenIfNeeded(w) }
      callOriginal(w, selector, flag)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  private func installOrderFrontHook() {
    let selector = NSSelectorFromString("orderFront:")
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
    let original = method_getImplementation(method)
    typealias OrderIMP = @convention(c) (NSWindow, Selector, AnyObject?) -> Void
    let callOriginal = unsafeBitCast(original, to: OrderIMP.self)
    let replacement: @convention(block) (NSWindow, AnyObject?) -> Void = { [weak self] w, sender in
      self?.holdHiddenIfNeeded(w)
      callOriginal(w, selector, sender)
    }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }

  /// 引擎刚把 FlutterViewController 挂到新窗口上、窗口还没显示时调用。
  /// 这是唯一能保证「首帧之前」的时机。
  private func prepareNewFlutterWindow(_ window: NSWindow) {
    let windowId = ObjectIdentifier(window)
    guard !revealedWindows.contains(windowId) else { return }
    if !pendingReveal.contains(windowId) {
      pendingReveal.insert(windowId)
      armRevealFallback(for: window)
    }
    hiddenAtCreation.insert(windowId)
    window.alphaValue = 0

    // 位置兜底：`[[NSWindow alloc] init]` 的默认 frame 在屏幕左侧。万一有
    // 路径把 alpha 重置回 1，窗口也在屏幕中央而不是左边缘，不会出现刺眼的
    // 「左侧闪一下」。正常路径下 setup 会再按锚点精确摆位（那时 alpha=0）。
    let screen = NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = window.frame.size
    window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                  y: screen.midY - size.height / 2))
  }

  /// 首次出现的 Flutter 窗口：记入待显示队列并压成完全透明。
  private func holdHiddenIfNeeded(_ window: NSWindow) {
    let windowId = ObjectIdentifier(window)
    guard !revealedWindows.contains(windowId),
          window.contentViewController is FlutterViewController else { return }
    if !pendingReveal.contains(windowId) {
      pendingReveal.insert(windowId)
      armRevealFallback(for: window)
    }
    window.alphaValue = 0
  }

  /// 兜底：万一 `setup` 没送到（句柄获取失败 / 通道异常），2.5s 后强制显示，
  /// 绝不让窗口变成「进程在跑但什么也看不见」。留足启动耗时的余量，避免
  /// 兜底先于 setup 触发、把窗口在旧坐标上亮出来。
  private func armRevealFallback(for window: NSWindow) {
    let windowId = ObjectIdentifier(window)
    let work = DispatchWorkItem { [weak self, weak window] in
      guard let self, let window, self.pendingReveal.contains(windowId) else { return }
      self.pendingReveal.remove(windowId)
      self.revealedWindows.insert(windowId)
      window.alphaValue = 1
    }
    revealFallbacks[windowId] = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
  }

  /// 摆位 / 去边框全部就绪后调用：把窗口淡入。
  /// 只动 alpha，不动 frame —— 改 frame 会触发 Flutter surface 重排，
  /// 异形窗口上会出现拉伸甚至 Impeller 尺寸不一致崩溃。
  ///
  /// 实测本 SDK 上 `window.animator().alphaValue = 1` 在
  /// `NSAnimationContext.runAnimationGroup` 里不会改变窗口的 alpha
  /// （窗口会永久停在 0，完全隐形）。改成按帧显式写 alphaValue，配一条
  /// easeOut 曲线，效果等价且不会依赖 animator 代理的实现细节。
  private func reveal(_ window: NSWindow) {
    let windowId = ObjectIdentifier(window)
    guard pendingReveal.contains(windowId) else { return }
    pendingReveal.remove(windowId)
    revealedWindows.insert(windowId)
    revealFallbacks.removeValue(forKey: windowId)?.cancel()

    window.alphaValue = 0
    if !window.isVisible { window.setIsVisible(true) }
    let duration = 0.26
    let steps = 13
    for step in 1...steps {
      DispatchQueue.main.asyncAfter(
        deadline: .now() + duration * Double(step) / Double(steps)) { [weak window] in
        guard let window else { return }
        let t = Double(step) / Double(steps)
        window.alphaValue = CGFloat(1 - pow(1 - t, 3))
      }
    }
    // 首帧被压成 alpha=0 时 AppKit 不会把窗口设为 key（登录框会收不到
    // 键盘），淡入结束后补一次聚焦。此时 revealed 集合里已有该窗口，
    // 显示钩子不会再把它压回透明。
    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) { [weak window] in
      guard let window, window.canBecomeKey else { return }
      window.alphaValue = 1
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func forget(_ window: NSWindow) {
    let windowId = ObjectIdentifier(window)
    pendingReveal.remove(windowId)
    revealedWindows.remove(windowId)
    hiddenAtCreation.remove(windowId)
    preSetupAlpha.removeValue(forKey: windowId)
    targetFrames.removeValue(forKey: windowId)
    revealFallbacks.removeValue(forKey: windowId)?.cancel()
  }

  /// 按锚点摆位。桌面版没有「控制台」参考系，全部以 `NSScreen.visibleFrame`
  /// 为准，换显示器或改分辨率都不需要改 Dart 常量。
  ///
  /// 注意 AppKit 的窗口原点是左下角，`y` 越小越靠下。
  private func place(window: NSWindow, anchor: String, index: Int) {
    let screen = NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = window.frame.size
    let step = CGFloat(index) * 28
    let origin: NSPoint
    switch anchor {
    case "top-right":
      origin = NSPoint(x: screen.maxX - size.width - 24,
                       y: screen.maxY - size.height - 24)
    case "center-right":
      origin = NSPoint(x: screen.maxX - size.width - 300,
                       y: screen.midY - size.height / 2)
    case "cascade":
      // 聊天窗从屏幕偏左上开始，逐窗右下错开 28pt。
      origin = NSPoint(x: screen.minX + screen.width * 0.34 + step,
                       y: screen.maxY - size.height - screen.height * 0.20 - step)
    case "center":
      origin = NSPoint(x: screen.midX - size.width / 2,
                       y: screen.midY - size.height / 2 - 16)
    default:
      origin = NSPoint(x: screen.midX - size.width / 2,
                       y: screen.midY - size.height / 2)
    }
    window.setFrameOrigin(origin)
  }

  /// 去掉所有窗口装饰（无边框、无阴影、无系统背景）。
  ///
  /// `NSWindow` 的 `canBecomeKey` / `canBecomeMain` 默认对 borderless 返回
  /// false，登录框会收不到键盘。这里把引擎创建的 NSWindow 实例在运行时换成
  /// 重写了这两个属性的子类。
  ///
  /// 顺序很重要：**先** `styleMask = []` 让 AppKit 把 NSTitlebarView 摘掉
  /// （它在 `viewWillMoveToWindow:` 里注销对窗口的 KVO），**再**换类。
  /// 反过来先在 KVO 的 `NSKVONotifying_NSWindow` 上换成自定义类，注销观察者
  /// 时会抛 `Cannot remove an observer ... because it is not registered`。
  private func makeBorderlessKeyable(_ window: NSWindow) {
    // 排查开关：QQ_BORDERLESS=0 时保持原生 titled 外观（有 1px 边框但零风险）。
    if ProcessInfo.processInfo.environment["QQ_BORDERLESS"] == "0" {
      window.hasShadow = false
      return
    }
    let wasKey = window.isKeyWindow
    window.styleMask = []
    window.hasShadow = false
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = false

    // borderless 窗口默认不能成为 key（登录框收不到键盘）。
    // 这里**不换类**：`object_setClass` 会让窗口的 dealloc 走另一个类，
    // 关闭窗口时打 `NSAutoreleasePool ... double release`（实测：只改
    // styleMask 不换类则完全没有该告警）。改成替换 NSWindow 的
    // canBecomeKey 实现，只对「承载 FlutterViewController 的窗口」返回 true。
    makeFlutterWindowsKeyable()

    if !window.canBecomeKey {
      // 极端情况：补丁没生效，退回 titled（有边框但至少能输入）。
      window.styleMask = window.styleMask.union([.titled, .fullSizeContentView])
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.hasShadow = false
    }
    // 改 styleMask 会让窗口失去 key 状态；原本是 key 的话立刻抢回来，
    // 否则登录框要点一下才能输入。
    if wasKey {
      window.makeKeyAndOrderFront(nil)
    }
  }

  private static var patchedKeyable = false

  /// 让「承载 Flutter 内容的窗口」永远可以成为 key 窗口。
  ///
  /// 只替换 canBecomeKey / canBecomeKeyWindow：非 Flutter 窗口仍按
  /// styleMask 判断（与 NSWindow 默认行为一致），避免影响 AppKit 内部窗口。
  private func makeFlutterWindowsKeyable() {
    if AppDelegate.patchedKeyable { return }
    AppDelegate.patchedKeyable = true
    let block: @convention(block) (NSWindow) -> Bool = { w in
      if w.contentViewController is FlutterViewController { return true }
      return w.styleMask.contains(.titled)
    }
    let imp = imp_implementationWithBlock(block)
    for name in ["canBecomeKey", "canBecomeKeyWindow"] {
      let sel = NSSelectorFromString(name)
      if let method = class_getInstanceMethod(NSWindow.self, sel) {
        method_setImplementation(method, imp)
      }
    }
  }

  /// 让窗口内容区真正透明，露出「异形」轮廓之外的桌面。
  ///
  /// macOS 引擎的 FlutterView 在 init 里执行 `setBackgroundColor:[NSColor
  /// blackColor]`（首帧前的占位），加上窗口默认不透明，圆角 / 相框之外
  /// 的透明像素就会被渲染成黑色。这里把 NSWindow、contentView 以及各层
  /// CALayer 的背景全部清成透明色，Flutter 画出的空像素才能真正透出后面
  /// 的控制台壁纸。
  private func makeContentTransparent(_ window: NSWindow) {
    window.isOpaque = false
    window.backgroundColor = .clear
    guard let content = window.contentView else { return }
    clearBackground(content)
  }

  private func clearBackground(_ view: NSView) {
    view.wantsLayer = true
    if let layer = view.layer {
      layer.backgroundColor = NSColor.clear.cgColor
      clearLayers(layer)
    }
    // FlutterView 暴露了 setBackgroundColor:（内部即改 layer 背景），
    // 头文件里没有，用 responds/perform 调用，避免改 SDK。
    let selector = Selector(("setBackgroundColor:"))
    if view.responds(to: selector) {
      _ = view.perform(selector, with: NSColor.clear)
    }
    for subview in view.subviews {
      clearBackground(subview)
    }
  }

  private func clearLayers(_ layer: CALayer) {
    layer.isOpaque = false
    for sublayer in layer.sublayers ?? [] {
      clearLayers(sublayer)
    }
  }

  /// 诊断用：把 contentView 的视图树连同每层背景透明度拼成一行。
  private func describe(_ view: NSView) -> String {
    let name = String(describing: type(of: view))
    let alpha = view.layer?.backgroundColor?.alpha ?? -1
    let head = "\(name):\(String(format: "%.2f", alpha))"
    let kids = view.subviews.map { describe($0) }
    return kids.isEmpty ? head : "\(head)[\(kids.joined(separator: ","))]"
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}


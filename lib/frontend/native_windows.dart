// QQ 概念版 · 桌面端「真·独立窗口」（第二期）
//
// 使用 Flutter master 渠道的实验性 Desktop Windowing API：
//   - `WindowController` 构造时即创建原生 OS 窗口（macOS NSWindow）；
//   - `Window` widget 把内容渲染到该窗口对应的 FlutterView；
//   - 所有窗口仍在同一棵 widget 树、同一个 Engine / isolate 内，[QAppState]
//     直接共享，消息收发与模拟回复无需任何跨窗口同步协议。
//
// 窗口清单：**只有内容窗口**（登录 / 主面板 / 每个聊天 / 好友管理 / 设置 / 关于），
// 不再有「桌面控制台」这种调试用宿主窗口 —— 桌面版对外就是一台正常的 IM：
// 启动只有登录窗，登录后换成主面板，其余窗口由用户操作按需打开。
// 窗口统一由 [QAppState.windows] 驱动，本类监听 ChangeNotifier 并 diff 出
// OS 窗口的创建、销毁、最小化与聚焦，因此登录→主面板、退出登录无需特例。
//
// 关键约束（实测）：macOS 引擎的 enableMultiView 要求「注册任何 view
// controller 之前」调用，所以**主窗口也必须由 Dart 侧创建**，Runner 不能
// 预先建 FlutterViewController。因此桌面窗口化入口用 `runWidget` +
// [ViewCollection] 作为根，而不是 `runApp` + 隐式 view。web 端仍用 runApp。
//
// 官方 API 没有 frameless / setPosition：macOS Runner 的方法通道负责把
// NSWindow 改成无标题栏的透明窗口、按设计稿坐标摆放，并转发标题栏拖拽。
//
// 该 API 位于 `package:flutter/src/widgets/_window.dart`，未走公开导出，
// 且带 @internal 标记；官方 integration_test / examples/multiple_windows
// 同样以 implementation_imports + invalid_use_of_internal_member 忽略方式使用。
//
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../core/models.dart';
import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';
import 'window_content.dart';

/// 与 macOS Runner 的 `qq_concept/windows` 通道通信：去原生标题栏、摆位、拖拽。
const MethodChannel _kWindowChannel = MethodChannel('qq_concept/windows');

/// 窗口落位锚点：由原生按 `NSScreen.visibleFrame` 换算，Dart 侧不需要知道
/// 屏幕分辨率（换了显示器也不会再算错）。
String _anchorFor(QWindowKind kind) => switch (kind) {
  QWindowKind.login => 'center',
  QWindowKind.register => 'center',
  QWindowKind.panel => 'top-right',
  QWindowKind.chat => 'cascade',
  QWindowKind.settings => 'center-right',
  QWindowKind.friendsManager => 'center',
  QWindowKind.about => 'center',
};

class _NativeWindow {
  _NativeWindow({
    required this.id,
    required this.kind,
    required this.friend,
    required this.size,
    required this.controller,
    required this.minimized,
  });

  final String id;
  final QWindowKind kind;
  final String? friend;
  final Size size;
  final WindowController controller;
  bool minimized;

  /// 原生层摆位 / 去边框就绪后才置 true，驱动窗口内容的出现动画。
  /// 不主动 dispose：窗口 widget 卸载后它随 [_NativeWindow] 一起被 GC 回收。
  final ValueNotifier<bool> reveal = ValueNotifier<bool>(false);
}

class _WindowLifecycleDelegate with WindowControllerDelegate {
  const _WindowLifecycleDelegate({required this.onDestroyed});

  final VoidCallback onDestroyed;

  @override
  void onWindowDestroyed() {
    onDestroyed();
    super.onWindowDestroyed();
  }
}

/// 桌面端所有原生窗口的持有者。
///
/// [active] 为 false 时表示原生窗口创建失败，调用方应把 QDesktop 切回
/// 画布模式（web / 未开启 windowing 的环境本来就不会创建本对象）。
class QNativeWindows extends ChangeNotifier {
  QNativeWindows._(this.state) {
    state.addListener(_sync);
    state.onIncomingNotification = _notifyIncoming;
  }

  final QAppState state;

  final Map<String, _NativeWindow> _windows = <String, _NativeWindow>{};
  final Set<String> _destroying = <String>{};
  bool _disposed = false;
  bool active = true;
  String? _topId;

  /// 是否在窗口化模式下运行。仅 macOS 做过 Runner 适配与真机验证。
  static bool get isSupported {
    if (kIsWeb || !isWindowingEnabled) return false;
    return defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// 在 `main()` 中、任何 view controller 被注册之前创建第一扇窗口。
  /// 失败（引擎不支持 / flag 未生效）返回 null，调用方回退到 web 式单画布入口。
  static QNativeWindows? tryCreate(QAppState state) {
    if (!isSupported) return null;
    try {
      final host = QNativeWindows._(state);
      // 原生窗口边界 == 画布尺寸，卡片外阴影只能在窗口里糊成灰雾。
      qNativeWindowChrome = true;
      host._sync();
      if (kDebugMode) {
        debugPrint('[QQ] 窗口化模式已启用：${host._windows.length} 个窗口（无控制台）');
      }
      return host;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[QQ] 窗口化初始化失败，回退单画布入口：$error');
      }
      qNativeWindowChrome = false;
      return null;
    }
  }

  int get count => _windows.length;

  void _notifyIncoming(String title, String body, String? chatId, bool sound) {
    final window = chatId == null ? null : _windows[chatId];
    final handle = window == null ? null : _handleOf(window.controller);
    _kWindowChannel
        .invokeMethod<void>('notify', <String, dynamic>{
          'title': title,
          'body': body,
          'sound': sound,
          if (handle != null) 'handle': handle,
        })
        .catchError((Object error) {
          debugPrint('[QQ] 通知失败：$error');
          state.flash('通知失败：$error');
        });
  }

  bool get isEmpty => _windows.isEmpty;

  /// `runWidget` 的根：全部内容窗口。没有窗口时是空集合（AppKit 里就是
  /// 一个没有窗口但仍在运行的应用），调用方通常已经在退出流程里。
  Widget rootView() => ViewCollection(
    views: <Widget>[for (final e in _windows.values) _build(e)],
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------ 状态 → 窗口同步
  void _sync() {
    if (_disposed) return;

    // 没有控制台兜底：最后一扇窗口关掉即退出（关登录窗 / 关主面板都算）。
    // 这里先不销毁现有窗口，避免用已销毁的 controller 重建 ViewCollection。
    if (state.windows.isEmpty && _windows.isNotEmpty) {
      _quit('所有窗口已关闭');
      return;
    }

    var changed = false;

    final ids = state.windows.map((w) => w.id).toSet();
    for (final id in List<String>.from(_windows.keys)) {
      if (!ids.contains(id)) {
        _destroy(id);
        changed = true;
      }
    }

    for (final w in state.windows) {
      final e = _windows[w.id];
      if (e == null) {
        _create(w);
        changed = true;
      } else if (e.minimized != w.minimized) {
        e.minimized = w.minimized;
        _call(e, (c) => c.setMinimized(w.minimized));
        changed = true;
      }
    }

    // 顶层窗口变化 → 把对应 OS 窗口置前；普通状态变化（输入账号、toast、
    // 切换 tab）不重建 ViewCollection，避免逐键输入时打断输入框焦点。
    final ordered = state.ordered;
    final top = ordered.isEmpty ? null : ordered.last.id;
    if (top != _topId) {
      _topId = top;
      final e = top == null ? null : _windows[top];
      if (e != null && !e.minimized) _call(e, (c) => c.activate());
      changed = true;
    }

    if (changed) _notify();
  }

  void _create(QWindow w) {
    final size = qWindowSize(w.kind);
    try {
      final controller = WindowController(
        size: size,
        // 1x 像素稿不能缩放：把窗口锁死在设计尺寸上。
        constraints: BoxConstraints(
          minWidth: size.width,
          minHeight: size.height,
          maxWidth: size.width,
          maxHeight: size.height,
        ),
        title: qWindowTitle(w.kind, w.friend),
        delegate: _WindowLifecycleDelegate(
          onDestroyed: () => _onOsDestroyed(w.id),
        ),
      );
      final e = _NativeWindow(
        id: w.id,
        kind: w.kind,
        friend: w.friend,
        size: size,
        controller: controller,
        minimized: w.minimized,
      );
      _windows[w.id] = e;
      _setupWindow(e, _chatIndex(w.id), onReady: () => _reveal(e));
      if (w.minimized) _call(e, (c) => c.setMinimized(true));
      if (kDebugMode) {
        debugPrint('[QQ] 独立窗口已创建：${w.id}（共 ${_windows.length} 个）');
        // 去边框是首帧之后异步做的，这里补一次外观自检。
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (_disposed || !_windows.containsKey(e.id)) return;
          final h = _handleOf(e.controller);
          if (h != null) {
            _invoke('info', <String, dynamic>{'handle': h}, log: true);
          }
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[QQ] 独立窗口创建失败：${w.id} → $error');
      }
      // 极端情况（引擎窗口数上限等）：整体回退画布模式，避免白屏。
      active = false;
    }
  }

  void _destroy(String id) {
    final e = _windows.remove(id);
    if (e == null) return;
    // 让仍在树上的出现动画收到终态，避免窗口销毁瞬间闪回初始变换。
    if (!e.reveal.value) e.reveal.value = true;
    _destroying.add(id);
    if (!e.controller.isDestroyed) {
      try {
        e.controller.destroy();
      } catch (_) {}
    }
    _destroying.remove(id);
  }

  /// 结束应用（桌面版没有托盘，关掉最后一扇窗口就等于退出）。
  void _quit(String reason) {
    if (_disposed) return;
    if (kDebugMode) debugPrint('[QQ] $reason，退出应用');
    ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  /// 用户在 OS 层关掉窗口（⌘W / Dock）：同步回窗口注册表。
  void _onOsDestroyed(String id) {
    if (_disposed || _destroying.contains(id)) return;
    if (!_windows.containsKey(id)) return;
    _windows.remove(id);
    state.close(id);
    _notify();
  }

  int _chatIndex(String id) => _windows.values
      .where((e) => e.kind == QWindowKind.chat && e.id != id)
      .length;

  // ------------------------------------------------------------ 原生层交互
  void _setupWindow(_NativeWindow e, int index, {VoidCallback? onReady}) {
    final handle = _handleOf(e.controller);
    if (handle == null) {
      // 拿不到 NSWindow 句柄就不要让内容动画卡在初始态。
      onReady?.call();
      return;
    }
    _invoke(
      'setup',
      <String, dynamic>{
        'handle': handle,
        'width': e.size.width,
        'height': e.size.height,
        // 原生按 NSScreen.visibleFrame 换算锚点，cascade 用 index 做阶梯错开。
        'anchor': _anchorFor(e.kind),
        'index': index,
        'floating': false,
        'resize': true,
        // 内容窗口是异形 + 真透明：系统矩形阴影会从透明像素里透出来
        // （看起来像蒙了一层浅灰），必须关掉。
        'shadow': false,
      },
      log: true,
      onDone: onReady,
    );
  }

  /// `setup` 的 result 由原生层在「摆位 + 去边框 + 开始淡入」之后才返回，
  /// 因此这里触发的内容动画与 NSWindow 的 alpha 淡入基本同帧。
  void _reveal(_NativeWindow e) {
    if (_disposed || !_windows.containsKey(e.id)) return;
    if (!e.reveal.value) {
      if (kDebugMode) debugPrint('[QQ] 窗口出现动画：${e.id}');
      e.reveal.value = true;
    }
  }

  /// 自绘标题栏拖拽：把后续鼠标事件交给 AppKit 的窗口拖动循环。
  ///
  /// 不能再按 Flutter 的 pointer delta 逐帧移动窗口：窗口跟着鼠标走时，
  /// pointer 事件的坐标是相对窗口的，窗口一动坐标就抵消掉位移，形成
  /// 负反馈 —— 表现就是掉帧、抖动、跟不上鼠标。
  void _startDrag(_NativeWindow e) {
    final handle = _handleOf(e.controller);
    if (handle == null) return;
    if (kDebugMode) debugPrint('[QQ] 标题栏拖动：${e.id}');
    _invoke('drag', <String, dynamic>{'handle': handle});
  }

  int? _handleOf(WindowController controller) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return null;
    try {
      // macOS controller 才有的 NSWindow* 句柄；用 dynamic 避免在非 macOS
      // 平台编译 dart:ffi 平台实现。
      final dynamic handle = (controller as dynamic).windowHandle;
      return handle.address as int;
    } catch (_) {
      return null;
    }
  }

  void _invoke(
    String method,
    Map<String, dynamic> args, {
    bool log = false,
    VoidCallback? onDone,
  }) {
    try {
      _kWindowChannel
          .invokeMethod<dynamic>(method, args)
          .then(
            (value) {
              if (log && kDebugMode) {
                debugPrint('[QQ] 窗口通道 $method → $value');
              }
              onDone?.call();
            },
            onError: (Object error, StackTrace stack) {
              if (kDebugMode) {
                debugPrint('[QQ] 窗口通道 $method 调用失败：$error');
              }
              // 通道异常时也让内容回到正常态，窗口不能被动画卡住。
              onDone?.call();
            },
          );
    } catch (_) {
      // 通道未就绪（例如 web）时静默降级。
      onDone?.call();
    }
  }

  void _call(_NativeWindow e, void Function(WindowController c) fn) {
    if (e.controller.isDestroyed) return;
    try {
      fn(e.controller);
    } catch (_) {
      // 平台可以忽略某个状态请求，不应影响 UI。
    }
  }

  // ------------------------------------------------------------ 子窗口内容
  Widget _build(_NativeWindow e) {
    return Window(
      // 按窗口 id 加 key：ViewCollection 增删窗口时不会复用其它窗口的
      // 动画 State（否则新窗口会继承「已播完」的状态，直接硬出现）。
      key: ValueKey<String>('q-window-${e.id}'),
      controller: e.controller,
      // 新 FlutterView 拿不到控制台窗口的 Directionality / Theme / MediaQuery，
      // 每个子窗口单独跑一份 MaterialApp，但共享同一个 QAppState。
      // 不套 Scaffold：登录 / 主面板的圆角与装饰需要透出控制台壁纸。
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: qWindowTitle(e.kind, e.friend),
        scrollBehavior: const QNoSystemScrollbarBehavior(),
        theme: qqTheme(),
        // 不套 Scaffold（登录 / 主面板的圆角需要透出控制台壁纸），
        // 但 TextField 等 Material 控件必须有 Material 祖先。
        // 出现动画放在内容最外层：原生 NSWindow 淡入 alpha 的同时，
        // 内容轻微上浮 + 缩放到位，两层动画由 setup 的 result 同步起步。
        home: _WindowReveal(
          signal: e.reveal,
          child: Material(
            type: MaterialType.transparency,
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) {
                final dragH =
                    (e.kind == QWindowKind.panel && state.panelSettings)
                    ? S.settingsBarH
                    : qDragHeight(e.kind);
                return SizedBox(
                  width: e.size.width,
                  height: e.size.height,
                  child: Stack(
                    children: [
                      // 不能用 Positioned.fill 再包一层：登录框 PillField 内部
                      // 已有 Positioned，嵌套会触发 ParentDataWidget 冲突。
                      buildQWindowContent(
                        state,
                        QWindow(id: e.id, kind: e.kind, friend: e.friend),
                        onWindowButton: (k) => _onWindowButton(e, k),
                      ),
                      // 自绘标题栏拖拽条：与画布桌面同款 translucent 命中方式，
                      // 点击仍由下层控件处理，只有真的拖动才交给原生窗口。
                      Positioned(
                        left: 0,
                        top: 0,
                        width: e.size.width,
                        height: dragH,
                        child: _DragHandle(onDragStart: () => _startDrag(e)),
                      ),
                      if (e.kind == QWindowKind.panel && state.toast != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 12,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xE61E2225),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  state.toast!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onWindowButton(_NativeWindow e, QWinBtnKind k) {
    switch (k) {
      case QWinBtnKind.minimize:
        // 交给 _sync 统一调 setMinimized，保持状态层为单一数据源。
        state.minimize(e.id);
      case QWinBtnKind.close:
      case QWinBtnKind.back:
        state.close(e.id);
      case QWinBtnKind.maximize:
        _call(e, (c) => c.setMaximized(!c.isMaximized));
      case QWinBtnKind.gear:
        // 齿轮 = 系统设置快捷键；主菜单由主面板左下角企鹅球打开。
        state.handleMenuAction('系统设置');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    qNativeWindowChrome = false;
    state.removeListener(_sync);
    state.onIncomingNotification = null;
    for (final id in List<String>.from(_windows.keys)) {
      _destroy(id);
    }
    super.dispose();
  }
}

/// 自绘标题栏的拖拽手柄。
///
/// 只负责一件事：判断「用户是在拖动，还是在点击」。
/// 按下后位移超过 3px 才通知原生层调用 `performWindowDrag(with:)`，
/// 之后整段拖动由 AppKit 的拖动循环处理 —— 窗口 1:1 跟随鼠标，不需要
/// 每帧过一次 MethodChannel，也不会和 Flutter 的指针坐标互相拉扯。
///
/// 用 [Listener] 而不是 [GestureDetector]：pan 手势要先打赢竞技场
/// （kPanSlop 约 36px）才回调 onPanStart，标题栏只有 30~60px 高，
/// 那点位移足以让窗口「黏」在鼠标后面不跟手。
class _DragHandle extends StatefulWidget {
  const _DragHandle({required this.onDragStart});

  final VoidCallback onDragStart;

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  Offset? _origin;
  bool _fired = false;

  @override
  Widget build(BuildContext context) => Listener(
    // translucent：不吞掉点击，下层窗口按钮 / tab 照常响应。
    behavior: HitTestBehavior.translucent,
    onPointerDown: (d) {
      _origin = d.position;
      _fired = false;
    },
    onPointerMove: (d) {
      if (_fired) return;
      final origin = _origin;
      if (origin == null) return;
      if ((d.position - origin).distance < 3) return;
      _fired = true;
      widget.onDragStart();
    },
    onPointerUp: (_) => _origin = null,
    onPointerCancel: (_) => _origin = null,
    child: const SizedBox.expand(),
  );
}

/// 原生窗口的出现动画：内容淡入 + 轻微上浮 + 缩放到位，与 NSWindow 的
/// alpha 淡入叠加成一次「浮现」。
///
/// [signal] 由 `setup` 通道的返回值驱动：原生层把摆位、透明化、去边框
/// 全部做完、正要淡入时才回 result，所以内容动画不会早于窗口出现，
/// 窗口也不会在旧坐标上被人看到。
///
/// 动画结束后直接返回 [child]，不留下多余的 Opacity / Transform 合成层 ——
/// 异形透明窗口里常驻的合成层容易让半透明区域发灰。
class _WindowReveal extends StatefulWidget {
  const _WindowReveal({required this.signal, required this.child});

  final ValueListenable<bool> signal;
  final Widget child;

  @override
  State<_WindowReveal> createState() => _WindowRevealState();
}

class _WindowRevealState extends State<_WindowReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    widget.signal.addListener(_onSignal);
    if (widget.signal.value) {
      // setup 有可能在本 widget 挂载前就返回（热重载 / 通道极快）。
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(covariant _WindowReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signal != widget.signal) {
      oldWidget.signal.removeListener(_onSignal);
      widget.signal.addListener(_onSignal);
      if (widget.signal.value) _play();
    }
  }

  void _onSignal() {
    if (widget.signal.value) _play();
  }

  void _play() {
    if (_started || !mounted) return;
    _started = true;
    setState(() {});
    _controller.forward().then((_) {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    widget.signal.removeListener(_onSignal);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done || !_started) return widget.child;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          // 起点 0.3 而不是 0：原生 alpha 淡入比 Dart 回调早一帧起步，
          // 留一点底避免「窗口亮了、内容还没出现」的空窗。
          opacity: 0.3 + 0.7 * t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

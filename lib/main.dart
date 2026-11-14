import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'core/app_state.dart';
import 'core/app_theme.dart';
import 'core/models.dart';
import 'frontend/desktop.dart';
import 'frontend/native_windows.dart';

const Set<String> _presets = {
  'login',
  'main',
  'friends',
  'menu',
  'bamboo',
  'chat',
  'fm',
  'settings',
  'about',
  'demo',
};

String _readPreset() {
  final fragment = Uri.base.fragment.toLowerCase();
  final preset =
      Uri.base.queryParameters['preset'] ??
      (fragment.isEmpty ? 'demo' : fragment);
  return _presets.contains(preset) ? preset : 'demo';
}

/// 开发 / 演示用：启动时预开多个独立聊天窗。
/// `flutter run -d macos --dart-define=QQ_INITIAL_CHATS=阿澈,苏禾,林岚`
const String _kInitialChats = String.fromEnvironment('QQ_INITIAL_CHATS');

/// 桌面端没有 URL fragment，用 dart-define 指定初始状态（便于核对登录窗）。
/// `flutter run -d macos --dart-define=QQ_PRESET=login`
const String _kPresetOverride = String.fromEnvironment('QQ_PRESET');

/// 开发期验证钩子：首帧后自动登录，用于核对「登录窗销毁 → 主面板创建」。
const bool _kAutoLogin = bool.fromEnvironment('QQ_AUTO_LOGIN');

List<String> _readInitialChats() => _kInitialChats.isEmpty
    ? const <String>[]
    : _kInitialChats
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);

/// 入口分两路：
/// - 桌面窗口化（macOS + master + `--enable-windowing`）：`runWidget` +
///   [ViewCollection]，根只有内容窗口，**没有控制台宿主窗口**；
/// - web / 其余平台：`runApp`，保持单画布浮动桌面（用于对照与回归）。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final windowing = QNativeWindows.isSupported;
  // 桌面版按真实产品流程起步：未登录 → 只有登录窗。web 仍按 URL 预设。
  final preset = _kPresetOverride.isNotEmpty
      ? _kPresetOverride
      : (windowing ? 'login' : _readPreset());
  final state = QAppState(preset: preset);
  final native = QNativeWindows.tryCreate(state);
  if (native != null) {
    runWidget(NativeWindowsRoot(state: state, native: native));
  } else {
    runApp(QQConceptApp(state: state));
  }
}

/// 桌面窗口化的根 widget。
///
/// 与画布模式的区别：没有「桌面控制台」——不画壁纸、顶栏、任务栏，
/// 应用对外就是若干原生窗口本身。窗口列表来自 [QNativeWindows.rootView]，
/// 由它监听 [QAppState] 增量维护。
class NativeWindowsRoot extends StatefulWidget {
  const NativeWindowsRoot({
    super.key,
    required this.state,
    required this.native,
  });

  final QAppState state;
  final QNativeWindows native;

  @override
  State<NativeWindowsRoot> createState() => _NativeWindowsRootState();
}

class _NativeWindowsRootState extends State<NativeWindowsRoot> {
  @override
  void initState() {
    super.initState();
    widget.native.addListener(_onChanged);
    if (_kAutoLogin || _readInitialChats().isNotEmpty) {
      // 改窗口注册表会触发上层 setState，必须等首帧之后再执行。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_kAutoLogin) {
          widget.state.setPassword('demo');
          widget.state.login();
        }
        for (final friend in _readInitialChats()) {
          widget.state.open(QWindowKind.chat, friend: friend);
        }
      });
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // state / native 的所有权在 main()，这里不能销毁，否则热重载会误关全部窗口。
    widget.native.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.native.rootView();
}

/// 画布模式入口（web / 非窗口化平台）。
///
/// 默认进入 [QDesktop]（可交互的应用桌面，不是九屏设计稿画廊）。
/// `#design` / `?mode=design` 才进入 [AppShell] 设计稿对照。
/// URL 预设：#login / #main / #friends / #menu / #bamboo / #chat /
/// #fm / #settings / #about / #demo，或 ?preset=名称。
class QQConceptApp extends StatefulWidget {
  const QQConceptApp({super.key, required this.state});

  final QAppState state;

  @override
  State<QQConceptApp> createState() => _QQConceptAppState();
}

class _QQConceptAppState extends State<QQConceptApp> {
  late bool _design;

  QAppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    final fragment = Uri.base.fragment.toLowerCase();
    _design =
        fragment == 'design' ||
        fragment == 'gallery' ||
        Uri.base.queryParameters['mode'] == 'design';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QQ 概念版 · Flutter 交互应用',
      // 全局禁用 Material 默认（系统样式）滚动条；
      // 可滚动区域一律使用 components/linked_scrollbar.dart 的自定义样式。
      scrollBehavior: const QNoSystemScrollbarBehavior(),
      theme: qqTheme(),
      home: _design
          ? AppShell(
              onExitDesign: () => setState(() => _design = false),
              initialShot: Uri.base.queryParameters['shot'],
            )
          : QDesktop(
              state: _state,
              onOpenDesign: () => setState(() => _design = true),
            ),
    );
  }
}

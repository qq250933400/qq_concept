import 'package:flutter/material.dart';

import 'components/linked_scrollbar.dart';
import 'core/app_state.dart';
import 'core/tokens.dart';
import 'core/widgets.dart';
import 'screens/about_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/friends_manager_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_panel.dart';
import 'screens/settings_screen.dart';

/// 九屏设计稿预览壳。
/// 设计稿每个 shot 是固定 1x 逻辑像素的窗口，这里 1:1 呈现，可拖拽平移 / 缩放查看。
class _Shot {
  const _Shot(this.name, this.note, this.w, this.h);

  final String name;
  final String note;
  final double w;
  final double h;
}

const List<_Shot> _shots = [
  _Shot('登录窗口', '太阳 / 云 / 叶丛动画', 372, 282),
  _Shot('聊天窗口', '细线按钮 · 功能图标 · 发送', 490, 435),
  _Shot('主面板 · 群组列表', '第二 tab · 群组行', 272, 645),
  _Shot('主面板 · 好友展开', '分组 + 好友行 + 滚动条', 272, 645),
  _Shot('主面板 · 齿轮菜单', '毛玻璃 blur(20px)', 272, 645),
  _Shot('主面板 · 最近消息', '竹叶背景 + 第三 tab 群消息', 272, 645),
  _Shot('好友管理', '木质桌面 · 气泡 · 照片卡', 959, 597),
  _Shot('设置窗口', '公共窗口样式（深色变体）', 268, 645),
  _Shot('关于窗口', '公共窗口样式（基准）', 357, 160),
];

/// 每个导航项对应的主面板状态；null 表示不是主面板。
/// [tab] 0 好友列表 / 1 群组列表 / 2 最近消息；menuOpen 打开齿轮菜单浮层。
class _PanelShot {
  const _PanelShot(this.tab, this.menuOpen);
  final int tab;
  final bool menuOpen;
}

const List<_PanelShot?> _shotPanels = [
  null,
  null,
  _PanelShot(1, false),
  _PanelShot(0, false),
  _PanelShot(0, true),
  _PanelShot(2, false),
  null,
  null,
  null,
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.onExitDesign,
    this.initialShot,
    required this.state,
  });

  /// 好友管理窗口需要状态对象；画廊里只用它做 1:1 静态对照。
  final QAppState state;

  /// 切回交互应用桌面（设计稿预览不再是默认入口）。
  final VoidCallback? onExitDesign;
  final String? initialShot;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 支持通过 URL hash 直达某个界面（用于无头截图逐屏核对）：
  /// #login / #chat / #main / #friends / #menu / #bamboo / #fm / #settings / #about
  static const Map<String, int> _hashIndex = {
    'login': 0,
    'chat': 1,
    'main': 2,
    'friends': 3,
    'menu': 4,
    'bamboo': 5,
    'fm': 6,
    'settings': 7,
    'about': 8,
  };

  late int _index;
  late int _tab;
  late bool _menuOpen;
  double _scale = 1;
  final TransformationController _viewer = TransformationController();
  final ScrollController _navCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final shot =
        widget.initialShot ??
        Uri.base.queryParameters['shot'] ??
        Uri.base.fragment.toLowerCase();
    _index = _hashIndex[shot.toLowerCase()] ?? 2;
    _tab = _shotPanels[_index]?.tab ?? 1;
    _menuOpen = _shotPanels[_index]?.menuOpen ?? false;
  }

  @override
  void dispose() {
    _navCtrl.dispose();
    _viewer.dispose();
    super.dispose();
  }

  void _select(int i) {
    setState(() {
      _index = i;
      final panel = _shotPanels[i];
      if (panel != null) {
        _tab = panel.tab;
        _menuOpen = panel.menuOpen;
      }
    });
  }

  /// 主面板内部的 tab 点击同步到左侧导航，保证状态一致。
  /// tab→shot：0 好友展开(3)、1 群组列表(2)、2 最近消息(5)。
  void _onTabChanged(int tab) {
    setState(() {
      _tab = tab;
      _menuOpen = false;
      _index = switch (tab) { 0 => 3, 2 => 5, _ => 2 };
    });
  }

  void _setScale(double s) {
    setState(() {
      _scale = s;
      _viewer.value = Matrix4.diagonal3Values(s, s, 1);
    });
  }

  Widget _screen() {
    switch (_index) {
      case 0:
        return const LoginScreen();
      case 1:
        return const ChatScreen();
      case 2:
      case 3:
      case 4:
      case 5:
        return MainPanel(
          tab: _tab,
          menuOpen: _menuOpen,
          onTabChanged: _onTabChanged,
          onDismissMenu: () => setState(() => _menuOpen = false),
          onMainMenuTap: () => setState(() => _menuOpen = !_menuOpen),
          staticPreview: true,
        );
      case 6:
        return FriendsManagerScreen(
          state: widget.state,
          staticPreview: true,
        );
      case 7:
        return const SettingsScreen();
      case 8:
        return const AboutScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shot = _shots[_index];
    return Scaffold(
      backgroundColor: QC.pageBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 232, child: _nav()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toolbar(shot),
                Expanded(child: _canvas()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav() => Container(
    color: const Color(0xFF1E2225),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF2C3236), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppIcon(size: 26),
                  const SizedBox(width: 10),
                  Text('QQ 概念版', style: QText.of(16, weight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Flutter 复刻 · 设计稿 V6.1',
                style: QText.of(11, color: const Color(0xFF8FA3AD)),
              ),
              const SizedBox(height: 4),
              Text(
                '9 个界面 · 1x 逻辑像素',
                style: QText.of(10.5, color: const Color(0xFF6F7F87)),
              ),
            ],
          ),
        ),
        Expanded(
          // 侧栏导航：右侧窄自定义滚动条（深色样式，替换系统默认滚动条）。
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _navCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _shots.length,
                  itemBuilder: (context, i) => _navItem(i, _shots[i]),
                ),
              ),
              LinkedScrollBar(controller: _navCtrl, step: 34),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF2C3236), width: 1)),
          ),
          child: Text(
            '桌面优先 · 单窗口\n纯 Flutter SDK，无第三方运行时依赖\n素材均为自绘矢量替身',
            style: QText.of(10, color: const Color(0xFF6F7F87)),
          ),
        ),
      ],
    ),
  );

  Widget _navItem(int i, _Shot shot) {
    final on = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () => _select(i),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: on ? const Color(0xFF2A3B45) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: Border(
              left: BorderSide(
                color: on ? QC.yellow : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${i + 1}. ${shot.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QText.of(
                  12.5,
                  color: on ? QC.white : const Color(0xFFB8C3C9),
                  weight: on ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${shot.w.toInt()} × ${shot.h.toInt()} px',
                style: QText.of(10, color: const Color(0xFF7E8A90)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(_Shot shot) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: Color(0xFF1E2225),
      border: Border(bottom: BorderSide(color: Color(0xFF2C3236), width: 1)),
    ),
    child: Row(
      children: [
        Text('设计稿对照', style: QText.of(14, weight: FontWeight.w700)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3B45),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('V6.1', style: QText.of(10.5, color: QC.yellow)),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            '${shot.name}  ·  ${shot.w.toInt()} × ${shot.h.toInt()} px  ·  ${shot.note}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QText.of(12, color: const Color(0xFF9FB0B8)),
          ),
        ),
        Text('缩放', style: QText.of(11, color: const Color(0xFF8FA3AD))),
        const SizedBox(width: 8),
        for (final s in const [0.5, 0.75, 1.0, 1.5])
          Padding(padding: const EdgeInsets.only(left: 4), child: _scaleBtn(s)),
        if (widget.onExitDesign != null) ...[
          const SizedBox(width: 14),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: widget.onExitDesign,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3A5663),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF6E98A8)),
              ),
              alignment: Alignment.center,
              child: Text('返回应用桌面', style: QText.of(11, color: QC.white)),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _scaleBtn(double s) {
    final on = (_scale - s).abs() < 0.001;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _setScale(s),
      child: Container(
        width: 44,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? const Color(0xFF3A5663) : const Color(0xFF2A3034),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: on ? const Color(0xFF6E98A8) : const Color(0xFF3A4247),
          ),
        ),
        child: Text(
          '${(s * 100).toInt()}%',
          style: QText.of(
            10.5,
            color: on ? QC.white : const Color(0xFF9FB0B8),
            weight: on ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _canvas() => Container(
    color: const Color(0xFF121417),
    child: InteractiveViewer(
      transformationController: _viewer,
      boundaryMargin: const EdgeInsets.all(600),
      minScale: 0.3,
      maxScale: 3,
      child: Center(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: _screen(),
        ),
      ),
    ),
  );
}

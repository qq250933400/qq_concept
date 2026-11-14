import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/tokens.dart';
import '../core/widgets.dart';
import 'native_windows.dart';
import 'window_content.dart';

/// QQ 概念版 · 交互应用桌面（默认入口）
///
/// [nativeMode] = false：单窗口内容纳多个 1x 逻辑像素的浮动窗口（web 回退）。
/// [nativeMode] = true：桌面只保留壁纸 / 顶栏 / 任务栏作为「控制台」，
/// 登录、主面板、聊天、好友管理、设置、关于全部由 [QNativeWindows]
/// 渲染到各自的 OS 级窗口里。两种模式共用 window_content.dart 的接线。
class QDesktop extends StatefulWidget {
  const QDesktop({
    super.key,
    required this.state,
    this.native,
    this.nativeMode = false,
    this.onOpenDesign,
  });

  final QAppState state;
  final QNativeWindows? native;

  /// 是否运行在 OS 级独立窗口模式（此时画布内不再绘制任何窗口）。
  final bool nativeMode;
  final VoidCallback? onOpenDesign;

  @override
  State<QDesktop> createState() => _QDesktopState();
}

class _QDesktopState extends State<QDesktop> {
  static const double _barH = 48;
  static const double _dockH = 46;

  QAppState get st => widget.state;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final area = Size(
      math.max(320, size.width),
      math.max(240, size.height - _barH - _dockH),
    );
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Scaffold(
        backgroundColor: QC.pageBg,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: const _WallpaperPainter()),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _barH,
              child: _topBar(),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: _barH,
              bottom: _dockH,
              child: Stack(children: _windowStack(area)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _dockH,
              child: _dock(),
            ),
            if (st.toast != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: _dockH + 18,
                child: IgnorePointer(child: _toast(st.toast!)),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 窗口栈
  // ---------------------------------------------------------------------------
  List<Widget> _windowStack(Size area) {
    final out = <Widget>[];
    // OS 级独立窗口模式：画布只当控制台，窗口内容全部交给原生 Window。
    if (widget.nativeMode) return out;
    for (final w in st.ordered) {
      if (w.minimized) continue;
      final winSize = qWindowSize(w.kind);
      // 面板翻到设置背面后，标题栏变矮（32），拖拽条同步收缩。
      final dragH = (w.kind == QWindowKind.panel && st.panelSettings)
          ? S.settingsBarH
          : qDragHeight(w.kind);
      final maxX = math.max(0.0, area.width - winSize.width);
      final maxY = math.max(0.0, area.height - winSize.height);
      final raw = w.pos ?? _defaultPos(w, area);
      final pos = Offset(raw.dx.clamp(0.0, maxX), raw.dy.clamp(0.0, maxY));
      out.add(
        Positioned(
          key: ValueKey('window:${w.id}'),
          left: pos.dx,
          top: pos.dy,
          child: Listener(
            onPointerDown: (_) => st.focus(w.id),
            child: Stack(
              children: [
                _screen(w, area),
                Positioned(
                  left: 0,
                  top: 0,
                  width: winSize.width,
                  height: dragH,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanUpdate: (d) => st.setWindowPos(
                      w.id,
                      Offset(
                        (pos.dx + d.delta.dx).clamp(0.0, maxX),
                        (pos.dy + d.delta.dy).clamp(0.0, maxY),
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  Offset _defaultPos(QWindow w, Size area) {
    final s = qWindowSize(w.kind);
    double cx(double x) =>
        math.max(0.0, math.min(math.max(0.0, area.width - s.width), x));
    double cy(double y) =>
        math.max(0.0, math.min(math.max(0.0, area.height - s.height), y));
    switch (w.kind) {
      case QWindowKind.login:
        return Offset(
          cx((area.width - s.width) / 2),
          cy((area.height - s.height) / 2 - 16),
        );
      case QWindowKind.panel:
        return Offset(cx(area.width - s.width - 70), cy(24));
      case QWindowKind.chat:
        return Offset(cx(area.width * .14), cy(area.height * .30));
      case QWindowKind.friendsManager:
        return Offset(
          cx((area.width - s.width) / 2),
          cy((area.height - s.height) / 2),
        );
      case QWindowKind.settings:
        return Offset(cx(area.width - s.width - 330), cy(64));
      case QWindowKind.about:
        return Offset(cx(area.width * .34), cy(24));
    }
  }

  Offset _centerPos(QWindow w, Size area) {
    final s = qWindowSize(w.kind);
    return Offset(
      math.max(0.0, (area.width - s.width) / 2),
      math.max(0.0, (area.height - s.height) / 2),
    );
  }

  void _winButton(QAppState state, QWindow w, QWinBtnKind k, Size area) {
    switch (k) {
      case QWinBtnKind.minimize:
        state.minimize(w.id);
      case QWinBtnKind.close:
      case QWinBtnKind.back:
        state.close(w.id);
      case QWinBtnKind.maximize:
        state.centerWindow(w.id, _centerPos(w, area));
      case QWinBtnKind.gear:
        // 齿轮 = 系统设置快捷键；主菜单由主面板左下角企鹅球打开。
        state.handleMenuAction('系统设置');
    }
  }

  // ---------------------------------------------------------------------------
  // 各窗口接线（画布桌面与 OS 独立窗口共用 window_content.dart）
  // ---------------------------------------------------------------------------
  Widget _screen(QWindow w, Size area) => buildQWindowContent(
    st,
    w,
    onWindowButton: (k) => _winButton(st, w, k, area),
  );


  // ---------------------------------------------------------------------------
  // 顶栏
  // ---------------------------------------------------------------------------
  Widget _topBar() => Container(
    height: _barH,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      color: Color(0xFF1E2225),
      border: Border(bottom: BorderSide(color: Color(0xFF2C3236), width: 1)),
    ),
    child: Row(
      children: [
        const AppIcon(size: 24),
        const SizedBox(width: 10),
        Text('QQ 概念版', style: QText.of(15, weight: FontWeight.w800)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3B45),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text('交互应用', style: QText.of(10.5, color: QC.yellow)),
        ),
        // OS 级独立窗口模式标识：所有窗口都由 WindowController 管理。
        if (widget.nativeMode) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF244A3A),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '独立窗口 · ${widget.native?.count ?? 0}',
              style: QText.of(10.5, color: const Color(0xFF8FE3A8)),
            ),
          ),
        ],
        const SizedBox(width: 18),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in QWindowKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _actionBtn(qWindowTitle(k), () => st.open(k)),
                  ),
                const SizedBox(width: 4),
                _actionBtn('打开全部', st.openAll),
                const SizedBox(width: 6),
                _actionBtn('重新登录', st.changeUser),
              ],
            ),
          ),
        ),
        if (widget.onOpenDesign != null) ...[
          const SizedBox(width: 10),
          _actionBtn('设计稿对照', widget.onOpenDesign!),
        ],
      ],
    ),
  );

  Widget _actionBtn(String label, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A3034),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A4247)),
      ),
      alignment: Alignment.center,
      child: Text(label, style: QText.of(11, color: const Color(0xFFB8C3C9))),
    ),
  );

  // ---------------------------------------------------------------------------
  // 任务栏
  // ---------------------------------------------------------------------------
  /// 两种模式共用同一份窗口注册表：画布模式点击 chip 改 z-order / minimized，
  /// 独立窗口模式由 QNativeWindows 监听到变化后 activate / setMinimized。
  Widget _dock() {
    final shown = st.windows;
    return Container(
      height: _dockH,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E2225),
        border: Border(top: BorderSide(color: Color(0xFF2C3236), width: 1)),
      ),
      child: Row(
        children: [
          Text('任务栏', style: QText.of(11, color: QC.yellow)),
          const SizedBox(width: 14),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => _dockChip(shown[i]),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            st.loggedIn ? '已登录 · ${st.account}' : '未登录',
            style: QText.of(11, color: const Color(0xFF8FA3AD)),
          ),
        ],
      ),
    );
  }


  Widget _dockChip(QWindow w) {
    final on = !w.minimized;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => on ? st.focus(w.id) : st.restore(w.id),
      onDoubleTap: () => st.minimize(w.id),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF2A3B45) : const Color(0xFF262B2E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: on ? const Color(0xFF6E98A8) : const Color(0xFF343B3F),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? QC.yellow : const Color(0xFF5A666C),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              // 面板翻到设置背面时，任务栏跟着改名。
              (w.kind == QWindowKind.panel && st.panelSettings)
                  ? '设置'
                  : qWindowTitle(w.kind, w.friend),
              style: QText.of(
                11,
                color: on ? QC.white : const Color(0xFF89959B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toast(String text) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xE61E2225),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A6570)),
      ),
      child: Text(text, style: QText.of(12.5, color: QC.white)),
    ),
  );
}

/// 深色壁纸：径向渐变 + 确定性淡竹叶，保证每次渲染一致。
class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = const RadialGradient(
      center: Alignment(0, -.45),
      radius: 1.35,
      colors: [Color(0xFF203A43), Color(0xFF101A20), Color(0xFF080D11)],
      stops: [0, .55, 1],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = bg);

    double seed = 11;
    double rnd() {
      seed = ((seed * 1103515245 + 12345).toInt() & 0x7fffffff).toDouble();
      return seed / 0x7fffffff;
    }

    final leaf = Paint()..color = const Color(0x0EFFFFFF);
    for (var i = 0; i < 84; i++) {
      final x = rnd() * size.width;
      final y = rnd() * size.height;
      final a = (rnd() * 140 - 70) * math.pi / 180;
      final s = .55 + rnd() * .9;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(a);
      canvas.scale(s, s);
      canvas.drawOval(const Rect.fromLTRB(-2.6, -24, 2.6, 2), leaf);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) => false;
}

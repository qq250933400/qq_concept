import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 主面板 ⇄ 设置页的 3D 卡片翻转。
///
/// 两块画布高度一致（645），宽度只差 4px（面板 272 / 设置 268），
/// 因此不需要改窗口尺寸：同一个窗口里绕 Y 轴翻转即可。
///
/// 动画分两半：
/// - t ∈ [0, .5]  正面（主面板）从 0° 转到 +90°，逐渐侧立消失；
/// - t ∈ [.5, 1]  反面（设置页）从 -90° 转到 0°，翻回正面。
/// 半程切换而不是让同一块卡片连续转 180°，避免出现镜像文字。
class PanelFlip extends StatefulWidget {
  const PanelFlip({
    super.key,
    required this.flipped,
    required this.front,
    required this.back,
    this.size = const Size(S.mainCanvasW, S.mainCanvasH),
    this.duration = const Duration(milliseconds: 460),
  });

  /// true = 显示反面（设置页）。
  final bool flipped;
  final Widget front;
  final Widget back;
  final Size size;
  final Duration duration;

  @override
  State<PanelFlip> createState() => _PanelFlipState();
}

class _PanelFlipState extends State<PanelFlip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.flipped ? 1 : 0,
  );

  static const Curve _curve = Curves.easeInOutCubic;

  @override
  void didUpdateWidget(covariant PanelFlip old) {
    super.didUpdateWidget(old);
    if (widget.flipped == old.flipped) return;
    if (widget.flipped) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _curve.transform(_c.value);
          final showBack = t >= .5;
          // 正面 0 → +90°；反面 -90° → 0°。
          final angle = showBack ? (t - 1) * math.pi : t * math.pi;
          final edgeOn = math.sin(angle.abs()); // 0 = 正面，1 = 侧立
          final card = showBack ? widget.back : widget.front;

          return Stack(
            children: [
              // 卡片本体：透视 + 绕 Y 轴旋转 + 侧立时轻微缩小（模拟远离）
              Positioned.fill(
                child: Align(
                  alignment: showBack ? Alignment.topCenter : Alignment.topLeft,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateY(angle)
                      ..scaleByDouble(1 - .035 * edgeOn, 1 - .035 * edgeOn, 1, 1),
                    child: SizedBox(
                      width: showBack ? S.settingsW : widget.size.width,
                      height: widget.size.height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _c.isAnimating,
                              child: card,
                            ),
                          ),
                          // 光照：越接近侧立越暗，贴着卡片一起转，不溢出阴影区
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Colors.black.withValues(
                                  alpha: .34 * edgeOn,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

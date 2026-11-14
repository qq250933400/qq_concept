import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// tab 页 3D 翻转组件（QQ 概念版主面板三 tab 通用）。
///
/// 用法：`TabFlip(index: tab, pages: [页0, 页1, 页2])`。
/// 方向由前后 tab 的索引决定：向右切换（索引增大）正向翻转，
/// 向左切换（索引减小）反向翻转。动画分两半：
/// 前半程旧页 0° → ±90° 侧立消失，后半程新页 ∓90° → 0° 翻正，
/// 半程切换而不是同一块卡片连续转 180°，避免出现镜像文字。
///
/// 页面骨架约定：页 widget 自身占 [S.mainWinW] × [S.bambooH]，
/// 内部列表用 `Positioned` 无界高度排布（超出部分由外层裁剪，
/// 不产生 overflow 异常）。
class TabFlip extends StatefulWidget {
  const TabFlip({
    super.key,
    required this.index,
    required this.pages,
    this.duration = const Duration(milliseconds: 460),
  });

  /// 当前选中的 tab 页索引（从左到右递增）。
  final int index;
  final List<Widget> pages;
  final Duration duration;

  @override
  State<TabFlip> createState() => _TabFlipState();
}

class _TabFlipState extends State<TabFlip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  /// 当前展示页 / 翻出页 / 方向（+1 正向，-1 反向）。
  int _current = 0;
  int _from = 0;
  int _dir = 1;

  static const Curve _curve = Curves.easeInOutCubic;

  @override
  void initState() {
    super.initState();
    _current = widget.index.clamp(0, widget.pages.length - 1);
  }

  @override
  void didUpdateWidget(covariant TabFlip old) {
    super.didUpdateWidget(old);
    final int next = widget.index.clamp(0, widget.pages.length - 1);
    if (next == _current && !_c.isAnimating) return;
    _from = _current;
    _current = next;
    _dir = next >= old.index ? 1 : -1;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final bool animating = _c.isAnimating;
        if (!animating) {
          return _card(widget.pages[_current], 0, false);
        }
        final double t = _curve.transform(_c.value);
        final bool showFrom = t < .5;
        final Widget page =
            showFrom ? widget.pages[_from] : widget.pages[_current];
        // 旧页 0 → ±90°；新页 ∓90° → 0°。
        final double angle =
            _dir * (showFrom ? t * math.pi : (t - 1) * math.pi);
        return _card(page, angle, true);
      },
    );
  }

  Widget _card(Widget page, double angle, bool animating) {
    final double edgeOn = math.sin(angle.abs());
    return SizedBox(
      width: S.mainWinW,
      height: S.bambooH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: S.mainWinW,
            // 不约束高度：列表页与旧实现一致，超出 bambooH 的部分由外层
            // 竹叶容器的 Clip.hardEdge 裁掉，不产生 overflow 异常。
            child: Transform(
              origin: Offset(S.mainWinW / 2, S.bambooH / 2),
              transform:
                  Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(angle)
                    ..scaleByDouble(1 - .035 * edgeOn, 1 - .035 * edgeOn, 1, 1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IgnorePointer(ignoring: animating, child: page),
                  // 光照：越接近侧立越暗。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .34 * edgeOn),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

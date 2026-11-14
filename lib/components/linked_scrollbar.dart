import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/widgets.dart';

/// 滚动条配色：深色用于主面板列表区，浅色用于聊天窗口等白底区域。
enum QScrollStyle {
  /// 主面板列表区（深蓝底轨道）。
  dark(
    track: Color(0xFF080F16),
    trackBorder: Color(0xFF0E1B24),
    arrow: Color(0xFF8D9AA2),
    thumb: Color(0xFFB6BFC5),
    thumb2: Color(0xFF7B868D),
  ),

  /// 聊天窗口 / 白底内容区（浅灰轨道）。
  light(
    track: Color(0xFFEDF1F4),
    trackBorder: Color(0xFFD9E1E6),
    arrow: Color(0xFF93A2AB),
    thumb: Color(0xFFC3CCD2),
    thumb2: Color(0xFF8D9AA2),
  );

  const QScrollStyle({
    required this.track,
    required this.trackBorder,
    required this.arrow,
    required this.thumb,
    required this.thumb2,
  });
  final Color track;
  final Color trackBorder;
  final Color arrow;
  final Color thumb;
  final Color thumb2;
}

/// 与列表联动的窄滚动条（宽 [S.vScrollW]，QQ 概念版列表区样式）。
///
/// - 拇指高度 = 视口高 / 内容总高（内容不足一屏时占满轨道）；
/// - 拇指位置随滚动偏移联动；拖拽拇指、点击上下箭头也可滚动列表。
class LinkedScrollBar extends StatelessWidget {
  const LinkedScrollBar({
    super.key,
    required this.controller,
    this.step = 56,
    this.style = QScrollStyle.dark,
  });

  final ScrollController controller;

  /// 箭头单次点击的滚动步长（约一行）。
  final double step;

  /// 深色（主面板）/浅色（白底内容区）两种配色。
  final QScrollStyle style;

  static const double _arrowPad = 8; // 箭头距上下边的留白
  static const double _arrowH = 4; // 箭头高
  static const double _thumbMinH = 30; // 拇指最小高度

  @override
  Widget build(BuildContext context) {
    // 自持固定宽度：避免在 Row 等无界宽度约束下被 LayoutBuilder+Stack
    // 撑满整行（轨道铺满、拇指错位到最左）。
    return SizedBox(
      width: S.vScrollW,
      child: Container(
        decoration: BoxDecoration(
          color: style.track,
          border: Border(left: BorderSide(color: style.trackBorder, width: 1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double h = constraints.maxHeight;
            final double trackTop = _arrowPad * 2 + _arrowH; // 20
            final double trackLen = h - trackTop * 2;
            return AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                double content = 1;
                double viewport = 1;
                double offset = 0;
                if (controller.hasClients &&
                    controller.position.hasContentDimensions) {
                  content =
                      controller.position.maxScrollExtent +
                      controller.position.viewportDimension;
                  viewport = controller.position.viewportDimension;
                  offset = controller.position.pixels;
                }
                final double frac = content <= viewport
                    ? 0
                    : (offset / (content - viewport)).clamp(0.0, 1.0);
                final double thumbH = content <= viewport
                    ? trackLen
                    : (trackLen * viewport / content).clamp(
                        _thumbMinH,
                        trackLen,
                      );
                final double thumbTop =
                    trackTop + frac * (trackLen - thumbH).clamp(0.0, trackLen);

                return Stack(
                  children: [
                    _arrow(
                      top: _arrowPad,
                      dir: QTriDir.up,
                      onTap: () => _scrollBy(-step),
                    ),
                    _arrow(
                      top: h - _arrowPad - _arrowH,
                      dir: QTriDir.down,
                      onTap: () => _scrollBy(step),
                    ),
                    // 轨道拇指：拖动即滚动。
                    Positioned(
                      left: 2,
                      top: thumbTop,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) =>
                            _scrollBy(d.delta.dy * (content / trackLen)),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            width: 9,
                            height: thumbH,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: hg([style.thumb, style.thumb2]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _scrollBy(double delta) {
    if (!controller.hasClients) return;
    final pos = controller.position;
    controller.jumpTo((pos.pixels + delta).clamp(0.0, pos.maxScrollExtent));
  }

  Widget _arrow({
    required double top,
    required QTriDir dir,
    required VoidCallback onTap,
  }) => Positioned(
    left: 3,
    top: top,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: QTriangle(
          width: 8,
          height: _arrowH,
          dir: dir,
          color: style.arrow,
        ),
      ),
    ),
  );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 主面板列表区整体背景：深青径向渐变 + 确定性竹叶叶簇（无外部素材）。
///
/// 作为三个 tab 页共用的「背景布」铺在列表区容器内，页内容浮于其上。
class BambooBackdrop extends StatelessWidget {
  const BambooBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.2, -0.1), // 60% 45%
            radius: .9,
            colors: [QC.bambooRadial, QC.bambooBg, QC.bambooBg],
            stops: [0, .78, 1],
          ),
        ),
      ),
      IgnorePointer(child: CustomPaint(painter: BambooLeavesPainter())),
    ],
  );
}

/// 竹叶叶簇画笔（近景锐利 / 中景竹枝 / 远景虚化三层）。
class BambooLeavesPainter extends CustomPainter {
  const BambooLeavesPainter();

  static final Path _leaf = Path()
    ..moveTo(0, 0)
    ..cubicTo(22, -11, 58, -14, 100, -2)
    ..cubicTo(58, 11, 22, 9, 0, 0)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final shaderA = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8AD96A), Color(0xFF3E9B3C), Color(0xFF176B24)],
      stops: [0, .55, 1],
    ).createShader(const Rect.fromLTWH(0, -14, 100, 25));
    final shaderB = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF67C455), Color(0xFF176622)],
      stops: [0, 1],
    ).createShader(const Rect.fromLTWH(0, -14, 100, 25));

    final Paint a = Paint()..shader = shaderA;
    final Paint b = Paint()..shader = shaderB;
    final Paint aBlur = Paint()
      ..shader = shaderA
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final Paint bBlur = Paint()
      ..shader = shaderB
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    Paint far(Color c) => Paint()
      ..color = c
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.save();
    // CSS: translateY(20px) scale(1.12)，transform-origin 56% 42%（相对 272x334）
    canvas.translate(0, 20);
    canvas.translate(272 * .56, 334 * .42);
    canvas.scale(1.12);
    canvas.translate(-272 * .56, -334 * .42);

    // 远景虚化叶
    _drawLeaf(canvas, 150, 60, 35, 1.9, far(const Color(0xFF1D5A26)));
    _drawLeaf(canvas, 40, 40, 140, 1.6, far(const Color(0xFF1A5222)));
    _drawLeaf(canvas, 200, 330, -150, 1.7, far(const Color(0xFF1B5523)));

    // 中景竹枝
    canvas.drawPath(
      Path()
        ..moveTo(170, 0)
        ..cubicTo(160, 80, 150, 160, 158, 260),
      Paint()
        ..color = const Color(0xD94A9A42)
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke,
    );

    // 近景锐利叶簇
    _drawLeaf(canvas, 118, 96, 24, 1.35, a);
    _drawLeaf(canvas, 132, 128, 55, 1.2, b);
    _drawLeaf(canvas, 108, 150, 12, 1.5, aBlur);
    _drawLeaf(canvas, 150, 190, 78, 1.3, b);
    _drawLeaf(canvas, 126, 232, 30, 1.55, a);
    _drawLeaf(canvas, 158, 262, 65, 1.25, b);
    _drawLeaf(canvas, 120, 296, 18, 1.4, aBlur);
    _drawLeaf(canvas, 230, 210, -40, 1.3, bBlur);
    _drawLeaf(canvas, 150, 44, 48, 1.55, a);
    _drawLeaf(canvas, 168, 76, 18, 1.7, b);
    _drawLeaf(canvas, 120, 62, -28, 1.45, aBlur);

    canvas.restore();
  }

  void _drawLeaf(Canvas c, double x, double y, double deg, double s, Paint p) {
    c.save();
    c.translate(x, y);
    c.rotate(deg * math.pi / 180);
    c.scale(s);
    c.drawPath(_leaf, p);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant BambooLeavesPainter old) => false;
}

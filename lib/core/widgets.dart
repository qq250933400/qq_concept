import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/window_chrome.dart';

import 'tokens.dart';

/// 窗口按钮种类（对应设计稿里 15/16px 细线 SVG，绝不使用字体字符图标）
enum QWinBtnKind { gear, back, minimize, maximize, close }

/// 三角形方向
enum QTriDir { up, down, right, left }

/// ============================================================================
/// 细线窗口按钮
/// ============================================================================
class LineWinButton extends StatelessWidget {
  const LineWinButton({
    super.key,
    required this.kind,
    this.size = S.dlgBtnSize,
    this.color = QC.dlgBtn,
    this.strokeWidth = 1.4,
    this.onTap,
  });

  final QWinBtnKind kind;
  final double size;
  final Color color;
  final double strokeWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LineWinBtnPainter(kind, color, strokeWidth)),
    );
    return onTap == null
        ? btn
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: btn,
          );
  }
}

class _LineWinBtnPainter extends CustomPainter {
  const _LineWinBtnPainter(this.kind, this.color, this.strokeWidth);

  final QWinBtnKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 15, size.height / 15);
    final p = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (kind) {
      case QWinBtnKind.minimize:
        canvas.drawLine(const Offset(3.5, 8), const Offset(11.5, 8), p);
        break;
      case QWinBtnKind.maximize:
        canvas.drawRect(const Rect.fromLTRB(4, 4, 11, 11), p);
        break;
      case QWinBtnKind.close:
        canvas.drawLine(const Offset(4.5, 4.5), const Offset(10.5, 10.5), p);
        canvas.drawLine(const Offset(10.5, 4.5), const Offset(4.5, 10.5), p);
        break;
      case QWinBtnKind.back:
        canvas.drawLine(const Offset(12, 8), const Offset(4, 8), p);
        canvas.drawLine(const Offset(7.5, 4.5), const Offset(4, 8), p);
        canvas.drawLine(const Offset(7.5, 11.5), const Offset(4, 8), p);
        break;
      case QWinBtnKind.gear:
        // 8 齿齿轮：旋转矩形 + 圆心
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.translate(7.5, 7.5);
          canvas.rotate(i * 3.14159265 / 4);
          canvas.drawRect(const Rect.fromLTRB(-1.1, -7.2, 1.1, -5.0), fill);
          canvas.restore();
        }
        canvas.drawCircle(const Offset(7.5, 7.5), 3.6, fill);
        canvas.drawCircle(
          const Offset(7.5, 7.5),
          1.5,
          Paint()
            ..color = QC.dlgBarTop
            ..style = PaintingStyle.fill,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _LineWinBtnPainter old) =>
      old.kind != kind || old.color != color || old.strokeWidth != strokeWidth;
}

class WindowButtonRow extends StatelessWidget {
  const WindowButtonRow({
    super.key,
    this.kinds = const [QWinBtnKind.minimize, QWinBtnKind.close],
    this.gap = 13,
    this.size = S.dlgBtnSize,
    this.color = QC.dlgBtn,
    this.strokeWidth = 1.4,
    this.onTap,
  });

  final List<QWinBtnKind> kinds;
  final double gap;
  final double size;
  final Color color;
  final double strokeWidth;
  final void Function(QWinBtnKind kind)? onTap;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final k in kinds)
        Padding(
          padding: EdgeInsets.only(right: gap),
          child: LineWinButton(
            kind: k,
            size: size,
            color: color,
            strokeWidth: strokeWidth,
            onTap: onTap == null ? null : () => onTap!(k),
          ),
        ),
    ],
  );
}

/// ============================================================================
/// 公共窗口外框（.dlg / .dlgbar / .dlgbtns / .dlgfoot）
/// body 使用整个窗口坐标系（从窗口左上 0,0 起），由调用方自行 Stack 绝对定位。
/// ============================================================================
class DlgFrame extends StatelessWidget {
  const DlgFrame({
    super.key,
    required this.width,
    required this.height,
    required this.title,
    required this.body,
    this.dark = false,
    this.centerTitle = false,
    this.barHeight = S.dlgBarH,
    this.buttons = const [QWinBtnKind.minimize, QWinBtnKind.close],
    this.footer,
    this.background,
    this.onButtonTap,
  });

  final double width;
  final double height;
  final String title;
  final Widget body;
  final bool dark;
  final bool centerTitle;
  final double barHeight;
  final List<QWinBtnKind> buttons;
  final Widget? footer;
  final Color? background;
  final void Function(QWinBtnKind kind)? onButtonTap;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (dark ? QC.settingsBg : QC.aboutBg);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: QC.dlgBorder, width: 1),
        borderRadius: BorderRadius.circular(S.dlgRadius),
        boxShadow: qOuterShadow(QShadow.dlg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: body),
          // 标题栏
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: barHeight,
            child: Container(
              decoration: BoxDecoration(
                gradient: vg(
                  [QC.dlgBarTop, QC.dlgBarMid, QC.dlgBarBottom],
                  const [0, .52, 1],
                ),
                border: const Border(
                  bottom: BorderSide(color: QC.dlgBarBorder, width: 1),
                ),
              ),
            ),
          ),
          if (!centerTitle) const Positioned(left: 8, top: 4, child: AppIcon()),
          // 居中标题用 left+right 拉伸定宽（不能同时给 width，违反
          // Positioned 的 left/right/width 互斥断言，debug 下会红屏）。
          Positioned(
            left: centerTitle ? 0 : 38,
            right: centerTitle ? 0 : null,
            top: 5,
            child: Text(
              title,
              textAlign: centerTitle ? TextAlign.center : TextAlign.left,
              style: centerTitle
                  ? QText.of(17, weight: FontWeight.w800, letterSpacing: 1)
                  : QText.of(15, weight: FontWeight.w700),
            ),
          ),
          Positioned(
            right: 9,
            top: 7,
            child: WindowButtonRow(kinds: buttons, onTap: onButtonTap),
          ),
          if (footer != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: S.dlgFootH,
              child: Container(
                decoration: BoxDecoration(
                  gradient: vg([QC.dlgFootTop, QC.dlgFootBottom]),
                  border: const Border(
                    top: BorderSide(color: Color(0x80FFFFFF), width: 1),
                  ),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 10),
                child: footer,
              ),
            ),
        ],
      ),
    );
  }
}

/// 标题栏左上 22x22 应用图标（自绘矢量替身，非腾讯素材）
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      gradient: vg([const Color(0xFF8FB6D8), const Color(0xFF3A6A9C)]),
      border: Border.all(color: const Color(0xFFDBE8F2), width: 1),
    ),
    clipBehavior: Clip.antiAlias,
    child: CustomPaint(painter: _AppIconPainter()),
  );
}

class _AppIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final p = Paint()..color = const Color(0xFFF4F7FA);
    canvas.drawOval(const Rect.fromLTRB(4, 3, 16, 18), p);
    canvas.drawCircle(const Offset(10, 6), 3.6, p);
    final eye = Paint()..color = const Color(0xFF2B3A41);
    canvas.drawCircle(const Offset(8.5, 5.6), .7, eye);
    canvas.drawCircle(const Offset(11.5, 5.6), .7, eye);
    canvas.drawPath(
      Path()
        ..moveTo(8.6, 8)
        ..lineTo(11.4, 8)
        ..lineTo(10, 9.6)
        ..close(),
      Paint()..color = const Color(0xFFE8A13A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ============================================================================
/// 金属按钮 / 米色按钮 / 胶囊输入框
/// ============================================================================
class MetalButton extends StatelessWidget {
  const MetalButton({
    super.key,
    required this.label,
    this.dark = false,
    this.width = S.metalBtnMinW,
    this.height = S.metalBtnH,
    this.onTap,
  });

  final String label;
  final bool dark;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final widget = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: dark ? QC.metalDarkBorder : QC.metalBorder,
          width: 1,
        ),
        gradient: dark
            ? vg(
                [QC.metalDarkTop, QC.metalDarkMid, QC.metalDarkBottom],
                const [0, .65, 1],
              )
            : vg(
                [QC.metalTop, QC.metalMid1, QC.metalMid2, QC.metalBottom],
                const [0, .47, .52, 1],
              ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: QText.metal.copyWith(
          shadows: const [
            Shadow(
              color: Color(0xBF000000),
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
      ),
    );
    return onTap == null
        ? widget
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: widget,
          );
  }
}

class BeigeButton extends StatelessWidget {
  const BeigeButton({
    super.key,
    required this.label,
    required this.width,
    this.height = S.loginBtnH,
    this.radius = const BorderRadius.all(Radius.circular(4)),
    this.leading,
    this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final BorderRadius radius;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final widget = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: QC.beigeBorder, width: 1),
        gradient: vg(
          [QC.beigeTop, QC.beigeMid, QC.beigeBottom],
          const [0, .60, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) leading!,
          if (leading != null) const SizedBox(width: 4),
          Text(label, style: QText.beige),
        ],
      ),
    );
    return onTap == null
        ? widget
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: widget,
          );
  }
}

class PillField extends StatelessWidget {
  const PillField({
    super.key,
    required this.width,
    this.height = S.loginFieldH,
    this.child,
    this.bottom = QC.pillBottom,
  });

  final double width;
  final double height;
  final Widget? child;
  final Color bottom;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(height / 2),
      gradient: vg([QC.pillTop, bottom]),
      border: Border.all(color: const Color(0x33787878), width: 1),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        // 模拟 inset 顶部阴影
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
        if (child != null) Positioned.fill(child: child!),
      ],
    ),
  );
}

/// ============================================================================
/// 毛玻璃面板（对应 CSS backdrop-filter: blur(20px)）
/// Flutter 的 sigma 约为 CSS blur 半径的一半，故 sigma=10 对应 CSS 20px。
/// ============================================================================
class BlurPanel extends StatelessWidget {
  const BlurPanel({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.radiusTop = S.menuRadiusTop,
    this.radiusBottom = S.menuRadiusBottom,
    this.sigma = S.menuBlurSigma,
    this.background = const [QC.menuA, QC.menuB, QC.menuC],
    this.borderColor = QC.menuBorder,
  });

  final double width;
  final double height;
  final Widget child;
  final double radiusTop;
  final double radiusBottom;
  final double sigma;
  final List<Color> background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(radiusTop),
      bottom: Radius.circular(radiusBottom),
    ),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: vg(background, const [0, .52, 1]),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: child,
      ),
    ),
  );
}

/// ============================================================================
/// 小图标 / 小控件
/// ============================================================================
class QTriangle extends StatelessWidget {
  const QTriangle({
    super.key,
    required this.width,
    required this.height,
    this.dir = QTriDir.right,
    this.color = QC.grpArrow,
  });

  final double width;
  final double height;
  final QTriDir dir;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _TrianglePainter(dir, color)),
  );
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.dir, this.color);
  final QTriDir dir;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    switch (dir) {
      case QTriDir.right:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, size.height / 2)
          ..lineTo(0, size.height)
          ..close();
        break;
      case QTriDir.left:
        path
          ..moveTo(size.width, 0)
          ..lineTo(0, size.height / 2)
          ..lineTo(size.width, size.height)
          ..close();
        break;
      case QTriDir.down:
        path
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width / 2, size.height)
          ..close();
        break;
      case QTriDir.up:
        path
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..close();
        break;
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) =>
      old.dir != dir || old.color != color;
}

/// 银白扁平信封 + V 形封口（17x15）
class EnvelopeIcon extends StatelessWidget {
  const EnvelopeIcon({super.key, this.width = 17, this.height = 15});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _EnvelopePainter()),
  );
}

class _EnvelopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 17, size.height / 15);
    final grad = vg([QC.envTop, QC.envMid, QC.envBottom], const [0, .55, 1]);
    final body = Paint()
      ..shader = grad.createShader(const Rect.fromLTRB(0, 0, 17, 15));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(0, 0, 17, 15),
        const Radius.circular(1.5),
      ),
      body,
    );
    final line = Paint()
      ..color = const Color(0xFF7A8B96)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, .8)
        ..lineTo(8.5, 8.2)
        ..lineTo(17, .8),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 15)
        ..lineTo(6, 9.5)
        ..lineTo(11, 9.5)
        ..lineTo(17, 15),
      line..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 搜索框右侧：无底座的粗浮雕十字（18x18）
class PlusIcon extends StatelessWidget {
  const PlusIcon({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _PlusPainter()),
  );
}

class _PlusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 18, size.height / 18);
    Path cross(double dx, double dy) => Path()
      ..moveTo(9 + dx, 2.5 + dy)
      ..lineTo(9 + dx, 15.5 + dy)
      ..moveTo(2.5 + dx, 9 + dy)
      ..lineTo(15.5 + dx, 9 + dy);
    Paint stroke(Color c, double w, double a) => Paint()
      ..color = c.withValues(alpha: a)
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(cross(0, 1.2), stroke(QC.plusShade, 4.4, .55));
    canvas.drawPath(cross(0, 0), stroke(QC.plusCross, 4.4, 1));
    canvas.drawPath(cross(-.4, -.6), stroke(const Color(0xFFFFFFFF), 1, .34));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 绿色状态圆点
class GreenDot extends StatelessWidget {
  const GreenDot({super.key, this.size = 13, this.check = true});
  final double size;
  final bool check;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.3, -.4),
        colors: [QC.greenDotTop, QC.greenDotMid, QC.greenDotBottom],
        stops: [0, .6, 1],
      ),
    ),
    alignment: Alignment.center,
    child: check
        ? Text(
            '✓',
            style: QText.of(
              size * .62,
              weight: FontWeight.w900,
              color: QC.white,
            ),
          )
        : null,
  );
}

/// 绿色勾选复选框（登录「记住密码」）
class GreenCheckBox extends StatelessWidget {
  const GreenCheckBox({
    super.key,
    this.size = 16,
    this.checked = true,
    this.onTap,
  });
  final double size;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: QC.checkBorder, width: 1.5),
        gradient: checked ? vg([QC.checkTop, QC.checkBottom]) : null,
        color: checked ? null : const Color(0x33000000),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: checked
          ? Text(
              '✓',
              style: QText.of(12, weight: FontWeight.w900, color: QC.white),
            )
          : null,
    );
    return onTap == null
        ? box
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: box,
          );
  }
}

/// 新闻条左侧圆形球 + 米色企鹅剪影（自绘替身）
class PenguinBall extends StatelessWidget {
  const PenguinBall({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const RadialGradient(
        center: Alignment(-.24, -.4),
        colors: [Color(0xFF5C6165), Color(0xFF202325)],
        stops: [0, .75],
      ),
      border: Border.all(color: const Color(0x1FFFFFFF), width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0xB3000000),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: CustomPaint(painter: _PenguinPainter()),
  );
}

class _PenguinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 30, size.height / 30);
    final beige = Paint()..color = const Color(0xFFEFE8C8);
    canvas.drawOval(const Rect.fromLTRB(6, 6, 24, 27), beige);
    canvas.drawCircle(const Offset(15, 9), 7, beige);
    final eye = Paint()..color = const Color(0xFF3A3A30);
    canvas.drawCircle(const Offset(12.4, 8), 1.2, eye);
    canvas.drawCircle(const Offset(17.6, 8), 1.2, eye);
    canvas.drawPath(
      Path()
        ..moveTo(13, 11)
        ..lineTo(17, 11)
        ..lineTo(15, 13.6)
        ..close(),
      Paint()..color = const Color(0xFFE8A13A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(7, 21, 23, 24),
        const Radius.circular(1.5),
      ),
      Paint()..color = const Color(0xFFB03A2A),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 好友头像占位（自绘矢量替身，40x40）
class AvatarPlaceholder extends StatelessWidget {
  const AvatarPlaceholder({
    super.key,
    this.size = S.friendAvatar,
    required this.bg,
    this.skin = const Color(0xFFE8C49C),
    this.hair = const Color(0xFF35231A),
  });

  final double size;
  final Color bg;
  final Color skin;
  final Color hair;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: QAvatarPainter(bg, skin, hair)),
    );
}

/// 自绘矢量头像（40x40 基准，可缩放）。公开给注册窗预览与主面板相框复用。
class QAvatarPainter extends CustomPainter {
  const QAvatarPainter(this.bg, this.skin, this.hair);
  final Color bg;
  final Color skin;
  final Color hair;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 40);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = bg);
    canvas.drawOval(const Rect.fromLTRB(11, 8, 29, 28), Paint()..color = skin);
    canvas.drawPath(
      Path()
        ..moveTo(10, 17)
        ..cubicTo(10, 7, 30, 7, 30, 17)
        ..lineTo(30, 13)
        ..cubicTo(27, 6, 13, 6, 10, 13)
        ..close(),
      Paint()..color = hair,
    );
    final eye = Paint()..color = const Color(0xFF2B211A);
    canvas.drawCircle(const Offset(16.5, 18), 1.3, eye);
    canvas.drawCircle(const Offset(23.5, 18), 1.3, eye);
    canvas.drawPath(
      Path()
        ..moveTo(7, 40)
        ..cubicTo(9, 30, 14, 27, 20, 27)
        ..cubicTo(26, 27, 31, 30, 33, 40)
        ..close(),
      Paint()..color = const Color(0xD2E8EEF2),
    );
  }

  @override
  bool shouldRepaint(covariant QAvatarPainter old) =>
      old.bg != bg || old.skin != skin || old.hair != hair;
}

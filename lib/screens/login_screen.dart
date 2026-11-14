import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 登录窗口（ui-v4.html V6.1）
///
/// 画布 372x282，自下而上分层：
///   z0 太阳/光晕（窗口之前）→ z1 窗口 → z2 叶丛（压住标题栏上沿）
///   → z3 窗口细线按钮（压在叶之上）→ z3 云（ClipRect 裁到 42px）。
/// 叶丛与云各由一个 CustomPainter 一次性绘制，动画由三个 Controller 驱动。
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.account,
    this.password,
    this.remember,
    this.onAccountChanged,
    this.onPasswordChanged,
    this.onRememberChanged,
    this.onLogin,
    this.onRegister,
    this.onMinimize,
    this.onClose,
  });

  /// 不传任何回调时，渲染与 V6.1 设计稿完全一致（gallery 模式）。
  final String? account;
  final String? password;
  final bool? remember;
  final ValueChanged<String>? onAccountChanged;
  final ValueChanged<String>? onPasswordChanged;
  final ValueChanged<bool>? onRememberChanged;
  final VoidCallback? onLogin;
  final VoidCallback? onRegister;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const InputDecoration _fieldDecoration = InputDecoration(
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    isDense: true,
    contentPadding: EdgeInsets.zero,
    filled: false,
  );

  late final TextEditingController _accountCtl;
  late final TextEditingController _passwordCtl;
  late final AnimationController _sway;
  late final AnimationController _floatCtl;
  late final AnimationController _cloud;
  late final _LeafPainter _leafPainter;
  late final _CloudPainter _cloudPainter;

  @override
  void initState() {
    super.initState();
    _accountCtl = TextEditingController(text: widget.account ?? '');
    _passwordCtl = TextEditingController(text: widget.password ?? '');
    _accountCtl.addListener(_syncAccount);
    _passwordCtl.addListener(_syncPassword);
    _sway = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (S.leafSwaySeconds * 1000).round()),
    )..repeat();
    _floatCtl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (S.leafFloatSeconds * 1000).round()),
    )..repeat();
    _cloud = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (S.cloudScrollSeconds * 1000).round()),
    )..repeat();
    _leafPainter = _LeafPainter(
      sway: _sway,
      float: _floatCtl,
      leaves: _genLeaves(),
    );
    _cloudPainter = _CloudPainter(_cloud);
  }

  void _syncAccount() {
    // 只同步到状态层；不再 setState 重建（空态马赛克已移除，
    // 逐键重建会造成输入时光标位置跳动）。
    widget.onAccountChanged?.call(_accountCtl.text);
  }

  void _syncPassword() {
    widget.onPasswordChanged?.call(_passwordCtl.text);
  }

  @override
  void didUpdateWidget(covariant LoginScreen old) {
    super.didUpdateWidget(old);
    if (widget.account != null &&
        widget.account != old.account &&
        widget.account != _accountCtl.text) {
      _accountCtl.text = widget.account!;
    }
    if (widget.password != null &&
        widget.password != old.password &&
        widget.password != _passwordCtl.text) {
      _passwordCtl.text = widget.password!;
    }
  }

  @override
  void dispose() {
    _accountCtl.removeListener(_syncAccount);
    _passwordCtl.removeListener(_syncPassword);
    _accountCtl.dispose();
    _passwordCtl.dispose();
    _sway.dispose();
    _floatCtl.dispose();
    _cloud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 372,
      height: 282,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // z0 太阳：径向渐变圆盘 + 黄色光晕；窗口顶 y=42 遮住其下部约 1/3。
          // 所有装饰层都必须 IgnorePointer：CustomPaint 在 painter 未重写
          // hitTest 时默认吸收命中，叶层会盖住账号输入框导致无法聚焦输入。
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: CustomPaint(
                painter: const _SunPainter(),
                size: const Size(S.loginCanvasW, 130),
              ),
            ),
          ),

          // z1 窗口
          Positioned(left: 0, top: S.loginWinTop, child: _window()),

          // z2 叶丛：top 24，画在窗口之前；横带自 x=86 起、右端上翘收尾，
          // 因此不压住 left20 的标题文字，也不压住右上细线按钮。
          Positioned(
            left: 0,
            top: S.loginLeafTop,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _leafPainter,
                size: const Size(S.loginCanvasW, 130),
              ),
            ),
          ),

          // z3 细线窗口按钮：HTML 中 .winbtns z-index:3 在叶丛之上，保持可见
          Positioned(
            right: 12 + 16 + 14,
            top: S.loginWinTop + 9,
            child: LineWinButton(
              kind: QWinBtnKind.minimize,
              size: 16,
              color: QC.loginWbtn,
              strokeWidth: 1.5,
              onTap: widget.onMinimize,
            ),
          ),
          Positioned(
            right: 12,
            top: S.loginWinTop + 9,
            child: LineWinButton(
              kind: QWinBtnKind.close,
              size: 16,
              color: QC.loginWbtn,
              strokeWidth: 1.5,
              onTap: widget.onClose,
            ),
          ),

          // z3 云：ClipRect 裁到 42px，26s linear 无缝右→左循环，压在叶之上
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: ClipRect(
                child: CustomPaint(
                  painter: _cloudPainter,
                  size: const Size(S.loginCanvasW, S.loginCloudClipH),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 窗口内部使用窗口坐标系（左上 0,0），caller 已把窗口放到 canvas y=42。
  Widget _window() {
    return Container(
      width: S.loginCanvasW,
      height: S.loginWinH,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(S.loginRadius),
        gradient: vg(
          [QC.loginWinTop, QC.loginWinMid, QC.loginWinBottom],
          const [0, .34, 1],
        ),
        boxShadow: qOuterShadow(QShadow.loginWin),
      ),
      child: Stack(
        children: [
          // 标题栏 34px，上两角圆角 10
          Positioned(
            left: 0,
            top: 0,
            width: S.loginCanvasW,
            height: S.loginTitleH,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(S.loginRadius),
                ),
                gradient: vg(
                  [QC.loginTitleTop, QC.loginTitleMid, QC.loginTitleBottom],
                  const [0, .55, 1],
                ),
              ),
            ),
          ),
          // 顶部 1px 白色高光 rgba(255,255,255,.10)
          Positioned(
            left: 0,
            top: 0,
            width: S.loginCanvasW,
            height: 1,
            child: const ColoredBox(color: Color(0x1AFFFFFF)),
          ),
          // 标题
          Positioned(
            left: 20,
            top: 9,
            child: Text('QQ 概念版', style: QText.loginTitle),
          ),

          // 表单：label + 6 + field + 12 + label + 6 + field
          Positioned(
            left: S.loginFormLeft,
            top: S.loginFormTop,
            width: 238,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('帐号：', style: QText.lab),
                const SizedBox(height: 6),
                PillField(
                  width: S.loginFieldW,
                  height: S.loginFieldH,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: 20,
                            bottom: 1,
                          ),
                          child: TextField(
                            controller: _accountCtl,
                            style: QText.of(
                              12.5,
                              color: const Color(0xFF23272A),
                            ),
                            cursorColor: const Color(0xFF4A5155),
                            cursorWidth: 1.2,
                            cursorHeight: 12,
                            // 空态占位：普通灰色 placeholder 文案。
                            decoration: _fieldDecoration.copyWith(
                              hintText: '请输入账号',
                              hintStyle: QText.of(
                                12.5,
                                color: const Color(0xFFA7B0B5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 下拉小三角（5px 半宽 / 6px 高）
                      const Positioned(
                        right: 8,
                        top: 6,
                        child: QTriangle(
                          width: 10,
                          height: 6,
                          dir: QTriDir.down,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('密码：', style: QText.lab),
                const SizedBox(height: 6),
                PillField(
                  width: S.loginFieldW,
                  height: S.loginFieldH,
                  // PillField 内部已经用 Positioned.fill 包裹 child，
                  // 这里不能再套一层 Positioned（会触发 ParentDataWidget 冲突）。
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      right: 8,
                      bottom: 1,
                    ),
                    child: TextField(
                      controller: _passwordCtl,
                      obscureText: true,
                      style: QText.of(12.5, color: const Color(0xFF23272A)),
                      cursorColor: const Color(0xFF4A5155),
                      cursorWidth: 1.2,
                      cursorHeight: 12,
                      decoration: _fieldDecoration.copyWith(
                        hintText: '请输入密码',
                        hintStyle: QText.of(
                          12.5,
                          color: const Color(0xFFA7B0B5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 记住密码（V6.1：与密码框间距由 8px 加到 16px）
          Positioned(
            right: 76,
            top: S.loginCbTop,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GreenCheckBox(
                  size: 16,
                  checked: widget.remember ?? true,
                  onTap: widget.onRememberChanged == null
                      ? null
                      : () => widget.onRememberChanged!(
                          !(widget.remember ?? true),
                        ),
                ),
                const SizedBox(width: 7),
                Text('记住密码', style: QText.of(12)),
              ],
            ),
          ),

          // 底部三按钮，均 bottom:32 高 26
          Positioned(
            left: S.loginRegLeft,
            bottom: S.loginBtnBottom,
            child: BeigeButton(
              label: '注册新帐号',
              width: S.loginRegW,
              height: S.loginBtnH,
              radius: BorderRadius.circular(4),
              onTap: widget.onRegister,
            ),
          ),
          // 状态 + 登录：紧贴的组合按钮，中间仅一条竖线感
          Positioned(
            left: S.loginStatusLeft,
            bottom: S.loginBtnBottom,
            child: Stack(
              children: [
                BeigeButton(
                  label: '',
                  width: S.loginStatusW,
                  height: S.loginBtnH,
                  radius: const BorderRadius.horizontal(
                    left: Radius.circular(4),
                  ),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const GreenDot(size: 13),
                      const SizedBox(width: 4),
                      QTriangle(
                        width: 8,
                        height: 5,
                        dir: QTriDir.down,
                        color: const Color(0xFF333333),
                      ),
                    ],
                  ),
                ),
                // 抹掉右边框，使与「登录」之间只剩一条竖线
                Positioned(
                  right: 0,
                  top: 1,
                  bottom: 1,
                  child: Container(
                    width: 1,
                    decoration: BoxDecoration(
                      gradient: vg(
                        [QC.beigeTop, QC.beigeMid, QC.beigeBottom],
                        const [0, .60, 1],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: S.loginLoginLeft,
            bottom: S.loginBtnBottom,
            child: BeigeButton(
              label: '登录',
              width: S.loginLoginW,
              height: S.loginBtnH,
              radius: const BorderRadius.horizontal(right: Radius.circular(4)),
              onTap: widget.onLogin,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 叶丛数据：与 ui-v4.html 末尾脚本逐行一致
// 注意：浏览器里 seed*1103515245 走 IEEE754 双精度，故此处 seed 用 double
// 推进并 .toInt() 后掩码，才能复现设计稿里每一片叶子的位置。
// ============================================================================
class _Leaf {
  const _Leaf(
    this.x,
    this.y,
    this.s,
    this.rot,
    this.kind, [
    this.floatIndex = -1,
  ]);

  final double x;
  final double y;
  final double s;
  final double rot;
  final int kind; // 0 深叶 / 1 亮叶 / 2 白花
  final int floatIndex; // >=0 表示该叶做独立浮动
}

List<_Leaf> _genLeaves() {
  double seed = 7;
  double rnd() {
    seed = ((seed * 1103515245 + 12345).toInt() & 0x7fffffff).toDouble();
    return seed / 0x7fffffff;
  }

  final out = <_Leaf>[];

  // 背景深叶：x=86..384 step4，中间厚两端薄，右端稀疏并上翘收尾
  for (double x = 86; x <= 384; x += 4) {
    final bulge = math.max(0.0, 1 - (x - 220).abs() / 175);
    double y = 5 + rnd() * (10 + 24 * bulge);
    if (x > 315) {
      if (rnd() < .42) continue;
      y = 15 - (x - 315) * .11 + rnd() * 4;
    }
    final s = .5 + rnd() * .28;
    final rot = (rnd() * 70 - 35).round().toDouble();
    out.add(_Leaf(x, y, s, rot, 0));
  }

  // 前景亮叶：x=90..380 step5
  for (double x = 90; x <= 380; x += 5) {
    final bulge2 = math.max(0.0, 1 - (x - 220).abs() / 170);
    double y = 7 + rnd() * (10 + 26 * bulge2);
    if (x > 315) {
      if (rnd() < .42) continue;
      y = 16 - (x - 315) * .11 + rnd() * 4;
    }
    final s = .48 + rnd() * .28;
    final rot = (rnd() * 80 - 40).round().toDouble();
    out.add(_Leaf(x, y, s, rot, 1));
  }

  // 中央下垂簇 48 片
  for (var i = 0; i < 48; i++) {
    final cx = 120 + rnd() * 150;
    final cy = 30 + rnd() * 40;
    final s = .45 + rnd() * .3;
    final rot = (rnd() * 90 - 45).round().toDouble();
    out.add(_Leaf(cx, cy, s, rot, 1));
  }

  // 白花 6 朵
  for (var i = 0; i < 6; i++) {
    final fx = 70 + rnd() * 280;
    final fy = 18 + rnd() * 38;
    final fs = .3 + rnd() * .16;
    out.add(_Leaf(fx, fy, fs, 0, 2));
  }

  // HTML 中未被停用的 6 片独立浮动叶（.leaf-float）
  const floats = <List<double>>[
    [96, 38, 1.05, 0],
    [124, 55, 1.15, 0],
    [158, 62, 1.25, 0],
    [206, 69, 1.30, 8],
    [248, 64, 1.20, 20],
    [310, 50, 1.40, 0],
  ];
  for (var i = 0; i < floats.length; i++) {
    out.add(
      _Leaf(floats[i][0], floats[i][1], floats[i][2], floats[i][3], 1, i),
    );
  }
  return out;
}

// ============================================================================
// z0 太阳
// ============================================================================
class _SunPainter extends CustomPainter {
  const _SunPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    const c = Offset(S.loginSunCx, S.loginSunCy);

    // r40 黄色光晕：#F7C948 从 .8 透明到 0
    final glow = RadialGradient(
      colors: [
        QC.sunGlow.withValues(alpha: .8),
        QC.sunGlow.withValues(alpha: 0),
      ],
      stops: const [0, 1],
    );
    canvas.drawCircle(
      c,
      S.loginSunGlowR,
      Paint()
        ..shader = glow.createShader(
          Rect.fromCircle(center: c, radius: S.loginSunGlowR),
        ),
    );

    // r27 圆盘：#FFF3B0 @0 → #FBCF4A @45% → #E8951D @100%，中心约 42%/40%
    const disc = RadialGradient(
      center: Alignment(-.16, -.20),
      radius: .60,
      colors: [QC.sunCore, QC.sunMid, QC.sunEdge],
      stops: [0, .45, 1],
    );
    canvas.drawCircle(
      c,
      S.loginSunR,
      Paint()
        ..shader = disc.createShader(
          Rect.fromCircle(center: c, radius: S.loginSunR),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _SunPainter old) => false;
}

// ============================================================================
// z2 叶丛：一个 CustomPainter 绘制全部叶片（约 232 个 use 元素对应的可见叶）
// ============================================================================
class _LeafPainter extends CustomPainter {
  _LeafPainter({required this.sway, required this.float, required this.leaves})
    : super(repaint: Listenable.merge([sway, float]));

  final Animation<double> sway;
  final Animation<double> float;
  final List<_Leaf> leaves;

  // 亮叶的两套渐变，shader 建在叶片局部坐标里，随 canvas 变换一起旋转/缩放
  static final Shader _gradA = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [QC.leaf1Top, QC.leaf1Bottom],
  ).createShader(const Rect.fromLTRB(-5.2, -17.7, 5.2, .7));

  static final Shader _gradB = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [QC.leaf2Top, QC.leaf2Bottom],
  ).createShader(const Rect.fromLTRB(-5.2, -17.7, 5.2, .7));

  @override
  void paint(Canvas canvas, Size size) {
    // SVG viewBox 372x130 的裁剪（在摆动之前，不随旋转转动）
    canvas.clipRect(Offset.zero & size);

    // leafSway：0/100% = -1.1°，50% = +1.1°，ease-in-out，绕 (186,0)
    final t = sway.value;
    final e = t < .5
        ? Curves.easeInOut.transform(t * 2)
        : Curves.easeInOut.transform((1 - t) * 2);
    final angle = (-1.1 + 2.2 * e) * math.pi / 180;

    canvas.save();
    canvas.translate(186, 0);
    canvas.rotate(angle);
    canvas.translate(-186, 0);

    for (final lf in leaves) {
      double dy = 0;
      double drot = 0;
      if (lf.floatIndex >= 0) {
        // leafFloat：translateY(-3px) + rotate(2.5deg)，5.2s，逐片错相
        final ft = (float.value + lf.floatIndex * .17) % 1.0;
        final fe = (1 - math.cos(2 * math.pi * ft)) / 2;
        dy = -3 * fe;
        drot = 2.5 * fe;
      }
      _drawLeaf(canvas, lf, dy, drot);
    }
    canvas.restore();
  }

  void _drawLeaf(Canvas c, _Leaf lf, double dy, double drot) {
    c.save();
    c.translate(lf.x, lf.y + dy);
    c.scale(lf.s, lf.s);
    c.rotate((lf.rot + drot) * math.pi / 180);

    if (lf.kind == 2) {
      _drawFlower(c);
    } else if (lf.kind == 0) {
      // 深叶：3 片 #2A7A2C / #205F23 / #236826
      const dark = [QC.leafDark1, QC.leafDark2, QC.leafDark3];
      for (var i = 0; i < 3; i++) {
        c.save();
        if (i == 1) c.rotate(60 * math.pi / 180);
        if (i == 2) c.rotate(-60 * math.pi / 180);
        c.drawOval(
          const Rect.fromLTRB(-5.6, -18.1, 5.6, 1.1),
          Paint()..color = dark[i],
        );
        c.restore();
      }
    } else {
      // 亮叶：3 片，第一片 #84D466→#2F8A2A，另两片 #5FBE50→#217A25
      for (var i = 0; i < 3; i++) {
        c.save();
        if (i == 1) c.rotate(60 * math.pi / 180);
        if (i == 2) c.rotate(-60 * math.pi / 180);
        c.drawOval(
          const Rect.fromLTRB(-5.2, -17.7, 5.2, .7),
          Paint()..shader = (i == 0 ? _gradA : _gradB),
        );
        c.restore();
      }
    }
    c.restore();
  }

  void _drawFlower(Canvas c) {
    final petal = Paint()..color = QC.flower;
    for (var i = 0; i < 5; i++) {
      c.save();
      c.rotate(i * 72 * math.pi / 180);
      c.drawOval(const Rect.fromLTRB(-2.6, -10.2, 2.6, -1.8), petal);
      c.restore();
    }
    c.drawCircle(Offset.zero, 2.6, Paint()..color = QC.flowerCore);
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) => false;
}

// ============================================================================
// z3 云：三团灰白云，复制两份相隔 372，26s linear 无缝循环
// ============================================================================
class _Puff {
  const _Puff(this.cx, this.cy, this.rx, this.ry);
  final double cx;
  final double cy;
  final double rx;
  final double ry;
}

const _cloudGroups = <List<_Puff>>[
  [_Puff(96, 16, 20, 8), _Puff(110, 11, 15, 8), _Puff(84, 12, 12, 6)],
  [
    _Puff(146, 18, 30, 12),
    _Puff(170, 12, 20, 10),
    _Puff(126, 22, 18, 8),
    _Puff(158, 7, 15, 8),
  ],
  [_Puff(212, 20, 18, 7), _Puff(226, 16, 12, 5)],
];

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.scroll) : super(repaint: scroll);

  final Animation<double> scroll;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.save();
    canvas.translate(-S.cloudScrollDistance * scroll.value, 0);
    _drawSet(canvas, 0);
    _drawSet(canvas, S.cloudScrollDistance);
    canvas.restore();
  }

  void _drawSet(Canvas c, double dx) {
    for (var gi = 0; gi < _cloudGroups.length; gi++) {
      final path = Path();
      Rect? bounds;
      for (final p in _cloudGroups[gi]) {
        final r = Rect.fromCenter(
          center: Offset(p.cx + dx, p.cy + S.loginCloudUseY),
          width: p.rx * 2,
          height: p.ry * 2,
        );
        path.addOval(r);
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
      // 每团整体纵向渐变，再套一层高斯柔化（对应 SVG 的 soft / soft2）
      c.drawPath(
        path,
        Paint()
          ..shader = vg([QC.cloudTop, QC.cloudBottom]).createShader(bounds!)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, gi == 1 ? 1.1 : 2.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) => false;
}

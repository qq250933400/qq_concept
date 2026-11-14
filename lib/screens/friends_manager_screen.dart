import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 好友管理木质桌面 959x597（ui-v4.html V6.1 / #fm）
///
/// 分区：标题栏 0..30 / 第二栏 30..62 / 黄线 62..64 / 木桌 64..597。
/// 木纹、暖光、暗角统一由 _WoodPainter 一次绘制；气泡球、照片卡、信息卡、
/// 柱状图、滚动条均为 canvas 1x 绝对坐标，超出底部的部分由窗口裁剪。
class FriendsManagerScreen extends StatelessWidget {
  const FriendsManagerScreen({super.key, this.onButtonTap, this.onFriendTap});

  final void Function(QWinBtnKind kind)? onButtonTap;
  final ValueChanged<String>? onFriendTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: S.fmW,
      height: S.fmH,
      child: Container(
        decoration: BoxDecoration(
          color: QC.woodBottom,
          borderRadius: BorderRadius.circular(4),
          boxShadow: qOuterShadow(QShadow.dlg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 木桌（最底层）
            Positioned(
              left: 0,
              top: 64,
              width: S.fmW,
              height: S.fmWoodH,
              child: CustomPaint(
                painter: _WoodPainter(),
                size: Size(S.fmW, S.fmWoodH),
              ),
            ),
            // 标题栏
            Positioned(
              left: 0,
              top: 0,
              width: S.fmW,
              height: S.fmTitleH,
              child: _titleBar(),
            ),
            // 第二栏（含搜索框）
            Positioned(
              left: 0,
              top: S.fmTitleH,
              width: S.fmW,
              height: S.fmBar2H,
              child: _bar2(),
            ),
            // 黄线
            Positioned(
              left: 0,
              top: 62,
              width: S.fmW,
              height: S.fmYLineH,
              child: ColoredBox(color: QC.fmYLine),
            ),

            // 7 个分组气泡球（top 相对 canvas）
            _bubble(132, 186, 82, '全部好友', '(292)', _blue),
            _bubble(112, 252, 78, '高中挚友', '(83)', _orange),
            _bubble(
              86,
              316,
              100,
              '大学好友',
              '(66)',
              _green,
              nameSize: 15,
              countSize: 14,
              ring: true,
              blur: 14,
              dy: 8,
            ),
            _bubble(92, 398, 76, 'WOW好友', '(12)', _red),
            _bubble(126, 462, 70, '亲戚家人', '(9)', _teal),
            _bubble(162, 520, 76, '已知网友', '(116)', _blue),
            _bubble(212, 584, 72, '淘宝好友', '(6)', _orange, opacity: .9),

            // 13 张照片卡
            _fcard(305, 120, -8, '吴芸', const Color(0xFFA9BFD0)),
            _fcard(478, 120, 7, '陈华', const Color(0xFF5A4636)),
            _fcard(290, 236, -10, '葛辰', const Color(0xFF4A5A7A)),
            _fcard(298, 318, -6, '黄晓梅', const Color(0xFFE8C9A8)),
            _fcard(318, 352, 4, '张亚方（会长）', const Color(0xFFD8A8B8)),
            _fcard(404, 296, -7, '谢俊展', const Color(0xFF8A4A3A)),
            _fcard(398, 352, 6, '何俊', const Color(0xFFE8A8B8)),
            _fcard(470, 376, -4, '刘邦', const Color(0xFFE8D8B8)),
            _fcard(618, 292, 6, '财管姜瑜', const Color(0xFF4A6A8A)),
            _fcard(772, 286, 2, 'dc', const Color(0xFFD8C8A8)),
            _fcard(748, 370, -3, '张晓玲', const Color(0xFF3A5A7A)),
            _fcard(646, 398, -11, '潘荣香', const Color(0xFFF2B8C4)),
            _fcard(806, 186, 8, '成杏阳', const Color(0xFFB8C8D8), opacity: .75),

            // 右上信息卡 / 右下柱状图 / 底部滚动条
            Positioned(left: 806, top: 16, child: _infoCard()),
            Positioned(left: 806, top: 404, child: _chart()),
            Positioned(left: 300, top: 584, child: _hscroll()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 标题栏 / 第二栏
  // ---------------------------------------------------------------------------
  Widget _titleBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: vg(
          [QC.fmTitleTop, QC.fmTitleMid, QC.fmTitleBottom],
          const [0, .6, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(left: 8, top: 5, child: PenguinBall(size: 19)),
          Positioned(
            left: 34,
            top: 7,
            child: Text(
              'QQ好友管理',
              style: QText.of(12.5, weight: FontWeight.w700),
            ),
          ),
          Positioned(
            right: 12,
            top: 8,
            child: WindowButtonRow(
              kinds: const [
                QWinBtnKind.minimize,
                QWinBtnKind.maximize,
                QWinBtnKind.close,
              ],
              gap: 13,
              size: 15,
              color: QC.dlgBtn,
              strokeWidth: 1.4,
              onTap: onButtonTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar2() {
    return Container(
      decoration: BoxDecoration(gradient: vg([QC.fmBar2Top, QC.fmBar2Bottom])),
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 8,
            child: Text('大学好友', style: QText.of(14, weight: FontWeight.w800)),
          ),
          // 搜索框：设计稿中位于 .bar2 内 top5（canvas 绝对 y=35）
          Positioned(left: 150, top: 5, child: _searchBox()),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Container(
      width: 640,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: vg([const Color(0xFFF4F4F4), const Color(0xFFD9DDE0)]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // inset 0 1px 2px rgba(0,0,0,.3) 用顶部暗渐变近似
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: vg([
                  const Color(0x4D000000),
                  const Color(0x00000000),
                ]),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 3,
            child: Text(
              '输入英文或者拼音进行搜索',
              style: QText.of(12, color: const Color(0xFF9AA1A6)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 分组气泡球
  // ---------------------------------------------------------------------------
  static const List<Color> _blue = [
    Color(0xFF8B9BD0),
    Color(0xFF5D6DA6),
    Color(0xFF414E7E),
  ];
  static const List<Color> _orange = [
    Color(0xFFEDA05A),
    Color(0xFFCF6F24),
    Color(0xFF9C4D14),
  ];
  static const List<Color> _green = [
    Color(0xFF8CBB5E),
    Color(0xFF5F9237),
    Color(0xFF416B23),
  ];
  static const List<Color> _red = [
    Color(0xFFD05A4A),
    Color(0xFFA53424),
    Color(0xFF742015),
  ];
  static const List<Color> _teal = [
    Color(0xFF7FB3CB),
    Color(0xFF4A86A3),
    Color(0xFF2F5F76),
  ];

  Widget _bubble(
    double left,
    double top,
    double size,
    String name,
    String count,
    List<Color> colors, {
    double nameSize = 13,
    double countSize = 12,
    bool ring = false,
    double opacity = 1,
    double blur = 10,
    double dy = 6,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-.24, -.44),
              colors: colors,
              stops: const [0, .55, 1],
            ),
            border: ring
                ? Border.all(color: const Color(0x40FFFFFF), width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: const Color(0x73000000),
                blurRadius: blur,
                offset: Offset(0, dy),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: QText.of(nameSize, weight: FontWeight.w700),
              ),
              Text(
                count,
                textAlign: TextAlign.center,
                style: QText.of(countSize, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 好友照片卡
  // ---------------------------------------------------------------------------
  Widget _fcard(
    double left,
    double top,
    double deg,
    String name,
    Color bg, {
    double opacity = 1,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: S.fCardSize,
      height: S.fCardSize,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: deg * math.pi / 180,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onFriendTap == null ? null : () => onFriendTap!(name),
            child: Container(
              width: S.fCardSize,
              height: S.fCardSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(S.fCardRadius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 7,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(S.fCardRadius),
                child: Stack(
                  children: [
                    // 相框
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [QC.frTop, QC.frBottom, QC.frBottom],
                            stops: const [0, .7, 1],
                          ),
                        ),
                      ),
                    ),
                    // 照片：4px 内边距、圆角 10，用头像替身
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AvatarPlaceholder(size: 58, bg: bg),
                        ),
                      ),
                    ),
                    // 绿色名牌：严格收在卡片内
                    Positioned(
                      left: 6,
                      bottom: 4,
                      width: S.plateW,
                      height: S.plateH,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: vg([QC.plateTop, QC.plateBottom]),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: QText.of(10, weight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 右上信息卡
  // ---------------------------------------------------------------------------
  Widget _infoCard() {
    return Container(
      width: 146,
      height: 136,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xE0080E14),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: const Color(0x99000000),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0x12FFFFFF),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AvatarPlaceholder(size: 44, bg: const Color(0xFF5A4636)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '陈华(635478153)',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QText.of(11.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: const Color(0x29FFFFFF)),
          const SizedBox(height: 6),
          Text('个性签名：', style: QText.of(11, color: const Color(0xFFE8EDF0))),
          Text(
            '你真美。Silverlight.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QText.of(10, color: const Color(0xFFC9D4DC)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 右下男女比例 3D 柱状图
  // ---------------------------------------------------------------------------
  Widget _chart() {
    return SizedBox(
      width: 146,
      height: 176,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 底座（skewX -14°）
          Positioned(
            left: 6,
            bottom: 0,
            width: 134,
            height: 16,
            child: Transform(
              transform: Matrix4.skewX(-14 * math.pi / 180),
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: vg([
                    const Color(0xFFB9BEC4),
                    const Color(0xFF8F969C),
                  ]),
                ),
              ),
            ),
          ),
          // 蓝柱
          Positioned(
            left: 34,
            bottom: 12,
            width: 15,
            height: 112,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
                gradient: hg(
                  [
                    const Color(0xFF5D6F92),
                    const Color(0xFF42506B),
                    const Color(0xFF303A4E),
                  ],
                  const [0, .6, 1],
                ),
              ),
            ),
          ),
          // 红柱
          Positioned(
            left: 78,
            bottom: 12,
            width: 15,
            height: 158,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
                gradient: hg(
                  [
                    const Color(0xFFA8493A),
                    const Color(0xFF8A2F22),
                    const Color(0xFF5F1E15),
                  ],
                  const [0, .6, 1],
                ),
              ),
            ),
          ),
          // 三个剪影小人
          Positioned(
            left: 35,
            bottom: 124,
            width: 13,
            height: 26,
            child: CustomPaint(
              painter: const _FigurePainter(
                color: Color(0xFF7FA8C9),
                female: false,
              ),
            ),
          ),
          Positioned(
            left: 78,
            bottom: 170,
            width: 13,
            height: 26,
            child: CustomPaint(
              painter: const _FigurePainter(
                color: Color(0xFFC9757F),
                female: true,
              ),
            ),
          ),
          Positioned(
            left: 116,
            bottom: 16,
            width: 13,
            height: 26,
            child: CustomPaint(
              painter: const _FigurePainter(
                color: Color(0xFFD8B23A),
                female: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hscroll() {
    return Container(
      width: 400,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: const Color(0x59E6E8EB),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 40,
            top: 1,
            width: 280,
            height: 6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: const Color(0xFFDFE3E6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
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

/// 木纹：底色 + 竖板缝 + 细横纹 + 左侧椭圆暖光 + 椭圆暗角
class _WoodPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1) 底色纵向渐变
    final base = Paint()
      ..shader = vg(
        [QC.woodTop, QC.woodMid, QC.woodBottom],
        const [0, .7, 1],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), base);

    // 2) 细横纹：每 9px 一轮 rgba(255,220,170,.018) 0..2px
    final grain = Paint()..color = const Color(0x05FFDCAA);
    for (double y = 0; y < h; y += 9) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 2), grain);
    }

    // 3) 竖板缝：每 158px 一轮
    final seamDark = Paint()..color = const Color(0x80000000);
    final seamLight = Paint()..color = const Color(0x0DFFEBC8);
    for (double x = 0; x < w; x += 158) {
      canvas.drawRect(Rect.fromLTWH(x + 76, 0, 2, h), seamDark);
      canvas.drawRect(Rect.fromLTWH(x + 78, 0, 1, h), seamLight);
    }

    // 4) 左侧椭圆暖光 ellipse 30x260 at (40, 40%)，rgba(90,55,30,.25)→透明@70%
    canvas.save();
    canvas.translate(40, h * .4);
    canvas.scale(30 / 260, 1);
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          260,
          const [Color(0x405A371E), Color(0x005A371E)],
          const [0, .7],
          ui.TileMode.clamp,
        ),
    );
    canvas.restore();

    // 5) 最外层椭圆暗角：中心 45% 45%，透明@40% → rgba(0,0,0,.42)@100%
    canvas.save();
    canvas.translate(w * .45, h * .45);
    canvas.scale(1, h / w);
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          w / 2,
          const [Color(0x00000000), Color(0x6B000000)],
          const [.4, 1],
          ui.TileMode.clamp,
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WoodPainter old) => false;
}

/// 柱状图上的 13x26 剪影小人（复刻 clip-path polygon，坐标归一化）
class _FigurePainter extends CustomPainter {
  const _FigurePainter({required this.color, required this.female});

  final Color color;
  final bool female;

  static const List<double> _male = [
    .5,
    0,
    .64,
    .05,
    .64,
    .12,
    .60,
    .14,
    .60,
    .44,
    .72,
    .50,
    .72,
    1,
    .28,
    1,
    .28,
    .50,
    .40,
    .44,
    .40,
    .14,
    .36,
    .12,
    .36,
    .05,
  ];
  static const List<double> _female = [
    .5,
    0,
    .68,
    .08,
    .58,
    .34,
    .56,
    1,
    .44,
    1,
    .42,
    .34,
    .32,
    .08,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pts = female ? _female : _male;
    final path = Path();
    for (var i = 0; i < pts.length; i += 2) {
      final x = pts[i] * size.width;
      final y = pts[i + 1] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FigurePainter old) =>
      old.color != color || old.female != female;
}

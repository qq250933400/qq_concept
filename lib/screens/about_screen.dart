import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 关于窗口 357x160（ui-v4.html V6.1 / #about）
///
/// 复用公共浅色 .dlg 外框（标题栏 AppIcon +「关于」、右上细线按钮、
/// footer 右对齐「确定」），body 自绘浅色 dlgbody 渐变与三行版权文字。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.onButtonTap, this.onOk});

  final void Function(QWinBtnKind kind)? onButtonTap;
  final VoidCallback? onOk;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: S.aboutW,
      height: S.aboutH,
      child: DlgFrame(
        width: S.aboutW,
        height: S.aboutH,
        title: '关于',
        buttons: const [QWinBtnKind.minimize, QWinBtnKind.close],
        onButtonTap: onButtonTap,
        footer: MetalButton(label: '确定', onTap: onOk),
        body: Stack(
          children: [
            // dlgbody：top30 到底部 35 之间，顶部 1px 白色高光
            Positioned(
              left: 0,
              right: 0,
              top: S.dlgBarH,
              height: S.aboutH - S.dlgBarH - S.dlgFootH,
              child: Container(
                decoration: BoxDecoration(
                  gradient: vg(
                    [QC.dlgBodyTop, QC.dlgBodyMid, QC.dlgBodyBottom],
                    const [0, .7, 1],
                  ),
                  border: const Border(
                    top: BorderSide(color: Color(0x73FFFFFF), width: 1),
                  ),
                ),
              ),
            ),
            // 三行内容（坐标相对窗口，left28 top50）
            Positioned(
              left: 28,
              top: 50,
              child: Text(
                'QQ 概念版 1.1.7.1\n'
                '腾讯公司 版权所有\n'
                'Copyright© 1998-2010 Tencent. All Rights Reserved.',
                style: QText.aboutTxt.copyWith(height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

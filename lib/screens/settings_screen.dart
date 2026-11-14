import 'package:flutter/material.dart';

import '../core/tokens.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 设置窗口 268x645（ui-v4.html V6.1 / #settings）
///
/// 复用公共深色 .dlg 外框；body 内所有控件按窗口左上 (0,0) 绝对定位。
/// 单选框选中态按设计稿与 v6_settings-stage.png：上方「按 Ctrl + Enter 键」选中。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.values = const <String, bool>{},
    this.onToggle,
    this.onSave,
    this.onCancel,
    this.onButtonTap,
  });

  /// key: autoStart / alwaysOnTop / autoHide / sound / sendCtrlEnter
  final Map<String, bool> values;
  final void Function(String key, bool value)? onToggle;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;
  final void Function(QWinBtnKind kind)? onButtonTap;

  bool _v(String key, bool fallback) => values[key] ?? fallback;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: S.settingsW,
      height: S.settingsH,
      child: DlgFrame(
        width: S.settingsW,
        height: S.settingsH,
        title: 'QQ',
        dark: true,
        centerTitle: true,
        barHeight: 32,
        onButtonTap: onButtonTap,
        buttons: const [
          QWinBtnKind.back,
          QWinBtnKind.minimize,
          QWinBtnKind.close,
        ],
        body: Stack(
          children: [
            // 深色背景（留 1px 给外框描边）
            Positioned(
              left: 1,
              top: 1,
              right: 1,
              bottom: 1,
              child: ColoredBox(color: QC.settingsBg),
            ),
            // 两个分组标题
            Positioned(left: 13, top: 58, child: Text('基本设置', style: _heading)),
            Positioned(
              left: 13,
              top: 258,
              child: Text('会话窗口消息中发送消息', style: _heading),
            ),
            // 4 个复选框项
            _checkItem(96, '开机时自动启动', 'autoStart', false),
            _checkItem(134, '始终保持在其它窗口前端', 'alwaysOnTop', false),
            _checkItem(172, '停靠桌面边缘时自动隐藏', 'autoHide', false),
            _checkItem(210, '开启声音提示', 'sound', false),
            // 2 个单选框项
            _radioItem(296, '按 Ctrl + Enter 键', 'sendCtrlEnter', true),
            _radioItem(334, '按 Enter 键', 'sendCtrlEnter', false),
            // 底部按钮
            Positioned(
              left: 44,
              bottom: 17,
              child: MetalButton(
                label: '保存',
                dark: true,
                width: 72,
                height: 25,
                onTap: onSave,
              ),
            ),
            Positioned(
              left: 146,
              bottom: 17,
              child: MetalButton(
                label: '取消',
                dark: true,
                width: 72,
                height: 25,
                onTap: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final TextStyle _heading = QText.of(
    14,
    color: QC.settingsHeading,
    weight: FontWeight.w700,
  );

  Widget _checkItem(double top, String label, String key, bool fallback) {
    final on = _v(key, fallback);
    return Positioned(
      left: 14,
      top: top,
      width: 240,
      height: 22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle == null ? null : () => onToggle!(key, !on),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                border: Border.all(color: QC.cbBorder, width: 1.5),
                gradient: vg([QC.cbTop, QC.cbBottom]),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: on
                  ? Text(
                      '✓',
                      style: QText.of(
                        11,
                        weight: FontWeight.w900,
                        color: QC.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            Text(label, style: QText.settingsOpt),
          ],
        ),
      ),
    );
  }

  Widget _radioItem(double top, String label, String key, bool value) {
    final on = _v(key, true) == value;
    return Positioned(
      left: 14,
      top: top,
      width: 240,
      height: 22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle == null ? null : () => onToggle!(key, value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: QC.cbBorder, width: 1.5),
                color: const Color(0xFF061824),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: on
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(-.3, -.4),
                          colors: [
                            QC.greenDotTop,
                            QC.greenDotMid,
                            QC.greenDotBottom,
                          ],
                          stops: [0, .65, 1],
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            Text(label, style: QText.settingsOpt),
          ],
        ),
      ),
    );
  }
}

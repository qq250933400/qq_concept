import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/avatars.dart';
import '../core/profile.dart';
import '../core/tokens.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 注册窗口（独立 OS 窗口，480x470）。
///
/// 概念版设计稿没有注册窗，这里沿用「关于窗口」的浅色 .dlg 外框语言：
/// 深蓝绿标题栏 + 浅色米色 dlgbody 渐变 + 米色 footer + 金属按钮，
/// 与登录窗的米色胶囊形成同一浅色系，而不是好友管理浮层的深色玻璃。
/// 表单文本全部留在本 State：注册窗与登录窗同为 OS 窗口，逐键 notify
/// 会让登录窗 / 主面板每敲一个字重建一次。
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.state,
    this.onButtonTap,
  });

  final QAppState state;

  /// 窗口标题栏按钮（最小化 / 关闭）。
  final void Function(QWinBtnKind kind)? onButtonTap;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _account = TextEditingController();
  final TextEditingController _nickname = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _passwordConfirm = TextEditingController();

  QGender _gender = QGender.secret;
  int _avatarIndex = 0;

  /// 本地表单校验错误（与服务端错误分开：后者由 state.registerError 带回）。
  String? _localError;

  @override
  void dispose() {
    _account.dispose();
    _nickname.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  void _submit() {
    final st = widget.state;
    if (st.registerBusy) return;
    FocusScope.of(context).unfocus();
    final reg = QRegistration(
      account: _account.text,
      nickname: _nickname.text,
      password: _password.text,
      passwordConfirm: _passwordConfirm.text,
      gender: _gender,
      avatarIndex: _avatarIndex,
    );
    final error = reg.validate();
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() => _localError = null);
    // 注册成功后登录流程会关闭本窗口，无需在这里处理。
    st.submitRegistration(reg);
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    // TextField 需要 Material 祖先：独立 OS 窗口与画布模式下窗口根都可能
    // 没有 Material，这里包一层透明 Material 兜底（幂等，不画背景）。
    return Material(
      type: MaterialType.transparency,
      child: DlgFrame(
        width: S.regW,
        height: S.regH,
        title: '注册新帐号',
        buttons: const [QWinBtnKind.minimize, QWinBtnKind.close],
        onButtonTap: widget.onButtonTap,
        footer: _footer(st),
        body: Stack(
          children: [
            // 浅色 dlgbody：标题栏下沿到 footer 上沿，顶部 1px 白色高光
            //（与 AboutScreen 同一套渐变 / 高光）。
            Positioned(
              left: 0,
              right: 0,
              top: S.dlgBarH,
              bottom: S.dlgFootH,
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
            Positioned(
              left: 20,
              right: 20,
              top: S.dlgBarH + 14,
              bottom: S.dlgFootH + 10,
              child: AnimatedBuilder(
                animation: st,
                builder: (context, _) => _form(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form() {
    final st = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _preview(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_account, '登录帐号（3~32 位字母 / 数字）'),
                  const SizedBox(height: 9),
                  _field(_nickname, '用户昵称'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(_password, '登录密码（至少 6 位）', obscure: true,
            onSubmitted: (_) => _submit()),
        const SizedBox(height: 9),
        _field(_passwordConfirm, '重复登录密码', obscure: true,
            onSubmitted: (_) => _submit()),
        const SizedBox(height: 15),
        _label('性别'),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < QGender.values.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              _genderOption(QGender.values[i]),
            ],
          ],
        ),
        const SizedBox(height: 15),
        _label('头像'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < kQBuiltinAvatars.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              QBuiltinAvatarChip(
                index: i,
                size: 40,
                selected: i == _avatarIndex,
                onTap: st.registerBusy
                    ? null
                    : () => setState(() => _avatarIndex = i),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _statusLine(st),
      ],
    );
  }

  /// 左侧大头像预览：当前所选内置头像的放大版，圆形裁剪 + 米色描边。
  Widget _preview() {
    final p = kQBuiltinAvatars[_avatarIndex];
    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: vg(const [Color(0xFFE2CC9C), Color(0xFFA98C5E)]),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0A1636),
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: AvatarPlaceholder(size: 72, bg: p.bg, skin: p.skin, hair: p.hair),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: QText.of(11.5, color: const Color(0xFF4A4638)),
      );

  Widget _genderOption(QGender g) {
    final selected = g == _gender;
    final colors = selected
        ? const <Color>[Color(0xFF2E5363), Color(0xFF122C39)]
        : const <Color>[Color(0xFFECE8DA), Color(0xFFD9D3C2)];
    return QButtonInteraction(
      onTap: widget.state.registerBusy
          ? null
          : () => setState(() => _gender = g),
      child: Container(
        width: 74,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? const Color(0xFF0B1D27) : const Color(0xFFB7B09C),
          ),
          gradient: vg(colors),
        ),
        child: Text(
          g.label,
          style: QText.of(
            11,
            weight: FontWeight.w700,
            color: selected ? QC.white : const Color(0xFF3A3A35),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    ValueChanged<String>? onSubmitted,
  }) =>
      SizedBox(
        height: 30,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          onSubmitted: onSubmitted,
          style: QText.of(12, color: QC.aboutText),
          cursorColor: QC.aboutText,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFFFFFFF),
            hintText: hint,
            hintStyle: QText.of(11, color: const Color(0xFFA09A88)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Color(0xFFB7B09C)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Color(0xFFB7B09C)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: const BorderSide(color: Color(0xFF2E5363)),
            ),
          ),
        ),
      );

  Widget _statusLine(QAppState st) {
    if (st.registerBusy) {
      return const Text(
        '正在提交注册…',
        style: TextStyle(color: Color(0xFF2E5363), fontSize: 11),
      );
    }
    final error = _localError ?? st.registerError;
    if (error == null) return const SizedBox(height: 4);
    return Text(
      error,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: QText.of(11, color: const Color(0xFFB23B2E)),
    );
  }

  Widget _footer(QAppState st) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MetalButton(
            label: '注册并登录',
            width: 108,
            onTap: st.registerBusy ? null : _submit,
          ),
          const SizedBox(width: 10),
          MetalButton(
            label: '取消',
            width: 76,
            onTap: st.registerBusy ? null : st.closeRegisterWindow,
          ),
        ],
      ),
    );
  }
}

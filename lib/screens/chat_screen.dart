import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/linked_scrollbar.dart';
import '../core/models.dart';
import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';

/// QQ 概念版 · 聊天窗口 490x435（ui-v4.html V6.1 / #chat）
///
/// 分区（canvas 1x 坐标）：
///   标题栏 0..62 / 消息区 62..300 / 黄线 300..302
///   工具栏 302..326 / 输入区 326..435。
/// 所有位图素材均为自绘矢量替身；两个大功能图标带 30% 镜像倒影。
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    this.friendName,
    this.messages = const <QMessage>[],
    this.onSend,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.onFolderTap,
    this.onMailTap,
    this.sendWithEnter = false,
    this.sendWithCtrlEnter = true,
  });

  final String? friendName;
  final List<QMessage> messages;
  final ValueChanged<String>? onSend;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final VoidCallback? onFolderTap;
  final VoidCallback? onMailTap;
  final bool sendWithEnter;
  final bool sendWithCtrlEnter;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: S.chatW,
      height: S.chatH,
      child: Container(
        decoration: BoxDecoration(
          color: QC.white,
          borderRadius: BorderRadius.circular(5),
          boxShadow: qOuterShadow(QShadow.win),
          border: Border.all(color: QC.pageBorder, width: 1),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: Stack(
          children: [
            // 标题栏
            Positioned(
              left: 0,
              top: 0,
              width: S.chatW,
              height: S.chatTitleH,
              child: _titleBar(),
            ),
            // 消息区：无消息时保持设计稿的纯白空白会话
            Positioned(
              left: 0,
              top: S.chatTitleH,
              width: S.chatW,
              height: S.chatMsgH,
              child: _messageList(),
            ),
            // 黄线
            Positioned(
              left: 0,
              top: 300,
              width: S.chatW,
              height: S.chatYLineH,
              child: Container(color: QC.chatYLine),
            ),
            // 工具栏
            Positioned(
              left: 0,
              top: 302,
              width: S.chatW,
              height: S.chatToolbarH,
              child: _toolbar(),
            ),
            // 输入区 + 发送按钮（同一 490x109 区域内，坐标与设计稿一致）
            Positioned(
              left: 0,
              top: 326,
              width: S.chatW,
              height: S.chatInputH,
              child: _ChatComposer(
                onSend: onSend,
                sendButton: _sendButton(),
                sendWithEnter: sendWithEnter,
                sendWithCtrlEnter: sendWithCtrlEnter,
              ),
            ),
            // 两个大功能图标 + 倒影（置于最上层，倒影压在白色消息区上沿）
            // 与右上窗口按钮（右 10 / 上 7，71x15）保持 15px 横向净空。
            Positioned(
              left: 336,
              top: 26,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onFolderTap,
                child: _bigIcon(folder: true),
              ),
            ),
            Positioned(
              left: 375,
              top: 30,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMailTap,
                child: _bigIcon(folder: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 标题栏
  // ---------------------------------------------------------------------------
  Widget _titleBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: vg(
          [QC.chatTitleTop, QC.chatTitleMid, QC.chatTitleBottom],
          const [0, .55, 1],
        ),
      ),
      child: Stack(
        children: [
          // 头像框 44x44
          Positioned(
            left: 10,
            top: 9,
            width: 44,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0xFFCFD8DE), width: 2),
                gradient: vg([
                  const Color(0xFF0D1C30),
                  const Color(0xFF1E3A5E),
                ]),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(painter: _ChatAvatarPainter()),
            ),
          ),
          // 昵称
          Positioned(
            left: 64,
            top: 8,
            child: Text(
              friendName == null ? '① 云帆(1207012000)' : '① $friendName',
              style: QText.of(12.5, weight: FontWeight.w700),
            ),
          ),
          // 签名（单行省略）
          Positioned(
            left: 64,
            top: 24,
            width: 240,
            child: Text(
              '慢慢像坚固的铠甲生长，每分每秒，陪我叶落归乡…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QText.of(10, color: const Color(0xFFDFE7EC)),
            ),
          ),
          // 在线
          Positioned(
            left: 64,
            top: 40,
            child: Text(
              '在线',
              style: QText.of(10, color: const Color(0xFFEEF2F4)),
            ),
          ),
          // 三个细线窗口按钮
          Positioned(
            right: 10,
            top: 7,
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
              onTap: (k) {
                switch (k) {
                  case QWinBtnKind.minimize:
                    onMinimize?.call();
                  case QWinBtnKind.maximize:
                    onMaximize?.call();
                  case QWinBtnKind.close:
                    onClose?.call();
                  default:
                    break;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 会话消息（无消息时保持纯白空白，有消息时才渲染气泡）
  // ---------------------------------------------------------------------------
  Widget _messageList() => _ChatMessageList(messages: messages);

  // ---------------------------------------------------------------------------
  // 标题栏右侧大功能图标 + 下方镜像倒影
  // 参考图 zf3_chat 实测 1x：文件夹体 25x22（含顶部绿箭头共 29x30），信封 26x25；
  // 视觉上收小两档：文件夹 21x22（含箭头）、信封 19x18，倒影 5px 高。
  // ---------------------------------------------------------------------------
  Widget _bigIcon({required bool folder}) {
    return folder
        ? SizedBox(
            width: 21,
            height: 27,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 21,
                  height: 22,
                  child: CustomPaint(painter: _FolderIconPainter()),
                ),
                Positioned(
                  left: 0,
                  top: 22,
                  width: 19,
                  height: 5,
                  child: Opacity(
                    opacity: .3,
                    child: Transform(
                      transform: Matrix4.diagonal3Values(1, -1, 1),
                      alignment: Alignment.center,
                      child: Container(
                        width: 19,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A5426),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : SizedBox(
            width: 19,
            height: 23,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 19,
                  height: 18,
                  child: CustomPaint(painter: _EnvelopeIconPainter()),
                ),
                Positioned(
                  left: 0,
                  top: 18,
                  width: 19,
                  height: 5,
                  child: Opacity(
                    opacity: .3,
                    child: Transform(
                      transform: Matrix4.diagonal3Values(1, -1, 1),
                      alignment: Alignment.center,
                      child: Container(
                        width: 19,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B6A75),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
  }

  // ---------------------------------------------------------------------------
  // 工具栏
  // ---------------------------------------------------------------------------
  Widget _toolbar() {
    return Container(
      decoration: BoxDecoration(
        gradient: vg(
          [QC.toolbarTop, QC.toolbarMid, QC.toolbarBottom],
          const [0, .6, 1],
        ),
      ),
      child: Stack(
        children: [
          // A：Georgia 衬线
          Positioned(
            left: 12,
            top: 3,
            child: Text(
              'A',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: QC.toolIcon,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          for (final e in <Map<String, double>>[
            {'left': 44, 'kind': 0},
            {'left': 74, 'kind': 1},
            {'left': 106, 'kind': 2},
            {'left': 140, 'kind': 3},
          ])
            Positioned(
              left: e['left']!,
              top: 5,
              width: 15,
              height: 15,
              child: CustomPaint(painter: _ToolIconPainter(e['kind']!.toInt())),
            ),
          // 右端文档小图标
          Positioned(
            right: 14,
            top: 4,
            width: 17,
            height: 15,
            child: CustomPaint(painter: _ToolIconPainter(4)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 发送按钮
  // ---------------------------------------------------------------------------
  Widget _sendButton() {
    return Container(
      width: S.chatSendW,
      height: S.chatSendH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: QC.sendBorder, width: 1),
        gradient: vg(
          [QC.sendTop, QC.sendMid, QC.sendBottom],
          const [0, .55, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 内侧 1px 白色高光（inset 0 0 0 1px rgba(255,255,255,.7)）
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xB3FFFFFF), width: 1),
              ),
            ),
          ),
          Center(
            child: SizedBox(
              width: 34,
              height: 18,
              child: CustomPaint(painter: _SendArrowPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入区 + 发送按钮：持有文本控制器，支持 Enter / Ctrl+Enter 发送。
/// 坐标相对输入区 490x109；发送按钮仍在 right14 / bottom12，与设计稿一致。
/// 消息区滚动面板：右侧浅色自定义滚动条（替换系统默认滚动条）。
/// 新消息到达时自动滚到最底部（含 900ms 模拟回复）。
class _ChatMessageList extends StatefulWidget {
  const _ChatMessageList({required this.messages});

  final List<QMessage> messages;

  @override
  State<_ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<_ChatMessageList> {
  final ScrollController _ctrl = ScrollController();
  // 上次见到的消息数：state 层复用同一个可变 List 引用，
  // 不能拿 old.messages.length（与当前是同一对象）比较。
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ChatMessageList old) {
    super.didUpdateWidget(old);
    if (widget.messages.length > _lastCount) {
      _lastCount = widget.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_ctrl.hasClients) {
          _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) return Container(color: QC.chatMsg);
    return Container(
      color: QC.chatMsg,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              controller: _ctrl,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              itemCount: widget.messages.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final m = widget.messages[i];
                return Row(
                  mainAxisAlignment: m.self
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!m.self) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: vg(
                            const [Color(0xFF9AAEBB), Color(0xFF4C6878)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: m.self
                              ? const Color(0xFFDCEBF3)
                              : const Color(0xFFF1F3F4),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFFCBD5DB),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          m.text,
                          style: QText.of(12.5, color: const Color(0xFF25323A)),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          LinkedScrollBar(
            controller: _ctrl,
            style: QScrollStyle.light,
            step: 40,
          ),
        ],
      ),
    );
  }
}

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.sendButton,
    this.onSend,
    this.sendWithEnter = false,
    this.sendWithCtrlEnter = true,
  });

  final Widget sendButton;
  final ValueChanged<String>? onSend;
  final bool sendWithEnter;
  final bool sendWithCtrlEnter;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  final TextEditingController _ctl = TextEditingController();

  void _submit() {
    final text = _ctl.text;
    if (text.trim().isEmpty) return;
    widget.onSend?.call(text);
    _ctl.clear();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{};
    if (widget.sendWithCtrlEnter) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter, control: true)] =
          _submit;
      bindings[const SingleActivator(LogicalKeyboardKey.enter, meta: true)] =
          _submit;
    }
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: QC.white,
              border: Border(
                top: BorderSide(color: QC.chatInputBorder, width: 1),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 10,
          width: 330,
          height: 84,
          child: CallbackShortcuts(
            bindings: bindings,
            child: TextField(
              controller: _ctl,
              maxLines: widget.sendWithEnter ? 1 : 3,
              style: QText.of(13, color: const Color(0xFF2B3338)),
              cursorColor: const Color(0xFF5B6A73),
              onSubmitted: widget.sendWithEnter ? (_) => _submit() : null,
              decoration: InputDecoration(
                hintText: '输入消息…',
                hintStyle: QText.of(15, color: QC.chatHint),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 12,
          width: S.chatSendW,
          height: S.chatSendH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _submit,
            child: widget.sendButton,
          ),
        ),
      ],
    );
  }
}

/// 头像框内：企鹅矢量替身（44x44 viewBox）
class _ChatAvatarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 44, size.height / 44);
    final fill = Paint()..style = PaintingStyle.fill;
    canvas.drawOval(
      const Rect.fromLTRB(8, 8, 36, 40),
      fill..color = const Color(0xFF14181C),
    );
    canvas.drawOval(
      const Rect.fromLTRB(13, 17, 31, 39),
      fill..color = const Color(0xFFF2F2EE),
    );
    canvas.drawCircle(
      const Offset(17, 16),
      2.2,
      fill..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(27, 16),
      2.2,
      fill..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(17.6, 16.4),
      1,
      fill..color = const Color(0xFF111111),
    );
    canvas.drawCircle(
      const Offset(26.4, 16.4),
      1,
      fill..color = const Color(0xFF111111),
    );
    canvas.drawPath(
      Path()
        ..moveTo(20, 20)
        ..lineTo(24, 20)
        ..lineTo(22, 24)
        ..close(),
      fill..color = const Color(0xFFE8A13A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(12, 26, 32, 31),
        const Radius.circular(2),
      ),
      fill..color = const Color(0xFFC23B2A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(28, 28, 35, 32),
        const Radius.circular(2),
      ),
      fill..color = const Color(0xFFC23B2A),
    );
  }

  @override
  bool shouldRepaint(covariant _ChatAvatarPainter old) => false;
}

/// 黄色文件夹 + 绿色回旋箭头（29x30 viewBox：体 26x22 @y8，箭头顶部 8px）
class _FolderIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 29, size.height / 30);
    final rect = const Rect.fromLTWH(0, 0, 29, 30);
    final grad = vg(
      [QC.folderTop, QC.folderMid, QC.folderBottom],
      const [0, .55, 1],
    );
    final body = Path()
      ..moveTo(2, 8)
      ..lineTo(10, 8)
      ..lineTo(13, 11)
      ..lineTo(24, 11)
      ..arcToPoint(const Offset(26, 13), radius: const Radius.circular(2))
      ..lineTo(26, 28)
      ..arcToPoint(const Offset(24, 30), radius: const Radius.circular(2))
      ..lineTo(2, 30)
      ..arcToPoint(const Offset(0, 28), radius: const Radius.circular(2))
      ..lineTo(0, 10)
      ..arcToPoint(const Offset(2, 8), radius: const Radius.circular(2))
      ..close();
    canvas.drawPath(body, Paint()..shader = grad.createShader(rect));
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF8C5D14)
        ..strokeWidth = .8
        ..style = PaintingStyle.stroke,
    );
    // 前景下半部略暗（对应设计稿 opacity .82 的叠加层）
    final front = Path()
      ..moveTo(0, 15)
      ..lineTo(26, 15)
      ..lineTo(26, 28)
      ..arcToPoint(const Offset(24, 30), radius: const Radius.circular(2))
      ..lineTo(2, 30)
      ..arcToPoint(const Offset(0, 28), radius: const Radius.circular(2))
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0x1A000000));
    // 绿色回旋箭头（顶部右侧，探出文件夹体）
    final green = Paint()
      ..color = const Color(0xFF5FB73D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(13, 12)
        ..arcToPoint(
          const Offset(27, 5),
          radius: const Radius.circular(9),
          clockwise: true,
        ),
      green,
    );
    canvas.drawPath(
      Path()
        ..moveTo(22, 0)
        ..lineTo(29, 2.5)
        ..lineTo(23.5, 8)
        ..close(),
      Paint()..color = const Color(0xFF5FB73D),
    );
  }

  @override
  bool shouldRepaint(covariant _FolderIconPainter old) => false;
}

/// 银白信封（V 形封口）+ 斜置铅笔（26x25 viewBox）
class _EnvelopeIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 25);
    final envelope = RRect.fromRectAndRadius(
      const Rect.fromLTRB(0.5, 0.5, 25.5, 24.5),
      const Radius.circular(1),
    );
    final grad = vg([QC.envTop, QC.envMid, QC.envBottom], const [0, .55, 1]);
    canvas.drawRRect(
      envelope,
      Paint()..shader = grad.createShader(const Rect.fromLTWH(0, 0, 26, 25)),
    );
    canvas.drawRRect(
      envelope,
      Paint()
        ..color = const Color(0xFFEEF4F7)
        ..strokeWidth = .8
        ..style = PaintingStyle.stroke,
    );
    // V 形封口
    canvas.drawPath(
      Path()
        ..moveTo(0.5, 2)
        ..lineTo(13, 14.5)
        ..lineTo(25.5, 2),
      Paint()
        ..color = const Color(0xFF4A5C68)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    // 下折角
    canvas.drawPath(
      Path()
        ..moveTo(0.5, 23.5)
        ..lineTo(6, 14.5)
        ..moveTo(25.5, 23.5)
        ..lineTo(20, 14.5),
      Paint()
        ..color = const Color(0xFF8B9AA4)
        ..strokeWidth = .9
        ..style = PaintingStyle.stroke,
    );
    // 斜置铅笔（左下→右上，笔头略探出信封顶）
    canvas.drawLine(
      const Offset(24.5, 0.8),
      const Offset(8, 19.5),
      Paint()
        ..color = const Color(0xFF5B666E)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    // 笔尖三角
    canvas.drawPath(
      Path()
        ..moveTo(8, 19.5)
        ..lineTo(5.5, 22)
        ..lineTo(7, 17.8)
        ..close(),
      Paint()..color = const Color(0xFF2F3840),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(23, 0, 2.6, 2.6),
        const Radius.circular(.4),
      ),
      Paint()..color = const Color(0xFF8B959C),
    );
  }

  @override
  bool shouldRepaint(covariant _EnvelopeIconPainter old) => false;
}

/// 工具栏矢量图标：0 笑脸 / 1 图片 / 2 裁剪虚线框 / 3 画笔 / 4 文档
class _ToolIconPainter extends CustomPainter {
  const _ToolIconPainter(this.kind);
  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    final bw = kind == 4 ? 17.0 : 15.0;
    canvas.scale(size.width / bw, size.height / 15);
    final c = QC.toolIcon;
    final stroke = Paint()
      ..color = c
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = c
      ..style = PaintingStyle.fill;
    switch (kind) {
      case 0: // 笑脸
        canvas.drawCircle(const Offset(7.5, 7.5), 6.2, stroke);
        canvas.drawCircle(const Offset(5.4, 6), 1, fill);
        canvas.drawCircle(const Offset(9.6, 6), 1, fill);
        canvas.drawPath(
          Path()
            ..moveTo(4.8, 9.4)
            ..quadraticBezierTo(7.5, 11.4, 10.2, 9.4),
          Paint()
            ..color = c
            ..strokeWidth = 1.3
            ..style = PaintingStyle.stroke,
        );
        break;
      case 1: // 图片
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(1, 2.5, 14, 12.5),
            const Radius.circular(1.5),
          ),
          stroke,
        );
        canvas.drawCircle(const Offset(5, 6.5), 1.3, fill);
        canvas.drawPath(
          Path()
            ..moveTo(2, 12)
            ..lineTo(6.5, 7.5)
            ..lineTo(9.5, 10.5)
            ..lineTo(11.5, 8.8)
            ..lineTo(14, 12)
            ..close(),
          fill,
        );
        break;
      case 2: // 虚线裁剪框 + 右下折角
        final dash = Path()..addRect(const Rect.fromLTRB(1, 1, 13, 12));
        for (final m in dash.computeMetrics()) {
          double d = 0;
          while (d < m.length) {
            final e = d + 2.4 > m.length ? m.length : d + 2.4;
            canvas.drawPath(m.extractPath(d, e), stroke);
            d = e + 1.6;
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(12, 15)
            ..lineTo(12, 12)
            ..lineTo(15, 12),
          stroke,
        );
        break;
      case 3: // 画笔
        canvas.drawPath(
          Path()
            ..moveTo(3, 12)
            ..cubicTo(3, 9.5, 4.5, 8.6, 6, 8.6)
            ..lineTo(11, 1.5)
            ..lineTo(13.5, 4)
            ..lineTo(8.5, 11)
            ..cubicTo(8.5, 12.5, 7.5, 13.5, 5.5, 13.5)
            ..close(),
          fill,
        );
        break;
      case 4: // 文档
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(1, 1, 13, 14),
            const Radius.circular(1.5),
          ),
          stroke,
        );
        final line = Paint()
          ..color = c
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(const Offset(3.5, 4.5), const Offset(10.5, 4.5), line);
        canvas.drawLine(const Offset(3.5, 7.5), const Offset(10.5, 7.5), line);
        canvas.drawLine(const Offset(3.5, 10.5), const Offset(8, 10.5), line);
        canvas.drawRect(const Rect.fromLTRB(12.5, 5, 16.5, 13), fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ToolIconPainter old) => old.kind != kind;
}

/// 发送按钮内：细线回车箭头 ←──┐（34x18 viewBox）
class _SendArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 34, size.height / 18);
    final line = Paint()
      ..color = QC.bigbtnArrow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(29, 3)
        ..lineTo(29, 11)
        ..lineTo(6, 11),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(11, 6)
        ..lineTo(4, 11)
        ..lineTo(11, 16)
        ..close(),
      Paint()..color = QC.bigbtnArrow,
    );
  }

  @override
  bool shouldRepaint(covariant _SendArrowPainter old) => false;
}

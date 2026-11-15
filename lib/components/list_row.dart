import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// 圆角白描边头像框（列表行、聊天窗通用）。
class QAvatarChip extends StatelessWidget {
  const QAvatarChip({
    super.key,
    this.size = S.friendAvatar,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0x6BFFFFFF), width: 1),
    ),
    clipBehavior: Clip.hardEdge,
    child: child,
  );
}

/// 通用两行列表行：头像 + 标题 + 副标题（可带右上/右下角标），带悬停高亮。
///
/// 交互约定（QQ 概念版）：**双击**行打开聊天窗口（[onOpen]）；
/// 选中行用黄框 + 橄榄绿底（[selected]）。
class QListRow extends StatefulWidget {
  const QListRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.trailingTop,
    this.trailingTopOffset = const Offset(2, 6),
    this.trailingBottom,
    this.selected = false,
    this.onOpen,
    this.height = S.friendRowH,
    this.titleColor = QC.fname,
    this.subtitleColor = QC.fsig,
    this.contentRightInset = 0,
    this.unreadCount = 0,
  });

  /// 头像内容（放进 [QAvatarChip]）。
  final Widget avatar;
  final String title;
  final String subtitle;

  /// 右上角标（如时间）与其偏移；右下角标（如未读红点）。
  final Widget? trailingTop;
  final Offset trailingTopOffset;
  final Widget? trailingBottom;

  final bool selected;

  /// 双击回调：打开聊天窗口。
  final VoidCallback? onOpen;

  final double height;
  final Color titleColor;
  final Color subtitleColor;
  final double contentRightInset;
  final int unreadCount;

  @override
  State<QListRow> createState() => _QListRowState();
}

class _QListRowState extends State<QListRow>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.unreadCount > 0) _shake.repeat();
  }

  @override
  void didUpdateWidget(covariant QListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unreadCount > 0 && oldWidget.unreadCount == 0) {
      _shake.repeat();
    } else if (widget.unreadCount == 0 && oldWidget.unreadCount > 0) {
      _shake.stop();
      _shake.value = 0;
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool sel = widget.selected;
    final Widget body = Container(
      height: widget.height,
      padding: EdgeInsets.only(left: sel ? 10 : 12, right: 8),
      decoration: sel
          ? BoxDecoration(
              color: QC.selRow,
              border: Border.all(color: QC.yellow, width: 2),
              borderRadius: BorderRadius.circular(3),
            )
          : BoxDecoration(
              color: _hover ? QC.rowHover : null,
              border: const Border(
                bottom: BorderSide(color: QC.rowSep, width: 1),
              ),
            ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _shake,
                    child: QAvatarChip(child: widget.avatar),
                    builder: (context, child) => Transform.translate(
                      key: ValueKey('shake-${widget.title}'),
                      offset: Offset(
                        math.sin(_shake.value * 2 * math.pi) * 3,
                        0,
                      ),
                      child: child,
                    ),
                  ),
                  if (widget.unreadCount > 0)
                    Positioned(
                      right: -5,
                      top: -4,
                      child: QUnreadBadge(
                        key: ValueKey('unread-${widget.title}'),
                        count: widget.unreadCount,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QText.of(
                        12,
                        weight: FontWeight.w700,
                        color: widget.titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QText.of(10.5, color: widget.subtitleColor),
                    ),
                  ],
                ),
              ),
              if (widget.contentRightInset > 0)
                SizedBox(width: widget.contentRightInset),
            ],
          ),
          if (widget.trailingTop != null)
            Positioned(
              right: widget.trailingTopOffset.dx,
              top: widget.trailingTopOffset.dy,
              child: widget.trailingTop!,
            ),
          if (widget.trailingBottom != null)
            Positioned(right: 2, bottom: 7, child: widget.trailingBottom!),
        ],
      ),
    );

    return MouseRegion(
      cursor: widget.onOpen != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: widget.onOpen == null
          ? null
          : (_) => setState(() => _hover = true),
      onExit: widget.onOpen == null
          ? null
          : (_) => setState(() => _hover = false),
      child: widget.onOpen == null
          ? body
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onOpen,
              child: body,
            ),
    );
  }
}

class QUnreadBadge extends StatelessWidget {
  const QUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '未读 $count 条',
    child: Container(
      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8574C), Color(0xFFB01E14)],
        ),
        border: Border.all(color: const Color(0xFF7A120B), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: QText.of(9, weight: FontWeight.w800),
      ),
    ),
  );
}

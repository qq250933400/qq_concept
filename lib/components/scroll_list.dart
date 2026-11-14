import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'linked_scrollbar.dart';

/// 可滚动列表面：内容列（宽 = 窗口宽 - 滚动条宽）+ 右侧联动窄滚动条。
///
/// 自持 [ScrollController]，内容高出视口时：
/// - 鼠标滚轮 / 触控板滚动列表；
/// - 拇指大小与位置联动，且可反向拖拽拇指滚动。
class QScrollList extends StatefulWidget {
  const QScrollList({
    super.key,
    required this.child,
    this.height = S.bambooH,
    this.topPadding = 7,
  });

  final Widget child;
  final double height;
  final double topPadding;

  @override
  State<QScrollList> createState() => _QScrollListState();
}

class _QScrollListState extends State<QScrollList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: S.mainWinW,
      height: widget.height,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: S.mainWinW - S.vScrollW,
            height: widget.height,
            child: SingleChildScrollView(
              controller: _controller,
              padding: EdgeInsets.only(top: widget.topPadding),
              child: widget.child,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: S.vScrollW,
            child: LinkedScrollBar(controller: _controller),
          ),
        ],
      ),
    );
  }
}

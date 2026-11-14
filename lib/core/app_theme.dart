import 'package:flutter/material.dart';

import 'tokens.dart';

/// 全局禁用 Material 在 web/desktop 上给滚动区域包默认灰色滚动条（系统样式）。
/// 需要滚动条的地方一律显式使用 [LinkedScrollBar]（QQ 概念版自绘样式）。
///
/// 主窗口与每个「原生独立子窗口」都有各自的 [MaterialApp]，两边必须共用
/// 同一份 scrollBehavior / ThemeData，否则子窗口会出现系统滚动条与配色漂移。
class QNoSystemScrollbarBehavior extends MaterialScrollBehavior {
  const QNoSystemScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// QQ 概念版统一主题。主窗口与原生聊天子窗口共用。
ThemeData qqTheme() => ThemeData(
  brightness: Brightness.dark,
  fontFamily: QText.font,
  scaffoldBackgroundColor: QC.pageBg,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF2D5763),
    surface: Color(0xFF1E2225),
  ),
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
);

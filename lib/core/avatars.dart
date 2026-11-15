import 'package:flutter/material.dart';

import 'tokens.dart';
import 'widgets.dart';

/// 内置自绘头像库（8 款矢量替身，无真实素材）。
///
/// 服务端只存字符串标识 `builtin://avatar/<0..7>`（avatar_url 透传，不托管图片），
/// 客户端据此取回配色并交给 `AvatarPlaceholder` 绘制。外链 URL 与 null（未设置）
/// 同样兼容：解析失败一律回落 0 号。
class QAvatarPalette {
  const QAvatarPalette({
    required this.bg,
    required this.skin,
    required this.hair,
    required this.name,
  });

  final Color bg;
  final Color skin;
  final Color hair;

  /// 调试用可读名称（「暖橙」「紫藤」等），不参与序列化。
  final String name;
}

const List<QAvatarPalette> kQBuiltinAvatars = <QAvatarPalette>[
  QAvatarPalette(
    bg: Color(0xFF6B4526), skin: Color(0xFFE8C49C), hair: Color(0xFF35231A),
    name: '原木',
  ),
  QAvatarPalette(
    bg: Color(0xFFDFE4E8), skin: Color(0xFFE8C49C), hair: Color(0xFF4A3A2A),
    name: '雾白',
  ),
  QAvatarPalette(
    bg: Color(0xFFD8A8BC), skin: Color(0xFFF2DCC8), hair: Color(0xFF8A3F5A),
    name: '粉玫',
  ),
  QAvatarPalette(
    bg: Color(0xFF8FA8BC), skin: Color(0xFFE8D5B8), hair: Color(0xFF3A2E26),
    name: '青灰',
  ),
  QAvatarPalette(
    bg: Color(0xFF3A5A7A), skin: Color(0xFFF2D8B0), hair: Color(0xFF2E2620),
    name: '深海',
  ),
  QAvatarPalette(
    bg: Color(0xFF9AB88A), skin: Color(0xFFF0D8B8), hair: Color(0xFF5A3A28),
    name: '草叶',
  ),
  QAvatarPalette(
    bg: Color(0xFFE8B36A), skin: Color(0xFFF2DCC8), hair: Color(0xFF7A4A20),
    name: '暖橙',
  ),
  QAvatarPalette(
    bg: Color(0xFF8A7ABC), skin: Color(0xFFF2DCC8), hair: Color(0xFF3A3055),
    name: '紫藤',
  ),
];

const String kQAvatarUrlPrefix = 'builtin://avatar/';

/// 序号 → 服务端存储的 avatar_url 标识。
String qBuiltinAvatarUrl(int index) =>
    '$kQAvatarUrlPrefix${index.clamp(0, kQBuiltinAvatars.length - 1)}';

/// avatar_url → 内置头像序号；非内置标识（外链 / null / 格式错）返回 null。
int? qBuiltinAvatarIndex(String? url) {
  if (url == null || !url.startsWith(kQAvatarUrlPrefix)) return null;
  final n = int.tryParse(url.substring(kQAvatarUrlPrefix.length));
  if (n == null || n < 0 || n >= kQBuiltinAvatars.length) return null;
  return n;
}

/// 内置头像 chip。选中时描一圈青色亮边（深色玻璃表面上的选中态）。
class QBuiltinAvatarChip extends StatelessWidget {
  const QBuiltinAvatarChip({
    super.key,
    required this.index,
    this.size = 40,
    this.selected = false,
    this.onTap,
  });

  final int index;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = kQBuiltinAvatars[index.clamp(0, kQBuiltinAvatars.length - 1)];
    final body = Container(
      width: size + (selected ? 4 : 2),
      height: size + (selected ? 4 : 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 选中环沿用窗口标题栏的深蓝绿，未选中用米色描边（适配浅色 dlgbody）。
        gradient: selected
            ? vg(const [Color(0xFF2E5363), Color(0xFF122C39)])
            : null,
        color: selected ? null : const Color(0x668A8272),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      padding: EdgeInsets.all(selected ? 2.0 : 1.0),
      child: ClipOval(
        child: AvatarPlaceholder(size: size, bg: p.bg, skin: p.skin, hair: p.hair),
      ),
    );
    return onTap == null
        ? body
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: body,
          );
  }
}

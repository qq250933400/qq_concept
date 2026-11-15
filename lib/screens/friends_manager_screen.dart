import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/contacts.dart';
import '../core/models.dart';
import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';
import 'contacts_dialogs.dart';

/// QQ 概念版 · 好友管理木质桌面 959x597（ui-v4.html V6.1 / #fm）
///
/// 分区：标题栏 0..30 / 第二栏 30..62 / 黄线 62..64 / 木桌 64..597。
/// 木纹、暖光、暗角统一由 _WoodPainter 一次绘制；气泡球、照片卡、信息卡、
/// 柱状图、滚动条均为 canvas 1x 绝对坐标，超出底部的部分由窗口裁剪。
class FriendsManagerScreen extends StatefulWidget {
  const FriendsManagerScreen({
    super.key,
    required this.state,
    this.onButtonTap,
    this.onFriendTap,
    this.staticPreview = false,
  });

  final QAppState state;
  final void Function(QWinBtnKind kind)? onButtonTap;
  final ValueChanged<String>? onFriendTap;

  /// true = 设计稿画廊：严格按 V6.1 渲染静态气泡 / 照片卡，不接关系链交互。
  final bool staticPreview;

  @override
  State<FriendsManagerScreen> createState() => _FriendsManagerScreenState();
}

class _FriendsManagerScreenState extends State<FriendsManagerScreen> {
  final TextEditingController _search = TextEditingController();

  QAppState get state => widget.state;
  void Function(QWinBtnKind kind)? get onButtonTap => widget.onButtonTap;
  ValueChanged<String>? get onFriendTap => widget.onFriendTap;
  bool get staticPreview => widget.staticPreview;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 关系链数据由 QAppState 驱动；输入框文本留在本地 State，
  /// 避免每个按键都通知全部 OS 窗口。
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: state,
        builder: (context, _) => _shell(),
      );

  Widget _shell() {
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

            // 分组数超过气泡球位数时给一个明确可见的入口：设计稿固定 7 个
            // 球位，且最后一个在窗口底部会被裁掉，单靠「更多分组」球不够。
            if (!staticPreview && state.contactGroups.length > 6)
              Positioned(
                left: 60,
                top: 100,
                width: 230,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      state.openContactsDialog(QContactDialog.groups),
                  child: Text(
                    '共 ${state.contactGroups.length} 个分组 · 点此管理',
                    style: QText.of(11, color: const Color(0xCCE6DCC8)),
                  ),
                ),
              ),

            // 分组气泡球：全部好友 + 真实分组（最多 6 个）。
            // 坐标 / 尺寸 / 配色沿用设计稿，只把名称与人数换成服务端数据。
            for (final spec in
                (staticPreview ? _staticBubbleSpecs() : _bubbleSpecs()))
              _bubble(spec),

            // 照片卡：当前分组 + 搜索词过滤后的真实好友（最多 13 张）。
            ...(staticPreview ? _staticCards() : _friendCards()),

            // 右上信息卡 / 右下柱状图 / 底部滚动条
            Positioned(
              left: 806,
              top: 16,
              child: _infoCard(design: staticPreview),
            ),
            Positioned(left: 806, top: 404, child: _chart()),
            Positioned(left: 300, top: 584, child: _hscroll()),

            // 关系链操作浮层：添加好友 / 申请 / 分组 / 好友操作 / 确认。
            if (!staticPreview) QContactsOverlay(state: state),
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
          // 关系链入口：放在标题栏左半的空白区。放右侧会被右上信息卡
          // 以及画布模式下叠上来的主面板窗口盖住，导致「分组管理」点不到。
          if (!staticPreview)
            Positioned(left: 130, top: 5, child: _toolButtons()),
          // 工具按钮右侧到窗口按钮之间是标题栏空白，放数据概览最稳妥：
          // 第二栏右端会被右上信息卡盖住，不能放文字。
          if (!staticPreview)
            Positioned(
              left: 440,
              top: 8,
              child: Text(
                '${state.contacts.length} 位好友 · '
                '${state.contactGroups.length} 个分组',
                style: QText.of(10.5, color: const Color(0xFFDCE7EC)),
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

  Widget _toolButtons() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolChip(
            '+ 添加好友',
            () => state.openContactsDialog(QContactDialog.addFriend),
            92,
          ),
          const SizedBox(width: 6),
          _toolChip(
            '好友申请 (${state.pendingRequestCount})',
            () => state.openContactsDialog(QContactDialog.requests),
            112,
          ),
          const SizedBox(width: 6),
          _toolChip(
            '分组管理',
            () => state.openContactsDialog(QContactDialog.groups),
            76,
          ),
        ],
      );

  Widget _toolChip(String label, VoidCallback onTap, double width) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: width,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: const Color(0x33000000),
            border: Border.all(color: const Color(0x55FFFFFF)),
          ),
          child: Text(label, style: QText.of(10.5, weight: FontWeight.w700)),
        ),
      );

  Widget _bar2() {
    return Container(
      decoration: BoxDecoration(gradient: vg([QC.fmBar2Top, QC.fmBar2Bottom])),
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 8,
            child: Text(
              staticPreview ? '大学好友' : state.selectedGroupName,
              style: QText.of(14, weight: FontWeight.w800),
            ),
          ),
          // 搜索框：设计稿中位于 .bar2 内 top5（canvas 绝对 y=35）。
          // 交互模式改成真实输入，按昵称 / 帐号 / 签名过滤照片卡。
          Positioned(
            left: 150,
            top: 5,
            child: _searchBox(design: staticPreview),
          ),
        ],
      ),
    );
  }

  Widget _searchBox({bool design = false}) {
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
          if (design)
            const Positioned(
              left: 10,
              top: 3,
              child: Text(
                '输入英文或者拼音进行搜索',
                style: TextStyle(fontSize: 12, color: Color(0xFF9AA1A6)),
              ),
            )
          else
            Positioned(
              left: 10,
              right: 10,
              top: 1,
              height: 20,
              child: Material(
                type: MaterialType.transparency,
                child: TextField(
                  controller: _search,
                  onChanged: state.setContactsQuery,
                  style: QText.of(11.5, color: const Color(0xFF33403F)),
                  cursorColor: const Color(0xFF4A5E5A),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '输入昵称 / 帐号 / 签名搜索好友',
                    hintStyle: QText.of(11, color: const Color(0xFF9AA1A6)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
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

  /// 设计稿画廊：V6.1 的 7 个气泡与 13 张照片卡，1:1 静态对照。
  List<_BubbleSpec> _staticBubbleSpecs() => const <_BubbleSpec>[
        _BubbleSpec(
          id: null,
          name: '全部好友',
          count: 292,
          left: 132,
          top: 186,
          size: 82,
          colors: _blue,
        ),
        _BubbleSpec(
          id: 'shot-1',
          name: '高中挚友',
          count: 83,
          left: 112,
          top: 252,
          size: 78,
          colors: _orange,
        ),
        _BubbleSpec(
          id: 'shot-2',
          name: '大学好友',
          count: 66,
          left: 86,
          top: 316,
          size: 100,
          colors: _green,
          nameSize: 15,
          countSize: 14,
          ring: true,
          blur: 14,
          dy: 8,
        ),
        _BubbleSpec(
          id: 'shot-3',
          name: 'WOW好友',
          count: 12,
          left: 92,
          top: 398,
          size: 76,
          colors: _red,
        ),
        _BubbleSpec(
          id: 'shot-4',
          name: '亲戚家人',
          count: 9,
          left: 126,
          top: 462,
          size: 70,
          colors: _teal,
        ),
        _BubbleSpec(
          id: 'shot-5',
          name: '已知网友',
          count: 116,
          left: 162,
          top: 520,
          size: 76,
          colors: _blue,
        ),
        _BubbleSpec(
          id: 'shot-6',
          name: '淘宝好友',
          count: 6,
          left: 212,
          top: 584,
          size: 72,
          colors: _orange,
          opacity: .9,
        ),
      ];

  List<Widget> _staticCards() => <Widget>[
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
      ];

  /// 气泡球数据：第 1 个固定「全部好友」，其余取服务端分组（最多 6 个）。
  /// 位置 / 尺寸 / 配色严格沿用设计稿，只换名称、人数与选中态。
  List<_BubbleSpec> _bubbleSpecs() {
    const spots = <List<double>>[
      <double>[112, 252, 78],
      <double>[86, 316, 100],
      <double>[92, 398, 76],
      <double>[126, 462, 70],
      <double>[162, 520, 76],
      <double>[212, 584, 72],
    ];
    const palettes = <List<Color>>[
      _orange,
      _green,
      _red,
      _teal,
      _blue,
      _orange,
    ];
    final selected = state.selectedGroupId;
    final all = selected == null;
    final result = <_BubbleSpec>[
      _BubbleSpec(
        id: null,
        name: '全部好友',
        count: state.contacts.length,
        left: 132,
        top: 186,
        size: 82,
        colors: _blue,
        ring: all,
        nameSize: all ? 14 : 13,
        countSize: all ? 13 : 12,
        blur: all ? 14 : 10,
        dy: all ? 8 : 6,
      ),
    ];
    final totalGroups = state.contactGroups.length;
    final overflow = totalGroups > spots.length;
    final groups = state.contactGroups.take(spots.length).toList();
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      // 分组多于气泡球位数时，最后一个球改成「更多分组」入口，
      // 否则新建的分组会完全看不见（气泡球沿用设计稿固定 7 位）。
      final more = overflow && i == groups.length - 1;
      // 第 3 个球是设计稿的视觉焦点，保留大字号与深投影；
      // 高亮环只给真正选中的分组，避免「看起来选中、点开却是别组」。
      final focus = i == 1;
      result.add(_BubbleSpec(
        id: g.id,
        name: more ? '更多分组' : g.name,
        count: more ? totalGroups - spots.length + 1 : g.count,
        left: spots[i][0],
        top: spots[i][1],
        size: spots[i][2],
        colors: palettes[i],
        ring: !more && !all && selected == g.id,
        nameSize: focus ? 15 : 13,
        countSize: focus ? 14 : 12,
        blur: focus ? 14 : 10,
        dy: focus ? 8 : 6,
        opacity: i == 5 ? .9 : 1,
        opensManager: more,
      ));
    }
    return result;
  }

  Widget _bubble(_BubbleSpec s) {
    return Positioned(
      left: s.left,
      top: s.top,
      width: s.size,
      height: s.size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: staticPreview
            ? null
            : () => s.opensManager
                ? state.openContactsDialog(QContactDialog.groups)
                : state.selectContactGroup(s.id),
        onLongPress: staticPreview ? null : () => _onBubbleLongPress(s),
        onSecondaryTapDown:
            staticPreview ? null : (_) => _onBubbleLongPress(s),
        child: Opacity(
          opacity: s.opacity,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-.24, -.44),
                colors: s.colors,
                stops: const [0, .55, 1],
              ),
              border: s.ring
                  ? Border.all(color: const Color(0x40FFFFFF), width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x73000000),
                  blurRadius: s.blur,
                  offset: Offset(0, s.dy),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: s.size - 12,
                  child: Text(
                    s.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QText.of(s.nameSize, weight: FontWeight.w700),
                  ),
                ),
                Text(
                  '(${s.count})',
                  textAlign: TextAlign.center,
                  style: QText.of(s.countSize, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onBubbleLongPress(_BubbleSpec s) {
    if (s.opensManager || s.id == null || s.id!.isEmpty) {
      state.openContactsDialog(QContactDialog.groups);
    } else {
      state.openContactsDialog(
        QContactDialog.renameGroup,
        target: s.id,
        targetName: s.name,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 照片卡数据：当前分组 / 搜索词过滤后的真实好友，最多摆 13 张
  // ---------------------------------------------------------------------------
  static const List<List<double>> _cardSpots = <List<double>>[
    <double>[305, 120, -8],
    <double>[478, 120, 7],
    <double>[290, 236, -10],
    <double>[298, 318, -6],
    <double>[318, 352, 4],
    <double>[404, 296, -7],
    <double>[398, 352, 6],
    <double>[470, 376, -4],
    <double>[618, 292, 6],
    <double>[772, 286, 2],
    <double>[748, 370, -3],
    <double>[646, 398, -11],
    <double>[806, 186, 8],
  ];

  List<Widget> _friendCards() {
    final visible = state.visibleContacts;
    if (visible.isEmpty) {
      return <Widget>[
        Positioned(
          left: 330,
          top: 246,
          width: 420,
          height: 60,
          child: Center(
            child: Text(
              state.contacts.isEmpty
                  ? '还没有好友，点右上角「+ 添加好友」开始'
                  : '当前分组下没有匹配的好友',
              textAlign: TextAlign.center,
              style: QText.of(13, color: const Color(0xFFE6DCC8)),
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      for (var i = 0; i < visible.length && i < _cardSpots.length; i++)
        _fcard(
          _cardSpots[i][0],
          _cardSpots[i][1],
          _cardSpots[i][2],
          visible[i].name,
          qFriendFromApi(visible[i].name, visible[i].signature).bg,
          opacity: i == 12 ? .75 : 1,
        ),
    ];
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
              onTap: staticPreview
                  ? null
                  : () {
                      state.selectContact(name);
                      if (onFriendTap != null) onFriendTap!(name);
                    },
              onLongPress: staticPreview
                  ? null
                  : () => state.openContactsDialog(
                      QContactDialog.friendActions,
                      target: name,
                      targetName: name,
                    ),
              onSecondaryTapDown: staticPreview
                  ? null
                  : (_) => state.openContactsDialog(
                      QContactDialog.friendActions,
                      target: name,
                      targetName: name,
                    ),
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
  Widget _infoCard({bool design = false}) {
    final visible = state.visibleContacts;
    // 优先显示点选过的好友，否则显示当前筛选结果的第一位。
    final c = state.contactByName(state.selectedContactName) ??
        (visible.isEmpty ? null : visible.first);
    final bg = (design || c == null)
        ? const Color(0xFF5A4636)
        : qFriendFromApi(c.name, c.signature).bg;
    var groupName = design ? '大学好友' : '未分组';
    if (!design && c == null) {
      groupName = '—';
    } else if (!design && c != null) {
      for (final g in state.contactGroups) {
        if (g.id == (c.groupId ?? '')) {
          groupName = g.name;
          break;
        }
      }
    }
    return Container(
      width: 146,
      height: 142,
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
                child: AvatarPlaceholder(size: 44, bg: bg),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            design
                ? '陈华(635478153)'
                : (c == null ? '暂无好友' : '${c.name}(${c.account})'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QText.of(11.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: const Color(0x29FFFFFF)),
          const SizedBox(height: 6),
          Text(
            design
                ? '你真美。Silverlight.'
                : (c == null || c.signature.isEmpty
                    ? '点击照片卡查看资料'
                    : c.signature),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: QText.of(10, color: const Color(0xFFC9D4DC)),
          ),
          const SizedBox(height: 3),
          Text(
            '分组：$groupName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QText.of(10, color: const Color(0xFF8FC7E8)),
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

/// 一个分组气泡球的布局 + 数据。id 为 null 表示「全部好友」，
/// 空串表示虚拟的「未分组」。
class _BubbleSpec {
  const _BubbleSpec({
    required this.id,
    required this.name,
    required this.count,
    required this.left,
    required this.top,
    required this.size,
    required this.colors,
    this.nameSize = 13,
    this.countSize = 12,
    this.ring = false,
    this.opacity = 1,
    this.blur = 10,
    this.dy = 6,
    this.opensManager = false,
  });

  final String? id;
  final String name;
  final int count;
  final double left;
  final double top;
  final double size;
  final List<Color> colors;
  final double nameSize;
  final double countSize;
  final bool ring;
  final double opacity;
  final double blur;
  final double dy;

  /// 分组数超出气泡球位数时，最后一个球变成「更多分组」入口。
  final bool opensManager;
}

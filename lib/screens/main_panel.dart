import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/bamboo_backdrop.dart';
import '../components/list_row.dart';
import '../components/scroll_list.dart';
import '../components/tab_flip.dart';
import '../core/avatars.dart';
import '../core/models.dart';
import '../core/tokens.dart';
import '../core/window_chrome.dart';
import '../core/widgets.dart';

/// QQ 概念版主面板（三个 tab 页 + 主菜单浮层）。
/// 全部坐标均为相对 .win 左上角的 1x 逻辑像素；画布 272x645，窗口 top32 272x603。
///
/// tab：0 = 好友列表，1 = 群组列表，2 = 最近消息。
/// tab 切换由 [TabFlip] 做 3D 翻转：向右切换正向翻转，向左切换反向翻转。
class MainPanel extends StatelessWidget {
  const MainPanel({
    super.key,
    this.tab = 0,
    this.onTabChanged,
    this.menuOpen = false,
    this.onDismissMenu,
    this.onFriendTap,
    this.onMenuAction,
    this.onFooterAction,
    this.onWindowButton,
    this.onSearchChanged,
    this.onAddTap,
    this.onGroupTap,
    this.onMainMenuTap,
    this.selectedName,
    this.searchQuery = '',
    this.expandedGroup,
    this.staticPreview = false,
    this.friendGroups,
    this.friends,
    this.myAvatarIndex,
  });

  /// 当前 tab 页索引：0 好友列表 / 1 群组列表 / 2 最近消息。
  final int tab;
  final ValueChanged<int>? onTabChanged;

  /// 主菜单浮层是否打开（由左下角企鹅球切换，点击浮层外部关闭）。
  final bool menuOpen;
  final VoidCallback? onDismissMenu;

  final ValueChanged<String>? onFriendTap;
  final ValueChanged<String>? onMenuAction;
  final ValueChanged<String>? onFooterAction;
  final void Function(QWinBtnKind kind)? onWindowButton;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onAddTap;

  /// 点击分组标题（如「大学好友(21/66)」）展开/收起该分组下的好友行。
  final ValueChanged<String>? onGroupTap;

  /// 主面板左下角企鹅球：主菜单的唯一切换入口。
  final VoidCallback? onMainMenuTap;

  final String? selectedName;
  final String searchQuery;

  /// 当前展开的分组；null = 全部折叠。交互态由 QAppState 驱动。
  final String? expandedGroup;

  /// 设计稿画廊模式：四态严格按 V6.1 渲染，不启用分组展开逻辑。
  final bool staticPreview;

  /// API 模式下由服务端 friend_groups 驱动；null 时用设计稿的六组静态数据。
  /// 这样「接后端」与「画廊/离线演示」共用同一套渲染代码。
  final List<QFriendGroup>? friendGroups;
  final List<QFriend>? friends;

  /// 当前用户的内置头像下标（`builtin://avatar/N`）。
  /// null（未设置 / 外链 / 画廊）时左上角相框保持 V6.1 默认剪影。
  final int? myAvatarIndex;

  static const List<Shadow> _headShadow = [
    Shadow(color: Color(0xD9000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<Shadow> _grpShadow = [
    Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<String> _grpLabels = [
    '高中挚友(19/83)',
    '大学好友(21/66)',
    'WOW好友(4/12)',
    '亲戚家人(4/9)',
    '已知网友(19/116)',
    '淘宝好友(4/6)',
  ];
  static const List<_Friend> _friends = [
    _Friend(
      '阿澈',
      '拍拍网友情，别来无恙…',
      Color(0xFF6B4526),
      Color(0xFFE8C49C),
      Color(0xFF35231A),
    ),
    _Friend(
      '周小满',
      '★[转] 穷人为什么穷？富人为什…',
      Color(0xFFDFE4E8),
      Color(0xFFE8C49C),
      Color(0xFF4A3A2A),
    ),
    _Friend(
      '苏禾',
      '/kh//等待是这么的漫长，可是人的一…',
      Color(0xFFD8A8BC),
      Color(0xFFF2DCC8),
      Color(0xFF8A3F5A),
      true,
    ),
    _Friend(
      '林岚',
      '/kh//zyz/ 努力就有收获。',
      Color(0xFF8FA8BC),
      Color(0xFFE8D5B8),
      Color(0xFF3A2E26),
    ),
    _Friend(
      '陈默',
      '明天太阳会照常升起，世界…',
      Color(0xFF3A5A7A),
      Color(0xFFF2D8B0),
      Color(0xFF2E2620),
    ),
    _Friend(
      '何小满',
      '/kh/ 不问世事，与技术…',
      Color(0xFF9AB88A),
      Color(0xFFF0D8B8),
      Color(0xFF5A3A28),
    ),
  ];

  /// 群组列表（tab1）：群名(成员数) + 群动态签名。
  static const List<_Group> _groups = [
    _Group(
      'IconFans | 国标粉丝',
      2,
      '国标字幕组 · 每周三更新',
      Color(0xFFD94B3A),
      Color(0xFF8D2A20),
      true,
    ),
    _Group(
      '视觉同盟编辑部',
      46,
      'UI 复刻与设计资源分享',
      Color(0xFF3A5A7A),
      Color(0xFF21414D),
      false,
    ),
    _Group(
      '像素小镇',
      128,
      '今晚 8 点像素画公开课',
      Color(0xFF5FA85A),
      Color(0xFF2F6B2C),
      false,
    ),
    _Group(
      '午夜电台 FM',
      89,
      '正在点歌：南方小羊影院',
      Color(0xFF8A6BB8),
      Color(0xFF4C3A6B),
      false,
    ),
    _Group(
      '胶片摄影社',
      57,
      '扫街活动返图已上传',
      Color(0xFF4A8A94),
      Color(0xFF25525C),
      false,
    ),
    _Group(
      '慢生活',
      23,
      '周末爬山，还差两位',
      Color(0xFFC8903A),
      Color(0xFF7A5218),
      false,
    ),
  ];

  /// 最近消息（tab2 / 竹叶页，IconFans 群消息）。
  static const List<_Recent> _recents = [
    _Recent(
      '阿澈',
      '今晚国标出片，资源已传群盘',
      '14:32',
      Color(0xFF6B4526),
      Color(0xFFE8C49C),
      Color(0xFF35231A),
      true,
    ),
    _Recent(
      '周小满',
      '★[转] 穷人为什么穷？富人为什…',
      '13:05',
      Color(0xFFDFE4E8),
      Color(0xFFE8C49C),
      Color(0xFF4A3A2A),
      false,
    ),
    _Recent(
      '苏禾',
      '/kh/ 等待是这么的漫长，可是人的一…',
      '11:47',
      Color(0xFFD8A8BC),
      Color(0xFFF2DCC8),
      Color(0xFF8A3F5A),
      false,
    ),
    _Recent(
      '林岚',
      '/zyz/ 努力就有收获。',
      '昨天',
      Color(0xFF8FA8BC),
      Color(0xFFE8D5B8),
      Color(0xFF3A2E26),
      false,
    ),
    _Recent(
      '陈默',
      '明天太阳会照常升起，世界…',
      '昨天',
      Color(0xFF3A5A7A),
      Color(0xFFF2D8B0),
      Color(0xFF2E2620),
      false,
    ),
    _Recent(
      '何小满',
      '/kh/ 不问世事，与技术…',
      '周二',
      Color(0xFF9AB88A),
      Color(0xFFF0D8B8),
      Color(0xFF5A3A28),
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bool isMenu = menuOpen;

    // 设计稿画廊：各 shot 固定展示对应 tab 页；菜单 shot 用 tab0 作背景。
    // 交互态：tab 由 QAppState.panelTab 驱动。
    final int tabIndex = staticPreview ? tab : tab;
    // 菜单态下所有面板交互都让位给「点击外部关闭菜单」。
    final bool interactive = !isMenu;
    final groupTap = (staticPreview || isMenu) ? null : onGroupTap;

    return SizedBox(
      width: S.mainCanvasW,
      height: S.mainCanvasH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (isMenu && onDismissMenu != null) ? onDismissMenu : null,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              top: S.mainWinTop,
              width: S.mainWinW,
              height: S.mainWinH,
              child: Container(
                decoration: BoxDecoration(
                  color: QC.black,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: qOuterShadow(QShadow.win),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    _glassHead(tabIndex == 0),
                    _searchBand(),
                    _iconBand(tabIndex, interactive),
                    _tabArea(tabIndex, groupTap),
                    // 指示三角：底边与图标栏底部黄色边线（y138）齐平，不再越线。
                    // 三个 tab 均分 242px：49 / 130 / 211。
                    Positioned(
                      left: 49 + 81.0 * tabIndex,
                      top: S.glassHeadH + S.searchBandH + S.iconBandH - 9,
                      child: const QTriangle(
                        width: 12,
                        height: 7,
                        dir: QTriDir.up,
                        color: QC.yellow,
                      ),
                    ),
                    _sliderBand(),
                    _newsBar(onMainMenuTap),
                    if (isMenu) _gearMenu(),
                  ],
                ),
              ),
            ),
            // 左上角「相框 + 小提琴 / 枫叶」装饰：canvas 外壳，四态共用，
            // z 序高于窗口以覆盖标题栏左侧；超出顶部的部分由 hardEdge 裁掉。
            Positioned(
              left: 0,
              top: -24,
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: -3 * math.pi / 180,
                  child: SizedBox(
                    width: 120,
                    height: 130,
                    child: CustomPaint(
                      painter: _AvatarDecoPainter(
                        avatarIndex: staticPreview ? null : myAvatarIndex,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 玻璃头 82
  Widget _glassHead(bool showUnread) {
    return Positioned(
      left: 0,
      top: 0,
      width: S.mainWinW,
      height: S.glassHeadH,
      child: Stack(
        children: [
          // 36px 以下硬切：深蓝黑（CSS 44% 硬切，用两个 Container 叠放实现）
          Positioned(
            left: 0,
            right: 0,
            top: 36,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: vg([QC.headDark, QC.headDarkBottom]),
              ),
            ),
          ),
          // 36px 上部：底层纵向青绿 + 上层横向「左亮右暗」
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 36,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      // 34%/44% 换算到 36px 容器：34/44≈.773、44/44=1
                      gradient: vg(
                        [QC.headTop, QC.headMid, QC.headBottom],
                        const [0, .773, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      // 仅保留左侧青色高光；右侧的黑色背景阴影按要求去掉。
                      gradient: hg(
                        [const Color(0x2196C8D2), const Color(0x00000000)],
                        const [0, .46],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 顶部 1px 高光 rgba(255,255,255,.17)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: ColoredBox(color: Color(0x2BFFFFFF)),
          ),
          // QQ 字标：居中 top9，14/800，字距 .5，白色带黑描边感
          Positioned(
            left: 0,
            right: 0,
            top: 9,
            child: Text(
              'QQ',
              textAlign: TextAlign.center,
              style: QText.of(
                14,
                weight: FontWeight.w800,
                letterSpacing: .5,
                shadows: const [
                  Shadow(color: Color(0xF2000000), blurRadius: 2),
                  Shadow(
                    color: Color(0xE6000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // 窗口按钮 right8 top9 gap5，3 个 16x16 细线图标。
          // WindowButtonRow 会给每个按钮（含末位）追加 gap 的右内边距，故 right 少设
          // 5px 补偿，令按钮可见边界正好落在 CSS 的 right:8 处。
          Positioned(
            right: 3,
            top: 9,
            child: WindowButtonRow(
              kinds: const [
                QWinBtnKind.gear,
                QWinBtnKind.minimize,
                QWinBtnKind.close,
              ],
              gap: 5,
              size: 16,
              color: QC.mainWbtn,
              strokeWidth: 1.6,
              // 齿轮是「系统设置」快捷键；主菜单只由左下角企鹅球打开。
              onTap: onWindowButton,
            ),
          ),
          // 昵称 wzw：left12 top47
          Positioned(
            left: 12,
            top: 47,
            child: Text(
              'wzw',
              style: QText.of(
                14,
                weight: FontWeight.w700,
                shadows: _headShadow,
              ),
            ),
          ),
          // 状态行：right9 top46，未读数仅 friends 态可见（占位隐藏防漂移）
          Positioned(
            right: 9,
            top: 46,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const GreenDot(size: 11),
                const SizedBox(width: 5),
                Text(
                  '在线',
                  style: QText.of(
                    14,
                    weight: FontWeight.w700,
                    color: const Color(0xFFF2F6F8),
                    shadows: _headShadow,
                  ),
                ),
                const SizedBox(width: 5),
                const QTriangle(
                  width: 9,
                  height: 6,
                  dir: QTriDir.down,
                  color: Color(0xFFDFE6EA),
                ),
                const SizedBox(width: 5),
                const EnvelopeIcon(width: 17, height: 15),
                const SizedBox(width: 5),
                Visibility(
                  visible: showUnread,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(
                    '2',
                    style: QText.of(
                      13,
                      weight: FontWeight.w700,
                      color: const Color(0xFFF2F6F8),
                      shadows: _headShadow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 个性签名：left12 top64
          Positioned(
            left: 12,
            top: 64,
            width: 248,
            child: Text(
              '若不在连，请留言或邮件至',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QText.of(12, color: QC.sign, shadows: _headShadow),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 搜索栏 28
  Widget _searchBand() => Positioned(
    left: 0,
    top: S.glassHeadH,
    width: S.mainWinW,
    height: S.searchBandH,
    child: Container(
      decoration: BoxDecoration(
        gradient: vg([QC.searchBandTop, QC.searchBandBottom]),
        border: const Border(
          top: BorderSide(color: QC.searchBandBorder, width: 1),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: S.searchPillLeft,
            top: 3,
            child: Container(
              width: S.searchPillW,
              height: S.searchPillH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: vg([QC.white, const Color(0xFFE6EAEC)]),
                border: Border.all(color: const Color(0x8C788287), width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // inset 顶部阴影
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: vg(const [
                          Color(0x40000000),
                          Color(0x00000000),
                        ]),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: _SearchInput(
                      initial: searchQuery,
                      onChanged: onSearchChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            top: 4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAddTap,
              child: const PlusIcon(size: 18),
            ),
          ),
        ],
      ),
    ),
  );

  // ---------------------------------------------------------------- 图标栏 28
  Widget _iconBand(int tabIndex, bool interactive) {
    final List<Color> sel = tabIndex == 2
        ? const [QC.tabOrangeTop, QC.tabOrangeBottom]
        : const [QC.tabYellowTop, QC.tabYellowBottom];
    const List<Color> white = [QC.tabWhiteTop, QC.tabWhiteBottom];
    return Positioned(
      left: 0,
      top: S.glassHeadH + S.searchBandH,
      width: S.mainWinW,
      height: S.iconBandH,
      child: Container(
        decoration: BoxDecoration(
          gradient: vg([QC.iconBandTop, QC.iconBandBottom]),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 15,
              right: 15,
              top: 0,
              height: S.iconBandH,
              child: Row(
                children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: (interactive && onTabChanged != null)
                            ? () => onTabChanged!(i)
                            : null,
                        child: Center(
                          child: Transform.translate(
                            offset: const Offset(0, -2),
                            child: SizedBox(
                              width: S.tabIconBox,
                              height: S.tabIconBox,
                              child: CustomPaint(
                                painter: _TabIconPainter(
                                  i,
                                  i == tabIndex ? sel : white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: S.yellowLineH,
              child: const ColoredBox(color: QC.yellow),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tab 页 410
  /// 三个 tab 页共用一块 410 高的列表区，页间切换用 [TabFlip] 做 3D 翻转：
  /// 向右切换（索引增大）正向翻转，向左切换反向翻转。
  /// 竹叶背景是整个列表区的「背景布」，三个页面都浮在其上。
  Widget _tabArea(int tabIndex, ValueChanged<String>? groupTap) {
    return Positioned(
      left: 0,
      top: S.glassHeadH + S.searchBandH + S.iconBandH,
      width: S.mainWinW,
      height: S.bambooH,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(color: QC.bambooBg),
        child: Stack(
          children: [
            const Positioned.fill(child: BambooBackdrop()),
            TabFlip(
              index: tabIndex,
              pages: [
                _friendsPage(groupTap),
                _groupsPage(),
                _recentPage(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------- tab0 · 好友列表
  /// 页骨架 = [QScrollList]：内容列可滚动（滚轮 / 拖拽拇指），右侧滚动条联动。
  Widget _friendsPage(ValueChanged<String>? groupTap) {
    final q = searchQuery.trim().toLowerCase().replaceAll(' ', '');
    final all = friends ?? _friends;
    final groups = friendGroups ??
        <QFriendGroup>[
          for (final label in _grpLabels) QFriendGroup(label, _friends),
        ];
    bool matches(QFriend f) =>
        f.name.toLowerCase().contains(q) ||
        f.sig.toLowerCase().contains(q) ||
        (_pinyin[f.name] ?? '').replaceAll(' ', '').contains(q);
    final rows = q.isEmpty ? all : all.where(matches).toList();
    // 画廊固定展示「大学好友」展开态；交互态由 expandedGroup 驱动。
    final String? openGroup = staticPreview ? '大学好友(21/66)' : expandedGroup;

    final Widget list;
    if (q.isNotEmpty) {
      // 搜索态：只列匹配的好友，不带分组标题。
      list = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in rows) _friendRow(f),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 12),
              child: Text('没有找到匹配的好友', style: QText.of(12, color: QC.fsig)),
            ),
        ],
      );
    } else {
      // 分组态：六个分组依次排列，好友行插在「当前展开的分组」下方。
      list = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in groups) ...[
            _group(
              g.label,
              open: g.label == openGroup,
              hi: g.label == openGroup,
              onTap: groupTap == null ? null : () => groupTap(g.label),
            ),
            if (g.label == openGroup)
              for (final f in (q.isEmpty
                  ? g.members
                  : g.members.where(matches).toList())) _friendRow(f),
          ],
        ],
      );
    }

    return QScrollList(child: list);
  }

  // -------------------------------------------------- tab1 · 群组列表
  Widget _groupsPage() {
    return QScrollList(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final g in _groups) _groupRow(g),
          if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 12),
              child: Text('还没有加入任何群组', style: QText.of(12, color: QC.fsig)),
            ),
        ],
      ),
    );
  }

  /// 群组行：双击打开同名聊天窗；悬停高亮。
  Widget _groupRow(_Group g) {
    final open = menuOpen ? null : onFriendTap;
    return QListRow(
      avatar: Container(
        decoration: BoxDecoration(gradient: vg([g.bg, g.bgDark])),
        alignment: Alignment.center,
        child: Text(
          g.badge ? 'icon' : g.name.characters.first,
          style: g.badge
              ? QText.of(11, weight: FontWeight.w800)
              : QText.of(17, weight: FontWeight.w800),
        ),
      ),
      title: '${g.name}(${g.count})',
      subtitle: g.sig,
      onOpen: open == null ? null : () => open(g.name),
    );
  }

  // -------------------------------------------------- tab2 · 最近消息
  /// 竹叶背景已上移为整个列表区的背景布；本页保留 iconFans 标题条 + 消息行。
  /// 标题条固定不滚动，消息行区域可滚动并与右侧滚动条联动。
  Widget _recentPage() {
    return SizedBox(
      width: S.mainWinW,
      height: S.bambooH,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 30,
            child: QScrollList(
              height: S.bambooH - 30,
              topPadding: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in _recents) _recentRow(m),
                  if (_recents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 14, top: 12),
                      child: Text('暂无消息', style: QText.of(12, color: QC.fsig)),
                    ),
                ],
              ),
            ),
          ),
          _bgtitle(),
        ],
      ),
    );
  }

  /// 消息行：双击打开同名聊天窗；悬停高亮；未读行加粗 + 红点徽标。
  Widget _recentRow(_Recent m) {
    final open = menuOpen ? null : onFriendTap;
    return QListRow(
      avatar: AvatarPlaceholder(
        size: S.friendAvatar,
        bg: m.bg,
        skin: m.skin,
        hair: m.hair,
      ),
      title: m.name,
      subtitle: m.preview,
      titleColor: m.unread ? QC.white : const Color(0xFFDDE6EB),
      subtitleColor: m.unread ? QC.newsSig : QC.fsig,
      trailingTop: Text(
        m.time,
        style: QText.of(10, color: const Color(0xFF8D9AA2)),
      ),
      trailingBottom: m.unread ? const _UnreadBadge() : null,
      onOpen: open == null ? null : () => open(m.name),
    );
  }

  Widget _bgtitle() => Positioned(
    left: 6,
    top: 4,
    width: 258,
    height: 20,
    child: Container(
      decoration: BoxDecoration(
        gradient: hg(const [Color(0xF0262C22), Color(0xE008181A)]),
        border: const Border(bottom: BorderSide(color: QC.yellow, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 20,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: vg(const [Color(0xFFD94B3A), Color(0xFF8D2A20)]),
            ),
            alignment: Alignment.center,
            child: Text(
              'icon',
              style: QText.of(9, weight: FontWeight.w700, letterSpacing: -.5),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'iconFans | 国标粉丝(2)',
            style: QText.of(
              11,
              weight: FontWeight.w700,
              color: const Color(0xFFEEF2F0),
            ),
          ),
        ],
      ),
    ),
  );

  // -------------------------------------------------- 好友列表辅助
  /// 设计稿提示「输入英文或者拼音进行搜索」，故按昵称 / 签名 / 拼音全拼过滤。
  static const Map<String, String> _pinyin = {
    '阿澈': 'a che',
    '周小满': 'zhou xiao man',
    '苏禾': 'su he',
    '林岚': 'lin lan',
    '陈默': 'chen mo',
    '何小满': 'he xiao man',
  };

  Widget _group(
    String text, {
    bool open = false,
    bool hi = false,
    VoidCallback? onTap,
  }) {
    final row = Container(
      height: hi ? 30 : S.friendGroupH,
      padding: const EdgeInsets.only(left: 12),
      decoration: hi
          ? const BoxDecoration(
              color: QC.selGroup,
              border: Border(bottom: BorderSide(color: QC.yellow, width: 1)),
            )
          : null,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          QTriangle(
            width: open ? 10 : 7,
            height: open ? 7 : 10,
            dir: open ? QTriDir.down : QTriDir.right,
            color: QC.grpArrow,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: QText.of(12.5, weight: FontWeight.w700, shadows: _grpShadow),
          ),
        ],
      ),
    );
    return onTap == null
        ? row
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: row,
          );
  }

  /// 折叠态分组行已并入 _friendsPage 的统一分组列表，不再单独渲染。

  /// 好友行：双击打开聊天窗；悬停高亮；选中行黄框 + 图钉角标。
  Widget _friendRow(_Friend f) {
    final bool sel = selectedName == null ? f.sel : selectedName == f.name;
    final open = menuOpen ? null : onFriendTap;
    return QListRow(
      avatar: AvatarPlaceholder(
        size: S.friendAvatar,
        bg: f.bg,
        skin: f.skin,
        hair: f.hair,
      ),
      title: f.name,
      subtitle: f.sig,
      selected: sel,
      trailingTop: sel ? const _Pin() : null,
      trailingTopOffset: const Offset(10, 5),
      onOpen: open == null ? null : () => open(f.name),
    );
  }

  // ---------------------------------------------------------------- 滑块栏 26
  Widget _sliderBand() => Positioned(
    left: 0,
    top: S.mainWinH - S.sliderBandH - S.newsBarH,
    width: S.mainWinW,
    height: S.sliderBandH,
    child: Container(
      decoration: BoxDecoration(
        gradient: vg([QC.sliderTop, QC.sliderBottom]),
        border: const Border(top: BorderSide(color: QC.sliderBorder, width: 1)),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 12,
            top: 6,
            child: SizedBox(
              width: 13,
              height: 13,
              child: CustomPaint(painter: _SizeIconPainter()),
            ),
          ),
          Positioned(
            left: 34,
            top: 11,
            child: Container(
              width: 186,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: const Color(0xFF1D2023),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: const [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 1,
                    child: ColoredBox(color: Color(0x1FFFFFFF)),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: S.knobLeft,
            top: 6,
            child: Container(
              width: 13,
              height: 13,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-.3, -.4),
                  colors: [QC.knobTop, QC.knobMid, QC.knobBottom],
                  stops: [0, .6, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            right: 10,
            top: 6,
            child: SizedBox(
              width: 16,
              height: 14,
              child: CustomPaint(painter: _BrushPainter()),
            ),
          ),
        ],
      ),
    ),
  );

  // ---------------------------------------------------------------- 新闻条 39
  Widget _newsBar(VoidCallback? onMainMenuTap) => Positioned(
    left: 0,
    top: S.mainWinH - S.newsBarH,
    width: S.mainWinW,
    height: S.newsBarH,
    child: Container(
      decoration: BoxDecoration(gradient: vg([QC.newsTop, QC.newsBottom])),
      child: Stack(
        children: [
          // 顶部 inset 黑线（文字背后无任何背景块）
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: ColoredBox(color: Color(0x8C000000)),
          ),
          // 左下角企鹅球 = 主菜单按钮（唯一打开入口）。
          Positioned(
            left: 5,
            top: 5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMainMenuTap,
              child: const PenguinBall(size: 30),
            ),
          ),
          Positioned(
            left: 49,
            top: 5,
            width: 208,
            child: Text.rich(
              TextSpan(
                style: QText.of(10.5, color: QC.newsText).copyWith(height: 1.5),
                children: const [
                  TextSpan(
                    text: '刘冠华',
                    style: TextStyle(
                      color: Color(0xFFEEF2F4),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' 14分钟前更新了个性签名:'),
                  TextSpan(text: '\n'),
                  TextSpan(
                    text: '忘不了，真的忘不了，我该用什么…',
                    style: TextStyle(color: QC.newsSig),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    ),
  );

  // ------------------------------------------------------------ 齿轮菜单 V6.1
  Widget _gearMenu() => Positioned(
    left: 0,
    bottom: 0,
    width: S.menuW,
    height: S.menuH,
    // 菜单内部点击由本层吸收，不触发外层「点击外部关闭」。
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: BlurPanel(
        width: S.menuW,
        height: S.menuH,
        radiusTop: S.menuRadiusTop,
        radiusBottom: S.menuRadiusBottom,
        sigma: S.menuBlurSigma,
        background: const [QC.menuA, QC.menuB, QC.menuC],
        borderColor: QC.menuBorder,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _menuSection('设置', const ['系统设置', '个人设置']),
                  _menuSep(),
                  _menuSection('管理', const ['好友管理', '我的 Qzone']),
                  _menuSep(),
                  _menuSection('帮助', const ['关于 QQ']),
                ],
              ),
            ),
            // 底部条 43px：两按钮各 50%，无左侧圆形头像按钮
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: S.menuFootH,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [QC.menuFootA, QC.menuFootB],
                  ),
                  border: Border(
                    top: BorderSide(color: Color(0x47FFFFFF), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    for (final label in const ['更换用户', '退出'])
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onFooterAction == null
                              ? null
                              : () => onFooterAction!(label),
                          child: Container(
                            decoration: label == '更换用户'
                                ? const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                        color: Color(0x333C382C),
                                        width: 1,
                                      ),
                                    ),
                                  )
                                : null,
                            alignment: Alignment.center,
                            child: Transform.translate(
                              offset: const Offset(0, S.menuFootTextShift),
                              child: Text(label, style: QText.menuFoot),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _menuSection(String title, List<String> items) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 14, top: 13, bottom: 5),
        child: Text(title, style: QText.menuTitle),
      ),
      for (final it in items)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMenuAction == null ? null : () => onMenuAction!(it),
          child: Container(
            height: S.menuItemH,
            padding: const EdgeInsets.only(left: 32),
            alignment: Alignment.centerLeft,
            child: Text(it, style: QText.menuItem),
          ),
        ),
    ],
  );

  Widget _menuSep() => Padding(
    padding: const EdgeInsets.only(left: 14, right: 14, top: 8),
    child: SizedBox(
      width: double.infinity,
      height: 2,
      child: Stack(
        children: const [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: ColoredBox(color: QC.menuSepLight),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 1,
            height: 1,
            child: ColoredBox(color: QC.menuSepDark),
          ),
        ],
      ),
    ),
  );
}

/// 搜索胶囊：空态保留设计稿的静态提示文字，输入后切换为真实 TextField。
class _SearchInput extends StatefulWidget {
  const _SearchInput({required this.initial, this.onChanged});

  final String initial;
  final ValueChanged<String>? onChanged;

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initial);
    _ctl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _SearchInput old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial && widget.initial != _ctl.text) {
      _ctl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (_ctl.text.isEmpty)
        Positioned(
          left: 11,
          top: 3,
          child: Text('输入英文或者拼音进行搜索', style: QText.searchHint),
        ),
      Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.only(left: 11, right: 24, bottom: 2),
          child: TextField(
            controller: _ctl,
            onChanged: widget.onChanged,
            style: QText.of(12, color: const Color(0xFF2B3136)),
            cursorColor: const Color(0xFF4A5155),
            cursorWidth: 1,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    ],
  );
}

/// 与 [QFriend] 同构：API 模式直接用状态层传进来的好友数据。
typedef _Friend = QFriend;

/// 群组列表行数据（tab1）。
class _Group {
  const _Group(
    this.name,
    this.count,
    this.sig,
    this.bg,
    this.bgDark, [
    this.badge = false,
  ]);
  final String name;
  final int count;
  final String sig;
  final Color bg;
  final Color bgDark;

  /// IconFans 用「icon」红标徽章样式，其余群取群名首字。
  final bool badge;
}

/// 最近消息行数据（tab2 · IconFans 群消息）。
class _Recent {
  const _Recent(
    this.name,
    this.preview,
    this.time,
    this.bg,
    this.skin,
    this.hair, [
    this.unread = false,
  ]);
  final String name;
  final String preview;
  final String time;
  final Color bg;
  final Color skin;
  final Color hair;
  final bool unread;
}

/// 未读小红点徽标（14x14）。
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE8574C), Color(0xFFB01E14)],
      ),
      border: Border.all(color: const Color(0xFF7A120B), width: 1),
    ),
    alignment: Alignment.center,
    child: Text('1', style: QText.of(9, weight: FontWeight.w800)),
  );
}

/// 选中行右侧图钉（14x18 主体 + 下方 2x6 针脚）
class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    height: 23,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            width: 14,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(3),
              ),
              gradient: vg(const [Color(0xFFEEF3F5), Color(0xFFAEBAC1)]),
            ),
          ),
        ),
        const Positioned(
          left: 6,
          top: 17,
          child: SizedBox(
            width: 2,
            height: 6,
            child: ColoredBox(color: Color(0xFFCDD6DA)),
          ),
        ),
      ],
    ),
  );
}

/// 三个 tab 图标（24x24 画布，SVG 路径等价绘制）
class _TabIconPainter extends CustomPainter {
  const _TabIconPainter(this.index, this.fill);
  final int index;
  final List<Color> fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..shader = vg(fill).createShader(const Rect.fromLTWH(0, 0, 24, 24));
    switch (index) {
      case 0:
        // 圆角对话气泡 + 下方小尖角
        canvas.drawPath(
          Path()
            ..moveTo(7, 4)
            ..lineTo(19, 4)
            ..arcToPoint(const Offset(22, 7), radius: const Radius.circular(3))
            ..lineTo(22, 16)
            ..arcToPoint(const Offset(19, 19), radius: const Radius.circular(3))
            ..lineTo(10.5, 19)
            ..lineTo(6, 22)
            ..lineTo(6, 19)
            ..lineTo(7, 19)
            ..arcToPoint(const Offset(4, 16), radius: const Radius.circular(3))
            ..lineTo(4, 7)
            ..arcToPoint(const Offset(7, 4), radius: const Radius.circular(3))
            ..close(),
          p,
        );
        break;
      case 1:
        // 两个白色重叠气泡
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4, 14, 11),
            Radius.circular(5.5),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6, 13)
            ..lineTo(6, 17)
            ..lineTo(9.5, 14)
            ..close(),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(9, 8, 13, 11),
            Radius.circular(5.5),
          ),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(11, 17)
            ..lineTo(11, 21)
            ..lineTo(14.5, 18)
            ..close(),
          p,
        );
        break;
      case 2:
        // 白色时钟：圆 + 两根指针
        canvas.drawCircle(const Offset(12, 12), 8.6, p);
        final hand = Paint()
          ..color = const Color(0xFF39424A)
          ..strokeWidth = 1.7
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(12, 7.5)
            ..lineTo(12, 12)
            ..lineTo(16, 12),
          hand,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TabIconPainter old) =>
      old.index != index || old.fill != fill;
}

/// 竹叶动态背景（对齐 HTML leaves SVG：远景虚化叶、中景竹枝、近景锐利叶簇）
/// 滑块栏左侧 13x13 虚线方框 + 内部 6x6 实心方块
class _SizeIconPainter extends CustomPainter {
  const _SizeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFCFD4D6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const double dash = 2.2;
    const double gap = 1.8;
    void dashLine(Offset a, Offset b) {
      final double d = (b - a).distance;
      final Offset u = (b - a) / d;
      double t = 0;
      while (t < d) {
        final double e = (t + dash) > d ? d : t + dash;
        canvas.drawLine(a + u * t, a + u * e, p);
        t += dash + gap;
      }
    }

    dashLine(const Offset(.75, .75), const Offset(12.25, .75));
    dashLine(const Offset(12.25, .75), const Offset(12.25, 12.25));
    dashLine(const Offset(12.25, 12.25), const Offset(.75, 12.25));
    dashLine(const Offset(.75, 12.25), const Offset(.75, .75));
    canvas.drawRect(
      const Rect.fromLTWH(3, 2, 6, 6),
      Paint()..color = const Color(0xFFCFD4D6),
    );
  }

  @override
  bool shouldRepaint(covariant _SizeIconPainter old) => false;
}

/// 滑块栏右侧刷子图标（16x14）
class _BrushPainter extends CustomPainter {
  const _BrushPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16, size.height / 14);
    canvas.drawPath(
      Path()
        ..moveTo(2, 12)
        ..cubicTo(2, 9, 4, 8, 6, 8)
        ..lineTo(12, 1)
        ..lineTo(15, 4)
        ..lineTo(8, 10)
        ..cubicTo(8, 12, 6, 13, 4, 13)
        ..close(),
      Paint()..color = const Color(0xFFE8ECEE),
    );
  }

  @override
  bool shouldRepaint(covariant _BrushPainter old) => false;
}

/// 主面板左上角「相框 + 小提琴 / 枫叶」装饰（对应 CSS .avatar-deco）。
/// canvas 直接子元素，四态共用，覆盖标题栏左侧。
/// 局部坐标 120x130，由 Positioned(top:-24) 映射：canvas y = 局部 y - 24。
/// 单个 painter 依次画：撕裂羊皮纸相框 → 深蓝照片 → 手写波浪线 → 橙棕枫叶 → 琴弓。
class _AvatarDecoPainter extends CustomPainter {
  const _AvatarDecoPainter({this.avatarIndex});

  /// 内置头像下标；null = 画 V6.1 默认剪影（画廊 / 未设置头像 / 外链）。
  final int? avatarIndex;

  // 确定性的「撕裂」噪声（sin 叠加），避免每次重绘抖动
  static double _noise(double s) =>
      0.55 * math.sin(s) +
      0.30 * math.sin(2.37 * s + 1.1) +
      0.15 * math.sin(4.13 * s + 2.7);

  // 上下边缘锯齿幅度大、左右边缘轻微，等价于 feTurbulence + feDisplacementMap
  Path _tornRect(double l, double t, double r, double b) {
    const double step = 3.5;
    final p = Path();
    double n = 0;
    p.moveTo(l, t + 2.5 * _noise(n));
    for (double x = l + step; x < r; x += step) {
      n += 1.13;
      p.lineTo(x, t + 2.5 * _noise(n));
    }
    p.lineTo(r, t + 2.5 * _noise(n + 1.13));
    for (double y = t + step; y < b; y += step) {
      n += 1.07;
      p.lineTo(r + 1.6 * _noise(n), y);
    }
    p.lineTo(r + 1.6 * _noise(n + 1.07), b);
    for (double x = r - step; x > l; x -= step) {
      n += 1.31;
      p.lineTo(x, b + 4.5 * _noise(n));
    }
    p.lineTo(l, b + 4.5 * _noise(n + 1.31));
    for (double y = b - step; y > t; y -= step) {
      n += 0.97;
      p.lineTo(l + 1.6 * _noise(n), y);
    }
    p.close();
    return p;
  }

  void _wave(Canvas c, double y, Paint p, int seed) {
    final path = Path()..moveTo(30, y);
    for (double x = 34; x <= 97; x += 4) {
      path.lineTo(x, y + 1.15 * math.sin(x * .55 + seed * 1.3));
    }
    c.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ---- 相框：米黄羊皮纸（parch #E2CC9C→#CDB27E→#A98C5E）+ 撕裂锯齿 ----
    final frame = _tornRect(25, 6, 102, 96); // canvas x25..102, y-18..72
    canvas.drawPath(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE2CC9C), Color(0xFFCDB27E), Color(0xFFA98C5E)],
          stops: [0, .6, 1],
        ).createShader(const Rect.fromLTWH(25, 6, 77, 90))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, .4), // 0.4px 虚化
    );
    canvas.drawPath(
      frame,
      Paint()
        ..color = const Color(0xFF8A7048)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 羊皮纸乐谱纹理：上方数条（中间被照片盖住，仅两侧露出）
    final ink = Paint()
      ..color = const Color(0x8C7C643E)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      _wave(canvas, 14 + i * 6.0, ink, i);
    }

    // ---- 内嵌深蓝照片（photoG 纵向叠加）----
    const Rect photo = Rect.fromLTRB(38, 6, 90, 72); // canvas x38..90, y-18..48
    canvas.drawRect(photo, Paint()..color = const Color(0xFF0A1636));
    canvas.drawRect(
      photo,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8012306E), Color(0xB3040A20)],
        ).createShader(photo),
    );
    // 默认头像剪影：半圆肩 + 蓝色圆形头（外圈 + 略亮内圈）
    // 注册时选了内置头像的用户画自绘矢量头像，其余保持设计稿剪影。
    final avatar = avatarIndex == null
        ? null
        : kQBuiltinAvatars[avatarIndex!.clamp(0, kQBuiltinAvatars.length - 1)];
    if (avatar == null) {
      canvas.drawPath(
        Path()
          ..moveTo(44, 72)
          ..cubicTo(46, 56, 54, 49, 64, 49)
          ..cubicTo(74, 49, 82, 56, 84, 72)
          ..close(),
        Paint()..color = const Color(0xFF12295C),
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(64, 34), width: 24, height: 27),
        Paint()..color = const Color(0xFF1C3F7A),
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(64, 32), width: 15, height: 17),
        Paint()..color = const Color(0xFF2D5590),
      );
    } else {
      // 40x40 头像放大 1.3 倍（52x52）放进照片区，上下留深蓝衬边。
      canvas.save();
      canvas.clipRect(photo);
      canvas.translate(38, 13);
      canvas.scale(1.3, 1.3);
      QAvatarPainter(avatar.bg, avatar.skin, avatar.hair)
          .paint(canvas, const Size(40, 40));
      canvas.restore();
    }

    // ---- 相框下部：3~4 条浅褐色手写波浪纹理线（canvas y≈48..72）----
    for (int i = 0; i < 4; i++) {
      _wave(canvas, 74 + i * 6.0, ink, i + 3);
    }

    // ---- 左侧橙棕枫叶 / 小熊（maple #D28E33→#A05A18→#6E3A0C）----
    final leaf = Path()
      ..moveTo(9, 30)
      ..cubicTo(3, 28, 0, 34, 1, 40)
      ..cubicTo(0, 46, 3, 52, 8, 53)
      ..cubicTo(8, 61, 13, 67, 17, 64)
      ..cubicTo(20, 61, 19, 52, 15, 48)
      ..cubicTo(18, 42, 16, 33, 9, 30)
      ..close();
    canvas.drawPath(
      leaf,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD28E33), Color(0xFFA05A18), Color(0xFF6E3A0C)],
          stops: [0, .6, 1],
        ).createShader(const Rect.fromLTWH(0, 27, 22, 42)),
    );
    canvas.drawPath(
      leaf,
      Paint()
        ..color = const Color(0xFF4E2A08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 两个小黑点眼睛 + 微笑弧线
    final eye = Paint()..color = const Color(0xFF1E1004);
    canvas.drawCircle(const Offset(5.5, 42), 1.3, eye);
    canvas.drawCircle(const Offset(12, 42), 1.3, eye);
    canvas.drawPath(
      Path()
        ..moveTo(5, 47)
        ..cubicTo(7, 51, 11, 51, 13, 47),
      Paint()
        ..color = const Color(0xFF2E1C0A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round,
    );

    // ---- 琴弓：棕色细杆 + 平行白色高光，压在相框与枫叶之上 ----
    // canvas (5,-15)→(78,70) 即局部 (5,9)→(78,94)
    canvas.drawLine(
      const Offset(5, 9),
      const Offset(78, 94),
      Paint()
        ..color = const Color(0xFF8A6232)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      const Offset(7, 7),
      const Offset(80, 92),
      Paint()
        ..color = const Color(0xFFE8E2D2)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarDecoPainter old) =>
      old.avatarIndex != avatarIndex;
}

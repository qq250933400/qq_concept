import 'package:flutter/material.dart';

/// ============================================================================
/// QQ 概念版复刻 · 设计 token
/// 来源：ui-v4.html V6.1（高保真静态稿），全部数值为 canvas / .win 的 1x 逻辑像素。
/// 注意：HTML 里 .stage 是 2x 渲染面，.canvas 才是 1x；不要把 stage 尺寸写进来。
/// ============================================================================

/// 尺寸与坐标
class S {
  // 页面
  static const double pageBg = 0; // 占位，实际颜色见 QC.pageBg

  // 登录窗口：canvas 372x282；.win left0 top42 372x240
  static const double loginCanvasW = 372;
  static const double loginCanvasH = 282;
  static const double loginWinTop = 42;
  static const double loginWinH = 240;
  static const double loginRadius = 10;
  static const double loginTitleH = 34;
  static const double loginFormLeft = 68;
  static const double loginFormTop = 44;
  static const double loginFieldW = 237;
  static const double loginFieldH = 21;
  static const double loginFieldGap = 12;
  static const double loginCbTop = 152;
  static const double loginBtnBottom = 32;
  static const double loginBtnH = 26;
  static const double loginRegLeft = 66;
  static const double loginRegW = 74;
  static const double loginStatusLeft = 187;
  static const double loginStatusW = 56;
  static const double loginLoginLeft = 243;
  static const double loginLoginW = 62;
  static const double loginLeafTop = 24;
  static const double loginCloudClipH = 42;
  static const double loginCloudUseY = 12;
  static const double loginSunCx = 34;
  static const double loginSunCy = 33;
  static const double loginSunR = 27;
  static const double loginSunGlowR = 40;
  static const double cloudScrollSeconds = 26;
  static const double cloudScrollDistance = 372;
  static const double leafSwaySeconds = 6.5;
  static const double leafFloatSeconds = 5.2;

  // 主面板：canvas 272x645；.win left0 top32 272x613（贴到 canvas 底部）
  static const double mainCanvasW = 272;
  static const double mainCanvasH = 645;
  static const double mainWinTop = 32;
  static const double mainWinH = 613;
  static const double mainWinW = 272;
  static const double glassHeadH = 82;
  static const double searchBandH = 28; // top 82
  static const double iconBandH = 28; // top 110
  static const double bambooH = 410; // top 138（列表区含竹叶整体背景）
  static const double sliderBandH = 26; // top 548
  static const double newsBarH = 39; // top 574，底部贴合窗口底
  static const double yellowLineH = 2;
  static const double tabIconBox = 24;
  static const double searchPillLeft = 10;
  static const double searchPillW = 226;
  static const double searchPillH = 21;
  static const double knobLeft = 210;
  static const double friendRowH = 50;
  static const double friendGroupH = 26;
  static const double friendAvatar = 40;
  static const double vScrollW = 14;

  // 齿轮菜单（V6.1）
  static const double menuW = 186;
  static const double menuH = 317;
  static const double menuRadiusTop = 12;
  static const double menuRadiusBottom = 10;
  static const double menuFootH = 43;
  static const double menuFootFont = 12.5;
  static const double menuFootTextShift = 3;
  static const double menuBlurCssPx = 20; // CSS backdrop-filter: blur(20px)
  static const double menuBlurSigma = 10; // Flutter sigma 约为 CSS blur 半径的一半
  static const double menuItemH = 26;

  // 聊天窗口
  static const double chatW = 490;
  static const double chatH = 435;
  static const double chatTitleH = 62;
  static const double chatMsgH = 238;
  static const double chatYLineH = 2;
  static const double chatToolbarH = 24;
  static const double chatInputH = 109;
  static const double chatSendW = 72;
  static const double chatSendH = 88;

  // 好友管理木质桌面
  static const double fmW = 959;
  static const double fmH = 597;
  static const double fmTitleH = 30;
  static const double fmBar2H = 32;
  static const double fmYLineH = 2;
  static const double fmWoodH = 533;
  static const double fCardSize = 66;
  static const double fCardRadius = 14;
  static const double plateW = 54;
  static const double plateH = 14;

  // 设置 / 关于
  static const double settingsW = 268;
  static const double settingsH = 645;
  static const double settingsBarH = 32;
  static const double aboutW = 357;
  static const double aboutH = 160;
  static const double dlgBarH = 30;
  static const double dlgFootH = 35;
  static const double dlgRadius = 8;
  static const double metalBtnH = 23;
  static const double metalBtnMinW = 76;
  static const double dlgBtnSize = 15;

  // 注册窗口
  static const double regW = 480;
  static const double regH = 470;
}

/// 颜色（全部取自 ui-v4.html 原文）
class QC {
  static const Color pageBg = Color(0xFF17191C);
  static const Color pageText = Color(0xFFCFD6DA);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color pageBorder = Color(0xFF2E2E2E);

  // 登录
  static const Color loginWinTop = Color(0xFF12303E);
  static const Color loginWinMid = Color(0xFF0B2030);
  static const Color loginWinBottom = Color(0xFF071824);
  static const Color loginTitleTop = Color(0xFF234858);
  static const Color loginTitleMid = Color(0xFF173543);
  static const Color loginTitleBottom = Color(0xFF0B2230);
  static const Color loginWbtn = Color(0xFF7D97A4);
  static const Color beigeTop = Color(0xFFF4F1E8);
  static const Color beigeMid = Color(0xFFCFCABA);
  static const Color beigeBottom = Color(0xFFBDB8A9);
  static const Color beigeBorder = Color(0xFF7E7A6C);
  static const Color beigeText = Color(0xFF2D2D2D);
  static const Color pillTop = Color(0xFFFFFFFF);
  static const Color pillBottom = Color(0xFFE3E7EA);
  static const Color caretGray = Color(0xFFB9BDC1);
  static const Color checkTop = Color(0xFF7FC23E);
  static const Color checkBottom = Color(0xFF3F8C1C);
  static const Color checkBorder = Color(0xFF2B5A1E);
  static const Color greenDotTop = Color(0xFFB8F08A);
  static const Color greenDotMid = Color(0xFF4CAE2E);
  static const Color greenDotBottom = Color(0xFF2E7C18);
  static const Color sunCore = Color(0xFFFFF3B0);
  static const Color sunMid = Color(0xFFFBCF4A);
  static const Color sunEdge = Color(0xFFE8951D);
  static const Color sunGlow = Color(0xFFF7C948);
  static const Color cloudTop = Color(0xFFF7F7F7);
  static const Color cloudBottom = Color(0xFFA9AEB4);
  static const Color leaf1Top = Color(0xFF84D466);
  static const Color leaf1Bottom = Color(0xFF2F8A2A);
  static const Color leaf2Top = Color(0xFF5FBE50);
  static const Color leaf2Bottom = Color(0xFF217A25);
  static const Color leafDark1 = Color(0xFF2A7A2C);
  static const Color leafDark2 = Color(0xFF205F23);
  static const Color leafDark3 = Color(0xFF236826);
  static const Color flower = Color(0xFFFDFDF8);
  static const Color flowerCore = Color(0xFFF3C53C);

  // 主面板
  static const Color headTop = Color(0xFF2D5763);
  static const Color headMid = Color(0xFF274A57);
  static const Color headBottom = Color(0xFF21414D);
  static const Color headDark = Color(0xFF0A2130);
  static const Color headDarkBottom = Color(0xFF071B2A);
  static const Color searchBandTop = Color(0xFF454A4D);
  static const Color searchBandBottom = Color(0xFF363B3E);
  static const Color searchBandBorder = Color(0xFF181D20);
  static const Color iconBandTop = Color(0xFF4D5255);
  static const Color iconBandBottom = Color(0xFF383D40);
  static const Color bambooBg = Color(0xFF00101B);
  static const Color bambooRadial = Color(0xFF032330);
  static const Color sliderTop = Color(0xFF3F4141);
  static const Color sliderBottom = Color(0xFF353636);
  static const Color sliderBorder = Color(0xFF222425);
  static const Color newsTop = Color(0xFF363B3F);
  static const Color newsBottom = Color(0xFF2A2E31);
  static const Color yellow = Color(0xFFFAD402);
  static const Color tabWhiteTop = Color(0xFFFFFFFF);
  static const Color tabWhiteBottom = Color(0xFFB7C1C8);
  static const Color tabYellowTop = Color(0xFFFFD257);
  static const Color tabYellowBottom = Color(0xFFD98A06);
  static const Color tabOrangeTop = Color(0xFFF6BD35);
  static const Color tabOrangeBottom = Color(0xFFC46A08);
  static const Color mainWbtn = Color(0xFF5C7682);
  static const Color sign = Color(0xFF8299A6);
  static const Color searchHint = Color(0xFF7C8489);
  static const Color plusCross = Color(0xFF79848A);
  static const Color plusShade = Color(0xFF3F484D);
  static const Color grpArrow = Color(0xFF39B54A);
  static const Color envTop = Color(0xFFFBFDFF);
  static const Color envMid = Color(0xFFD3DDE3);
  static const Color envBottom = Color(0xFF8496A0);
  static const Color folderTop = Color(0xFFF8CF5C);
  static const Color folderMid = Color(0xFFD69B2E);
  static const Color folderBottom = Color(0xFF9C6818);
  static const Color newsText = Color(0xFFC7CDD1);
  static const Color newsSig = Color(0xFFDFE6E2);
  static const Color knobTop = Color(0xFFF2F2F2);
  static const Color knobMid = Color(0xFF9AA1A5);
  static const Color knobBottom = Color(0xFF5F6569);

  // 好友列表
  static const Color fname = Color(0xFFF2F7FA);
  static const Color fsig = Color(0xFFA9BCC6);
  static const Color selRow = Color(0xFF4B4D16);
  static const Color selGroup = Color(0xFF4A4C14);
  static const Color rowHover = Color(0x2696C8D2); // rgba(150,200,210,.15) 行悬停
  static const Color rowSep = Color(0x14FFFFFF); // 行分隔线
  static const Color vScrollBg = Color(0xFF080F16);
  static const Color vScrollBorder = Color(0xFF0E1B24);
  static const Color thumbLeft = Color(0xFFB6BFC5);
  static const Color thumbRight = Color(0xFF7B868D);
  static const Color scrollArrow = Color(0xFF8D9AA2);

  // 齿轮菜单 V6.1
  static const Color menuA = Color(0xB3E4E0D2); // rgba(228,224,210,.70)
  static const Color menuB = Color(0xA8D2CDBD); // rgba(210,205,189,.66)
  static const Color menuC = Color(0xB8BEB8A4); // rgba(190,184,164,.72)
  static const Color menuBorder = Color(0xB33A3830); // rgba(58,56,48,.70)
  static const Color menuFootA = Color(0xDB928768); // rgba(146,135,104,.86)
  static const Color menuFootB = Color(0xE67A7056); // rgba(122,112,86,.90)
  static const Color menuFootText = Color(0xFF1E1E1A);
  static const Color menuTitle = Color(0xFF262622);
  static const Color menuItem = Color(0xFF35342E);
  static const Color menuSepLight = Color(0x8CFFFFFF);
  static const Color menuSepDark = Color(0x73585446);

  // 聊天
  static const Color chatTitleTop = Color(0xFF102B3C);
  static const Color chatTitleMid = Color(0xFF092031);
  static const Color chatTitleBottom = Color(0xFF061824);
  static const Color chatMsg = Color(0xFFFFFFFF);
  static const Color chatYLine = Color(0xFFE2A600);
  static const Color toolbarTop = Color(0xFF9AA0A3);
  static const Color toolbarMid = Color(0xFF6A7075);
  static const Color toolbarBottom = Color(0xFF585E63);
  static const Color chatInputBorder = Color(0xFFC9CED2);
  static const Color chatHint = Color(0xFFB9BFC4);
  static const Color sendTop = Color(0xFFFFFFFF);
  static const Color sendMid = Color(0xFFEEF1F3);
  static const Color sendBottom = Color(0xFFD5DADE);
  static const Color sendBorder = Color(0xFFA7AFB4);
  static const Color toolIcon = Color(0xFF2C3236);
  static const Color bigbtnArrow = Color(0xFF8A9094);

  // 好友管理木质桌面
  static const Color fmTitleTop = Color(0xFF2A5A68);
  static const Color fmTitleMid = Color(0xFF143C4A);
  static const Color fmTitleBottom = Color(0xFF0E2C38);
  static const Color fmBar2Top = Color(0xFF12303C);
  static const Color fmBar2Bottom = Color(0xFF0B2230);
  static const Color fmYLine = Color(0xFFD8A800);
  static const Color woodTop = Color(0xFF3F2818);
  static const Color woodMid = Color(0xFF2B1A0E);
  static const Color woodBottom = Color(0xFF20120A);
  static const Color frTop = Color(0xFF5A6168);
  static const Color frBottom = Color(0xFF2E3338);
  static const Color plateTop = Color(0xFF8DBB4A);
  static const Color plateBottom = Color(0xFF5C8A2C);

  // 公共窗口 .dlg
  static const Color dlgBorder = Color(0xFF2B3A41);
  static const Color dlgBarTop = Color(0xFF2E5363);
  static const Color dlgBarMid = Color(0xFF1C3E4C);
  static const Color dlgBarBottom = Color(0xFF122C39);
  static const Color dlgBarBorder = Color(0xFF0B1D27);
  static const Color dlgBtn = Color(0xFF8AA6B3);
  static const Color dlgBodyTop = Color(0xFFE9E5D8);
  static const Color dlgBodyMid = Color(0xFFD9D3C2);
  static const Color dlgBodyBottom = Color(0xFFCBC4B1);
  static const Color dlgBodyDark = Color(0xFF031C2A);
  static const Color dlgFootTop = Color(0xFFCDC7B5);
  static const Color dlgFootBottom = Color(0xFFBDB6A2);
  static const Color metalTop = Color(0xFFE8E4D8);
  static const Color metalMid1 = Color(0xFFCDC8B8);
  static const Color metalMid2 = Color(0xFFA9A392);
  static const Color metalBottom = Color(0xFFBDB7A4);
  static const Color metalBorder = Color(0xFF6F6A58);
  static const Color metalDarkTop = Color(0xFF5B6872);
  static const Color metalDarkMid = Color(0xFF313D46);
  static const Color metalDarkBottom = Color(0xFF29343C);
  static const Color metalDarkBorder = Color(0xFF6D7A83);
  static const Color aboutBg = Color(0xFFD9D3C2);
  static const Color aboutText = Color(0xFF2B2B28);
  static const Color settingsBg = Color(0xFF001726);
  static const Color settingsHeading = Color(0xFFAAB7BF);
  static const Color settingsOpt = Color(0xFFE3E9ED);
  static const Color cbBorder = Color(0xFFCFD8DE);
  static const Color cbTop = Color(0xFF243743);
  static const Color cbBottom = Color(0xFF0B1D29);
}

/// 纵向 / 横向渐变快捷构造
LinearGradient vg(List<Color> colors, [List<double>? stops]) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: colors,
  stops: stops,
);

LinearGradient hg(List<Color> colors, [List<double>? stops]) => LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: colors,
  stops: stops,
);

/// 常用文本样式
class QText {
  static const String font = 'PingFang SC';

  static TextStyle of(
    double size, {
    Color color = QC.white,
    FontWeight weight = FontWeight.normal,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) => TextStyle(
    fontFamily: font,
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    shadows: shadows,
    decoration: TextDecoration.none,
  );

  static final TextStyle loginTitle = of(
    13,
    weight: FontWeight.w700,
    letterSpacing: .5,
    shadows: const [
      Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 2),
    ],
  );
  static final TextStyle lab = of(13, weight: FontWeight.w700);
  static final TextStyle beige = of(
    12.5,
    color: QC.beigeText,
    weight: FontWeight.w700,
  );
  static final TextStyle brand = of(
    14,
    weight: FontWeight.w800,
    letterSpacing: .5,
  );
  static final TextStyle nick = of(14, weight: FontWeight.w700);
  static final TextStyle sign = of(12, color: QC.sign);
  static final TextStyle searchHint = of(12, color: QC.searchHint);
  static final TextStyle menuTitle = of(
    14,
    color: QC.menuTitle,
    weight: FontWeight.w800,
  );
  static final TextStyle menuItem = of(13, color: QC.menuItem);
  static final TextStyle menuFoot = of(
    12.5,
    color: QC.menuFootText,
    weight: FontWeight.w600,
  );
  static final TextStyle aboutTxt = of(13, color: QC.aboutText);
  static final TextStyle settingsOpt = of(12.5, color: QC.settingsOpt);
  static final TextStyle metal = of(13, weight: FontWeight.w700);
}

/// 常用阴影
class QShadow {
  static const List<BoxShadow> win = [
    BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 10)),
  ];
  static const List<BoxShadow> loginWin = [
    BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> dlg = [
    BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 12)),
  ];
}

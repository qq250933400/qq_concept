// 原生 OS 窗口模式下的窗口外观开关。
// 画布模式下每个窗口是「桌面画布」里的一个卡片，卡片自带的 `boxShadow`
// 可以溢出到画布壁纸上，看起来像真实的投影。
// 但原生窗口的边界 == 画布尺寸，阴影无处可去，只能在窗口内部糊成一层
// 半透明灰雾（异形窗口的透明区域尤其明显）。
//
// 所以原生窗口模式下统一不画外阴影；窗口层次改由系统窗口层级表达。
import 'package:flutter/widgets.dart';

bool qNativeWindowChrome = false;

/// 取「窗口外阴影」：原生窗口模式返回空列表，画布模式原样返回。
List<BoxShadow> qOuterShadow(List<BoxShadow> canvas) =>
    qNativeWindowChrome ? const <BoxShadow>[] : canvas;

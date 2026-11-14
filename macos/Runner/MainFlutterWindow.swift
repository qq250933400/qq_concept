import Cocoa
import FlutterMacOS

/// 窗口化模式下这个类不再被 MainMenu.xib 实例化，保留仅为兼容 Xcode 工程引用。
///
/// 切勿在这里创建 FlutterViewController：只要在 Dart 创建第一个
/// WindowController 之前注册了任何 view controller，FlutterEngine 的
/// enableMultiView 就会抛 "Multiview can only be enabled before adding any
/// view controllers."。初始窗口尺寸 / 主窗口标题改由
/// lib/frontend/native_windows.dart 里的主 WindowController 设置。
class MainFlutterWindow: NSWindow {}

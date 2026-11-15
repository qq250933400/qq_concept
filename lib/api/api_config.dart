import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

/// 是否接真实 API。默认开启；`--dart-define=QQ_USE_API=false` 可回到纯演示数据。
const bool kApiEnabled = bool.fromEnvironment(
  'QQ_USE_API',
  defaultValue: true,
);

/// 自动化联调用：给登录窗预填演示密码（默认空，正常使用时手输）。
const String kDemoPassword = String.fromEnvironment('QQ_DEMO_PASSWORD');

const String _kApiBaseOverride = String.fromEnvironment('QQ_API_BASE');

/// REST 根地址（不含尾部斜杠），例如 `http://127.0.0.1:3000/v1`。
///
/// 优先级：dart-define > web 同源推导（API 固定 3000）> 桌面 127.0.0.1:3000。
/// 通过 Nginx 同源代理部署时传 `--dart-define=QQ_API_BASE=/v1` 即可。
String qResolveApiBase() {
  if (_kApiBaseOverride.isEmpty) {
    if (kIsWeb) {
      final origin = Uri.base;
      return '${origin.scheme}://${origin.host}:3000/v1';
    }
    return 'http://127.0.0.1:3000/v1';
  }
  if (_kApiBaseOverride.startsWith('/')) {
    final origin = Uri.base;
    final port = origin.hasPort ? ':${origin.port}' : '';
    return '${origin.scheme}://${origin.host}$port$_kApiBaseOverride';
  }
  return _kApiBaseOverride.endsWith('/')
      ? _kApiBaseOverride.substring(0, _kApiBaseOverride.length - 1)
      : _kApiBaseOverride;
}

/// 网关挂在 HTTP server 根路径 `/ws`（不随全局 `v1` 前缀）。
///
/// 必须显式构造：用 `Uri.replace(fragment: '')` 会留下一个空的 `#`，
/// 后续再拼 `?token=...` 时查询参数会被当成 fragment，服务端收不到 token。
String qResolveWsUrl(String apiBase) {
  final uri = Uri.parse(apiBase);
  return Uri(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '/ws',
  ).toString();
}

/// 本进程稳定的设备标识，登录与 WS 握手必须使用同一个值。
String qNewDeviceId() {
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
  return '$platform-${DateTime.now().microsecondsSinceEpoch}';
}

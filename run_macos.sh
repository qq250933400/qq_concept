#!/usr/bin/env bash
# 启动 macOS 调试版（含 Hot Reload）。
# 说明：本机代理会拦截 127.0.0.1 的 VM Service WebSocket（502），
# 故显式把本机地址加入 NO_PROXY；固定端口便于 IDE / DevTools 连接。
set -e
cd "$(dirname "$0")"
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
export no_proxy="$NO_PROXY"
exec flutter run -d macos --host-vmservice-port=55177 "$@"

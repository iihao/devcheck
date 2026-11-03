#!/bin/bash
# 录制 CLI Demo GIF（需要「屏幕录制」+ Terminal 自动化权限）
#
#   ./scripts/record-cli-demo.sh en docs/demo-cli.gif
#   ./scripts/record-cli-demo.sh zh docs/demo-cli.zh.gif
#
# 会在新 Terminal 窗口里真实执行 devcheck why 5000 / ports / why 3000，
# 然后录下这个窗口并转成 GIF。结束时会关闭自己开的窗口。
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${1:-en}"
OUTPUT="${2:-docs/demo-cli.gif}"
DURATION="${DURATION:-7}"
WORK="$(mktemp -d)"
APP_BIN="$PWD/dist/DevCheck.app/Contents/MacOS/DevCheck"
BIN_LINK="/tmp/devcheck-demo-bin"

DEMO_ROOT="/tmp/devcheck-cli-demo-$$"

cleanup() {
  [[ -n "${TERM_WINDOW_ID:-}" ]] && osascript -e "tell application \"Terminal\" to close (first window whose id is ${TERM_WINDOW_ID}) saving no" >/dev/null 2>&1 || true
  [[ -n "${NODE_PID:-}" ]] && kill "$NODE_PID" 2>/dev/null || true
  [[ -n "${PY_PID:-}" ]] && kill "$PY_PID" 2>/dev/null || true
  rm -rf "$DEMO_ROOT" "$WORK"
}
trap cleanup EXIT

[[ -x "$APP_BIN" ]] || { echo "先构建：VERSION=0.1.1 ./scripts/bundle.sh" >&2; exit 1; }

# 让终端里能直接敲 `devcheck`
mkdir -p "$BIN_LINK"
ln -sf "$APP_BIN" "$BIN_LINK/devcheck"

echo "==> 启动示例服务"
mkdir -p "$DEMO_ROOT/cloud-admin/src" "$DEMO_ROOT/data-api/app"
printf '{"name":"cloud-admin"}' > "$DEMO_ROOT/cloud-admin/package.json"
printf '[project]\nname = "data-api"\n' > "$DEMO_ROOT/data-api/pyproject.toml"
(cd "$DEMO_ROOT/cloud-admin" && git init -q .)
(cd "$DEMO_ROOT/cloud-admin/src" && exec node -e "require('http').createServer((q,s)=>s.end('ok')).listen(5173)" >/dev/null 2>&1) &
NODE_PID=$!
(cd "$DEMO_ROOT/data-api/app" && exec python3 -m http.server 8000 >/dev/null 2>&1) &
PY_PID=$!
sleep 1.5

read -r WIN_ID LEFT TOP WIDTH HEIGHT < <(osascript -e "
tell application \"Terminal\"
  activate
  do script \"\"
  delay 0.4
  set bounds of front window to {120, 300, 1120, 780}
  set w to front window
  return (id of w as text) & \" 120 300 1000 480\"
end tell" 2>/dev/null | tr -d '\r')
TERM_WINDOW_ID="${WIN_ID:-}"
echo "    Terminal 窗口 id=${TERM_WINDOW_ID:-?} 区域 ${WIDTH}x${HEIGHT} @ ${LEFT},${TOP}"
[[ -n "$TERM_WINDOW_ID" ]] || { echo "无法创建 Terminal 窗口（检查自动化权限）" >&2; exit 1; }

run() {
  osascript -e "tell application \"Terminal\" to do script \"$1\" in (first window whose id is ${TERM_WINDOW_ID})" >/dev/null
}

# 清屏并预热 shell，让第一帧是干净的提示符
run "export PATH=${BIN_LINK}:\$PATH; export DEVCHECK_LANG=${LANG_CODE}; cd ${PWD}; clear"

echo "==> 录制 ${DURATION}s"
screencapture -x -V "$DURATION" -R"${LEFT},${TOP},${WIDTH},${HEIGHT}" "$WORK/demo.mov" &
REC_PID=$!

sleep 1
run "devcheck why 5000"
sleep 2
run "devcheck ports"
sleep 2
run "devcheck why 3000"

wait "$REC_PID" || true

echo "==> 转 GIF"
swift scripts/mov-to-gif.swift "$WORK/demo.mov" "$OUTPUT" 8 1000
echo "完成：${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
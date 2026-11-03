#!/bin/bash
# 录制菜单栏 Demo GIF（需要「屏幕录制」权限）
#
#   ./scripts/record-demo.sh en docs/demo.gif
#   ./scripts/record-demo.sh zh docs/demo.zh.gif
#
# 流程：造两个示例项目 → 启动 app 并自动展开菜单 → 录右上角 → 转 GIF → 清理
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_CODE="${1:-en}"
OUTPUT="${2:-docs/demo.gif}"
SECONDS_TO_RECORD="${SECONDS_TO_RECORD:-7}"

DEMO_ROOT="/tmp/devcheck-demo-$$"
WORK="$(mktemp -d)"
APP="./dist/DevCheck.app/Contents/MacOS/DevCheck"

cleanup() {
  [[ -n "${NODE_PID:-}" ]] && kill "$NODE_PID" 2>/dev/null || true
  [[ -n "${PY_PID:-}" ]] && kill "$PY_PID" 2>/dev/null || true
  [[ -n "${APP_PID:-}" ]] && kill "$APP_PID" 2>/dev/null || true
  rm -rf "$DEMO_ROOT" "$WORK"
}
trap cleanup EXIT

if [[ ! -x "$APP" ]]; then
  echo "先构建：VERSION=0.1.1 ./scripts/bundle.sh" >&2
  exit 1
fi

# 两个假项目，让菜单里出现「按项目分组」的效果
mkdir -p "$DEMO_ROOT/cloud-admin/src" "$DEMO_ROOT/data-api/app"
printf '{"name":"cloud-admin","version":"0.1.0"}' > "$DEMO_ROOT/cloud-admin/package.json"
printf '[project]\nname = "data-api"\n' > "$DEMO_ROOT/data-api/pyproject.toml"
(cd "$DEMO_ROOT/cloud-admin" && git init -q .)

echo "==> 启动示例服务"
(cd "$DEMO_ROOT/cloud-admin/src" && exec node -e "require('http').createServer((q,s)=>s.end('ok')).listen(5173)" >/dev/null 2>&1) &
NODE_PID=$!
(cd "$DEMO_ROOT/data-api/app" && exec python3 -m http.server 8000 >/dev/null 2>&1) &
PY_PID=$!

# 避免重复的菜单栏图标
pkill -x DevCheck 2>/dev/null || true
sleep 1

echo "==> 启动 DevCheck（菜单会在 2s 后自动展开）"
APP_LOG="$WORK/app.log"
DEVCHECK_LANG="$LANG_CODE" DEVCHECK_OPEN_MENU=1 "$APP" >"$APP_LOG" 2>&1 &
APP_PID=$!

# 等 app 报出 status item 的真实位置：菜单不一定贴着屏幕最右边
# （菜单栏里其它图标会把我们的图标挤到中间，盲录就会录空）
BUTTON_X=""
for _ in $(seq 1 60); do
  if grep -q "DEVCHECK_DIAG button window frame=" "$APP_LOG" 2>/dev/null; then
    BUTTON_X=$(sed -nE 's/.*button window frame=\(([0-9]+)\..*/\1/p' "$APP_LOG" | head -1)
    break
  fi
  sleep 0.25
done

if [[ -z "$BUTTON_X" ]]; then
  echo "拿不到 status item 位置，回退到屏幕右上角" >&2
  read -r SCREEN_W _ _ < <(swift -e 'import AppKit; print(Int(NSScreen.main!.frame.width), 0, 0)' 2>/dev/null)
  BUTTON_X=$((SCREEN_W - 60))
fi

# 菜单从 status item 下方展开、右对齐按钮右边缘，宽度取决于最长条目
REGION_W=640
REGION_H=420
REGION_X=$((BUTTON_X - 60))
[[ $REGION_X -lt 0 ]] && REGION_X=0
REGION_Y=0
echo "    status item x=$BUTTON_X → 录制区域 ${REGION_W}x${REGION_H} @ ${REGION_X},${REGION_Y}"

# 菜单内条目大致从 y=45 排到 y=330（详情行高随分组数变化，扫过去即可）
CURSOR_X=$((BUTTON_X + 140))
CURSOR_Y_START=50
CURSOR_Y_END=300

echo "==> 录制 ${SECONDS_TO_RECORD}s（区域 ${REGION_W}x${REGION_H} @ ${REGION_X},${REGION_Y}）"
screencapture -x -C -V "$SECONDS_TO_RECORD" -R"${REGION_X},${REGION_Y},${REGION_W},${REGION_H}" "$WORK/demo.mov" &
SCREENSHOT_PID=$!

# 等录制真正开始，再让光标扫过菜单，避免头几帧光标还在乱跑
sleep 1
swift scripts/move-cursor.swift "$CURSOR_X" "$CURSOR_Y_START" "$CURSOR_Y_END" 3.2 &
CURSOR_PID=$!

wait "$SCREENSHOT_PID" || true
wait "$CURSOR_PID" 2>/dev/null || true

if [[ ! -s "$WORK/demo.mov" ]]; then
  echo "录制失败：没有生成视频。请确认终端已获得「屏幕录制」权限。" >&2
  exit 1
fi

echo "==> 转 GIF"
swift scripts/mov-to-gif.swift "$WORK/demo.mov" "$OUTPUT" 10 900

echo "完成：${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
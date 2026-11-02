#!/bin/bash
# 生成 App 图标：SF Symbol → 1024 母版 → 完整尺寸链 → Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."

MASTER="build/icon_1024.png"
ICONSET="build/AppIcon.iconset"
OUT="Resources/AppIcon.icns"

echo "==> 渲染 1024 母版"
swift scripts/make-icon.swift "$MASTER"

echo "==> 生成 iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  size="${spec%%:*}"
  name="${spec##*:}"
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${name}.png" >/dev/null
done

echo "==> 打包 icns"
mkdir -p Resources
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"

echo "完成：${OUT} ($(du -h "$OUT" | cut -f1))"

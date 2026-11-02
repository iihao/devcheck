#!/bin/bash
# 打包为 macOS App（LSUIElement，只在菜单栏出现）
#
#   ./scripts/bundle.sh                 # 当前架构
#   UNIVERSAL=1 ./scripts/bundle.sh     # arm64 + x86_64 通用二进制
#   ZIP=1 ./scripts/bundle.sh           # 额外产出可分发的 zip
#   VERSION=0.2.0 ./scripts/bundle.sh   # 指定版本号（CI 用）
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="DevCheck"
BUNDLE_ID="local.devcheck"
VERSION="${VERSION:-0.1.1}"
APP="dist/${NAME}.app"
UNIVERSAL="${UNIVERSAL:-0}"
ZIP="${ZIP:-0}"

if [[ "$UNIVERSAL" == "1" ]]; then
  # 不用 `swift build --arch arm64 --arch x86_64`：该模式在 CI 上会触发
  # SwiftDriver 的 "missing target configuration" 报错。改为分别构建再 lipo 合并。
  echo "==> swift build -c release --arch arm64"
  swift build -c release --arch arm64 --scratch-path .build/arm64
  ARM_BIN="$(swift build -c release --arch arm64 --scratch-path .build/arm64 --show-bin-path)/devcheck"

  echo "==> swift build -c release --arch x86_64"
  swift build -c release --arch x86_64 --scratch-path .build/x86
  X86_BIN="$(swift build -c release --arch x86_64 --scratch-path .build/x86 --show-bin-path)/devcheck"

  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  echo "==> lipo 合并为通用二进制"
  lipo -create "$ARM_BIN" "$X86_BIN" -output "$STAGE/devcheck"
  lipo -info "$STAGE/devcheck"
  BIN="$STAGE/devcheck"
else
  echo "==> swift build -c release"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/devcheck"
fi

if [[ ! -x "$BIN" ]]; then
  echo "未找到可执行文件：$BIN" >&2
  exit 1
fi

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${NAME}"

# 图标（由 scripts/make-icon.sh 生成，仓库里带的是成品）
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "  ! 缺少 Resources/AppIcon.icns（先跑 ./scripts/make-icon.sh）"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <!-- 只在菜单栏运行，不显示 Dock 图标 -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> 签名（ad-hoc；正式发布走 Developer ID + notarize）"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --sign "${CODESIGN_IDENTITY}" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "ad-hoc 签名失败（不影响本机运行）"
fi

if [[ "$ZIP" == "1" ]]; then
  echo "==> 打包 zip"
  (cd dist && ditto -c -k --keepParent "${NAME}.app" "${NAME}-${VERSION}.zip")
  echo "产物：dist/${NAME}-${VERSION}.zip"
fi

echo "完成：$APP"
echo "运行：open $APP"
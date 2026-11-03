#!/bin/bash
# 一行安装（从 GitHub Releases 拉最新通用二进制）
#
#   curl -fsSL https://raw.githubusercontent.com/iihao/port-map/main/scripts/install.sh | bash
set -euo pipefail

REPO="${DEVCHECK_REPO:-iihao/port-map}"
DEST="${DEVCHECK_DEST:-/Applications}"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "只支持 macOS"

say "==> 查询最新版本"
TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$TAG" ]] || fail "拿不到最新 release，请到 https://github.com/${REPO}/releases 手动下载"
VERSION="${TAG#v}"
say "    最新版本：${TAG}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/${REPO}/releases/download/${TAG}/DevCheck-${VERSION}.zip"
say "==> 下载 $URL"
curl -fL --progress-bar "$URL" -o "$TMP/DevCheck.zip" || fail "下载失败"

say "==> 解压并安装到 ${DEST}"
ditto -x -k "$TMP/DevCheck.zip" "$TMP/out"
rm -rf "${DEST}/DevCheck.app"
cp -R "$TMP/out/DevCheck.app" "${DEST}/"

# ad-hoc 签名的包首次运行会被 Gatekeeper 拦，去掉隔离属性
xattr -dr com.apple.quarantine "${DEST}/DevCheck.app" 2>/dev/null || true

# 把 CLI 链进 PATH，否则 `devcheck why 5000` 找不到
BIN_DIR="${DEVCHECK_BIN_DIR:-/usr/local/bin}"
if [[ -w "$BIN_DIR" ]]; then
  ln -sf "${DEST}/DevCheck.app/Contents/MacOS/DevCheck" "${BIN_DIR}/devcheck"
  say "==> CLI 已链接：${BIN_DIR}/devcheck"
else
  say "==> 跳过 CLI 链接（${BIN_DIR} 不可写），可手动执行："
  say "    sudo ln -sf \"${DEST}/DevCheck.app/Contents/MacOS/DevCheck\" /usr/local/bin/devcheck"
fi

say "==> 完成。打开：open \"${DEST}/DevCheck.app\""
say "    命令行：devcheck why 5000"

#!/bin/bash
# 打包 TermDeck DMG（arm64）
# 用法: ./make_dmg.sh [版本号]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
ARCH="arm64"
DMG_NAME="TermDeck-${VERSION}-${ARCH}.dmg"

echo "==> release 构建"
./make_app.sh release >/dev/null

echo "==> 组装 DMG 内容（App + Applications 链接）"
STAGING="build/dmg-staging"
rm -rf "$STAGING" "build/$DMG_NAME"
mkdir -p "$STAGING"
cp -R "build/TermDeck.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> 生成 DMG"
hdiutil create \
    -volname "TermDeck" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -fs HFS+ \
    -ov \
    "build/$DMG_NAME" | tail -1

rm -rf "$STAGING"

echo ""
echo "完成: build/$DMG_NAME"
echo "验证: hdiutil attach build/$DMG_NAME"

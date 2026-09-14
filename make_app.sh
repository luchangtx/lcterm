#!/bin/bash
# 构建 TermDeck.app
# 用法: ./make_app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
APP="build/TermDeck.app"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TermDeck" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "==> 生成图标"
    swift Scripts/make_icon.swift
    iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf AppIcon.iconset
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force -s - "$APP"

echo "完成: $APP"
echo "运行: open $APP"

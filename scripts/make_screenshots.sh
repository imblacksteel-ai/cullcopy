#!/bin/zsh
# App Store 用スクリーンショット（2880×1800）を build/screenshots に作る。架空の写真と履歴を使う
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh --no-install >/dev/null
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
cp Sources/SDImporter/*.swift "$WORK/src/"
sed -i '' 's/^@main$//' "$WORK/src/SDImporterApp.swift"   # 撮影用の main に差し替える
cp scripts/screenshots/Screenshots.swift "$WORK/src/main.swift"

# 翻訳が効くように、アプリと同じ Resources を持つ .app にして動かす
APP="$WORK/Screenshots.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -O -DAPPSTORE -o "$APP/Contents/MacOS/screenshots" "$WORK"/src/*.swift
cp -R "build/SD Importer.app/Contents/Resources" "$APP/Contents/"
sed -e 's/<string>SDImporter<\/string>/<string>screenshots<\/string>/' \
    -e 's/com.imblacksteelai.sdimporter/com.imblacksteelai.sdimporter.screenshots/' \
    "build/SD Importer.app/Contents/Info.plist" > "$APP/Contents/Info.plist"

# 架空の写真は「Photos」という名前の一時ディスクに置く（画面に /Volumes/Photos と出るように）。Finder には出さない
hdiutil create -size 60m -fs APFS -volname Photos -ov "$WORK/demo.dmg" >/dev/null
DEMO=$(hdiutil attach -nobrowse "$WORK/demo.dmg" | awk -F'\t' '/Volumes/{print $NF}')
trap 'hdiutil detach "$DEMO" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

OUT=build/screenshots
rm -rf "$OUT" && mkdir -p "$OUT"
for lang in ja en ko zh-Hans zh-Hant; do
    "$APP/Contents/MacOS/screenshots" "$PWD/$OUT" "$lang" "$DEMO" -AppleLanguages "($lang)"
done
"$APP/Contents/MacOS/screenshots" "$PWD/$OUT" tips "$DEMO" -AppleLanguages "(ja)"   # チップの審査用
echo "作成しました: $OUT"

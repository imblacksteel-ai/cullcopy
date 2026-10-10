#!/bin/zsh
# リリースビルドして build/SD Importer.app を作る
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/SD Importer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SDImporter" "$APP/Contents/MacOS/SDImporter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "作成しました: $APP"

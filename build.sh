#!/bin/zsh
# リリースビルドして build/CullCopy.app を作り、/Applications にも入れる
# 使い方: ./build.sh             … ビルドして /Applications に入れ替え
#         ./build.sh --no-install … build/ に作るだけ
set -euo pipefail
cd "$(dirname "$0")"

# UNIVERSAL=1 なら Intel と Apple シリコンの両方で動くビルドにする（配布用）
SWIFT_FLAGS=(-c release)
if [[ "${UNIVERSAL:-}" == 1 ]]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi
swift build "${SWIFT_FLAGS[@]}"

APP="build/CullCopy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/SDImporter" "$APP/Contents/MacOS/SDImporter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 翻訳（英語・日本語・韓国語・中国語）を組み込む
xcrun xcstringstool compile Resources/Localization/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
cp -R Resources/Localization/InfoPlist/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "作成しました: $APP"

# --no-install を付けたときは build/ に作るだけ（使用中のアプリには触らない）
if [[ "${1:-}" == "--no-install" ]]; then
    exit 0
fi

# /Applications に入れ替える。起動中なら終了を待ってから入れ替え、起動し直す
INSTALLED="/Applications/CullCopy.app"
was_running=false
if pgrep -x SDImporter >/dev/null; then
    was_running=true
    pkill -x SDImporter
    while pgrep -x SDImporter >/dev/null; do sleep 0.2; done
fi
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
echo "インストールしました: $INSTALLED"

# 旧名（SD Importer）のアプリが残っていれば、ゴミ箱に移す（元に戻せる）
OLD="/Applications/SD Importer.app"
if [[ -d "$OLD" ]]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$OLD\"" >/dev/null \
        && echo "旧名のアプリをゴミ箱に移しました: $OLD" \
        || echo "旧名のアプリ（$OLD）は手動で削除してください"
fi

if $was_running; then
    # 終了直後は macOS 側の後片付けが残っていて open が失敗する（-600）ことがあるので、少し待って再試行する
    for _ in 1 2 3 4 5; do
        sleep 1
        open "$INSTALLED" 2>/dev/null && { echo "起動し直しました"; break; }
    done
fi

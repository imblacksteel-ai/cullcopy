#!/bin/zsh
# 配布用の .dmg を作って GitHub Releases に公開する
#
#   scripts/release.sh 1.0.0          … ビルド → 署名 → .dmg → 公証 → GitHub に公開（公開前に確認あり）
#   scripts/release.sh 1.0.0 --local  … 動作確認用。署名は仮のもの、公証と公開はしない
#
# 必要なもの（詳しくは docs/release.md）
#   - 「Developer ID Application」証明書がキーチェーンにあること
#   - App Store Connect API キーがキーチェーンにあること（kumofuton と同じ登録を使う）
# 鍵の値は画面にもリポジトリにも出さない
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-}
MODE=${2:-}
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ -n "$MODE" && "$MODE" != --local ]]; then
    echo "使い方: scripts/release.sh 1.0.0 [--local]" >&2
    exit 2
fi
TAG="v$VERSION"
KEYCHAIN_ACCOUNT=${KEYCHAIN_ACCOUNT:-kumofuton}

secret() {
    security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$1" -w 2>/dev/null || {
        echo "キーチェーンに「$1」がありません。docs/release.md を見てください。" >&2
        exit 1
    }
}

# --- 事前チェック --------------------------------------------------------------
if [[ "$MODE" != --local ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "コミットしていない変更があります。先にコミットしてください。" >&2
        exit 1
    fi
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "タグ $TAG はもうあります。別のバージョンを指定してください。" >&2
        exit 1
    fi
    TEAM_ID=$(secret APPLE_TEAM_ID)
    IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)
    if [[ -z "$IDENTITY" ]]; then
        echo "「Developer ID Application」証明書が見つかりません。docs/release.md の手順で作成してください。" >&2
        exit 1
    fi
    echo "署名に使う証明書: $IDENTITY"
else
    IDENTITY="-"
fi

# --- バージョンを書いてビルド --------------------------------------------------
BUILD_NUMBER=$(git rev-list --count HEAD)
PLIST_BACKUP=$(mktemp)
cp Resources/Info.plist "$PLIST_BACKUP"
KEY_FILE=""
COMMITTED=false
# 途中で失敗しても、書き換えたバージョンを元に戻し、鍵の一時ファイルを消す
cleanup() {
    [[ -n "$KEY_FILE" ]] && rm -f "$KEY_FILE"
    if ! $COMMITTED && [[ -f "$PLIST_BACKUP" ]]; then
        cp "$PLIST_BACKUP" Resources/Info.plist
    fi
    rm -f "$PLIST_BACKUP"
}
trap cleanup EXIT
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Resources/Info.plist

UNIVERSAL=1 ./build.sh --no-install
APP="build/SD Importer.app"

# --- 署名（Hardened Runtime と時刻つき。公証に必要） ---------------------------
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

# --- .dmg を作る（アプリと「アプリケーション」フォルダへのショートカット） -------
DMG="build/SD-Importer-$VERSION.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "SD Importer $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
if [[ "$IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
echo "作成しました: $DMG"

if [[ "$MODE" == --local ]]; then
    echo "（--local のため、公証と公開はしません）"
    exit 0
fi

# --- 公証（App Store Connect API キーを使う） ----------------------------------
KEY_FILE=$(mktemp -t AuthKey).p8
secret ASC_KEY_P8_BASE64 | base64 --decode > "$KEY_FILE"
echo "公証に出しています（数分かかります）…"
xcrun notarytool submit "$DMG" --key "$KEY_FILE" --key-id "$(secret ASC_KEY_ID)" --issuer "$(secret ASC_ISSUER_ID)" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# --- GitHub に公開 ------------------------------------------------------------
git add Resources/Info.plist
git commit -m "バージョン $VERSION" >/dev/null
COMMITTED=true
echo
echo "準備ができました: $DMG"
read "answer?GitHub に $TAG として公開しますか？ [y/N] "
if [[ "$answer" != [yY] ]]; then
    echo "公開しませんでした。バージョンを書き換えたコミットはそのまま残っています。"
    exit 0
fi
git tag "$TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" "$DMG" --title "SD Importer $VERSION" --generate-notes
echo "公開しました: $(gh release view "$TAG" --json url --jq .url)"

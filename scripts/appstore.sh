#!/bin/zsh
# App Store 版をビルドして App Store Connect にアップロードする（TestFlight / 審査用）
#
#   scripts/appstore.sh 1.0.0
#
# 証明書とプロビジョニングプロファイルは、App Store Connect API キーで Apple のクラウドから自動で用意する
# （kumofuton と同じキーをキーチェーンから読む。値は画面にもリポジトリにも出さない）
# 事前に App Store Connect でアプリを作っておくこと（docs/appstore.md）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:-}
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "使い方: scripts/appstore.sh 1.0.0" >&2
    exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "コミットしていない変更があります。先にコミットしてください。" >&2
    exit 1
fi
KEYCHAIN_ACCOUNT=${KEYCHAIN_ACCOUNT:-kumofuton}
secret() {
    security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$1" -w 2>/dev/null || {
        echo "キーチェーンに「$1」がありません。docs/release.md を見てください。" >&2
        exit 1
    }
}

TEAM_ID=$(secret APPLE_TEAM_ID)
KEY_ID=$(secret ASC_KEY_ID)
ISSUER_ID=$(secret ASC_ISSUER_ID)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
KEY_FILE="$WORK/AuthKey_$KEY_ID.p8"
secret ASC_KEY_P8_BASE64 | base64 --decode > "$KEY_FILE"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_FILE" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")

# ビルド番号はコミット数（増える一方なので App Store の決まりを満たす）
BUILD_NUMBER=$(git rev-list --count HEAD)
ARCHIVE="build/appstore/SDImporter.xcarchive"
rm -rf build/appstore

xcodegen generate
echo "アーカイブを作成しています（バージョン $VERSION、ビルド $BUILD_NUMBER）…"
xcodebuild archive -project SDImporter.xcodeproj -scheme SDImporter -configuration Release \
    -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${AUTH[@]}" | grep -E "error|warning: |ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "アーカイブを作れませんでした。" >&2; exit 1; }

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "App Store Connect にアップロードしています…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "build/appstore/export" "${AUTH[@]}"
echo
echo "アップロードしました（バージョン $VERSION、ビルド $BUILD_NUMBER）。"
echo "処理が終わると App Store Connect の TestFlight に表示されます（数分〜数十分）。"

#!/bin/zsh
# 画面の文言を変えたら実行する。コードから翻訳が必要な文言を抜き出して Localizable.xcstrings に反映し、
# scripts/translations.py の翻訳表を書き込む（翻訳が足りないキーがあれば表示して失敗する）
set -euo pipefail
cd "$(dirname "$0")/.."

# GitHub 版と App Store 版（APPSTORE）で表示する文言が違うので、両方から抜き出す
OUT=$(mktemp -d)
mkdir -p "$OUT/github" "$OUT/appstore"
swift build -c release -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT/github"
swift build -c release --build-path .build/appstore-strings -Xswiftc -DAPPSTORE \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT/appstore"
xcrun xcstringstool sync Resources/Localization/Localizable.xcstrings --stringsdata "$OUT"/github/*.stringsdata "$OUT"/appstore/*.stringsdata
rm -rf "$OUT"
python3 scripts/translations.py

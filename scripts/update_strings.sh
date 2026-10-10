#!/bin/zsh
# 画面の文言を変えたら実行する。コードから翻訳が必要な文言を抜き出して Localizable.xcstrings に反映し、
# scripts/translations.py の翻訳表を書き込む（翻訳が足りないキーがあれば表示して失敗する）
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
swift build -c release -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT"
xcrun xcstringstool sync Resources/Localization/Localizable.xcstrings --stringsdata "$OUT"/*.stringsdata
rm -rf "$OUT"
python3 scripts/translations.py

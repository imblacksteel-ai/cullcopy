# SD Importer

<img src="Resources/AppIcon-preview.png" width="128" align="right" alt="アイコン">

SDカードの写真・動画を、撮影日ごとのフォルダに振り分けてコピーする macOS アプリです。

## できること

- **コピー元の選択**：接続中のSDカード・外付けドライブを一覧から選択（カードを差すと自動で選ばれます）。普通のフォルダも選べます
- **フォルダ名の形式を自由に指定**：`yyyy/yyyy年MM月dd日` のように書くと、撮影日で置き換えます
- **進捗の表示**：件数・進捗バー・コピー中のファイル名。途中でキャンセルも可能
- **取り込み済みはスキップ**：コピー先に同名・同サイズのファイルがあればコピーしません。同名で中身が違う場合は `IMG_0001-1.JPG` のように別名で保存します
- **安全なコピー**：一時ファイルにコピーしてサイズを照合してから正式な名前にします
- **コピー元の削除（任意）**：完了後に「コピー元フォルダを削除しますか？」と確認。コピー先に同じサイズで存在するファイルだけを削除します

### フォルダ名の書き方

| 記号 | 意味 | 例 |
|---|---|---|
| `yyyy` | 年 | 2026 |
| `yy` | 年（2桁） | 26 |
| `MM` | 月 | 08 |
| `dd` | 日 | 15 |
| `/` | サブフォルダの区切り | |

大文字・小文字は区別しません。空欄にするとフォルダ分けしません。

| 入力 | 結果 |
|---|---|
| `yyyy/yyyy-MM-dd` | `2026/2026-08-15/` |
| `yyyy年MM月dd日` | `2026年08月15日/` |
| `yyyy_mm_dd` | `2026_08_15/` |

### 撮影日の判定

写真は EXIF の撮影日時、動画はファイル内の作成日時を使い、どちらも無ければファイルの作成日を使います。

### 対象のファイル

- 写真：jpg, jpeg, heic, heif, png, tif, tiff, dng と各社の RAW（arw, cr2, cr3, nef, orf, raf, rw2 など）
- 動画：mp4, mov, m4v, avi, mts, m2ts, 3gp, mxf, insv, lrv

## ビルド

macOS 14 以降、Xcode（Swift 6）が必要です。

```bash
./build.sh
```

`build/SD Importer.app` ができます。`/Applications` にコピーすると Launchpad やスポットライトから起動できます。

```bash
cp -R "build/SD Importer.app" /Applications/
```

アイコンを作り直すときは `swift scripts/make_icon.swift` を実行してからビルドしてください。

## 構成

| ファイル | 内容 |
|---|---|
| `Sources/SDImporter/SDImporterApp.swift` | 画面 |
| `Sources/SDImporter/AppState.swift` | SDカードの検知・設定・コピーの進行管理 |
| `Sources/SDImporter/Importer.swift` | ファイルの走査・撮影日の取得・コピー・削除 |
| `Sources/SDImporter/FolderFormat.swift` | フォルダ名の形式の変換 |
| `scripts/make_icon.swift` | アイコンの生成 |

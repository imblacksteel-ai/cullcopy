# Mac App Store への提出手順

App Store 版は `project.yml`（XcodeGen）から作る Xcode プロジェクトでビルドします。
サンドボックスの中で動き、チップはアプリ内課金です（GitHub 版は今まで通り `build.sh` で作り、チップなしの完全無料）。

## 毎回の手順

```sh
cd ~/claude_workspace/photo_manager_project
git status                     # コミットしていない変更がないこと
scripts/appstore.sh 1.0.0      # ビルドして App Store Connect にアップロード
```

- 署名用の証明書とプロビジョニングプロファイルは、API キーで Apple のクラウドから自動で用意します（kumofuton と同じキー）。
- ビルド番号はコミット数です。
- アップロードが終わると、数分〜数十分で App Store Connect の「TestFlight」に表示されます。

## API でできること（scripts/asc_setup.py）

アプリを作ったあとの設定の多くは、API キーで登録できます（何度実行しても同じ結果になります）。

```sh
python3 scripts/asc_setup.py metadata      # バージョン番号・カテゴリ・年齢制限・5言語の掲載文
python3 scripts/asc_setup.py screenshots   # スクリーンショット（先に scripts/make_screenshots.sh）
python3 scripts/asc_setup.py pricing       # 価格（無料）と販売地域
python3 scripts/asc_setup.py tips          # チップ3つ（名前・説明・価格・販売地域・審査用画像）
```

API でできないのは、アプリの新規作成、「App のプライバシー」、審査用の連絡先、審査への提出です（App Store Connect の画面で行います）。

## 最初に一度だけ（App Store Connect での作業）

### 1. アプリを作る

https://appstoreconnect.apple.com → アプリ → ＋ → 新規 App

| 項目 | 入力 |
|---|---|
| プラットフォーム | macOS |
| 名前 | `CullCopy`（1.0.0 は旧名 SD Importer で提出。使われていたら `CullCopy - Photo Sorter` など） |
| プライマリ言語 | 日本語 |
| バンドル ID | `com.imblacksteelai.sdimporter`（一覧になければ、先に `scripts/appstore.sh` を一度実行すると Xcode が登録します） |
| SKU | `sdimporter` |

### 2. アプリ内課金（チップ）を作る

App → 収益化 → アプリ内課金 → ＋ → **消耗型**。3つ作ります。

| 製品 ID | 参照名 | 価格（例） | 表示名（日本語 / 英語） |
|---|---|---|---|
| `com.imblacksteelai.sdimporter.tip.small` | Tip Small | 160円 | 小さなチップ / Small Tip |
| `com.imblacksteelai.sdimporter.tip.medium` | Tip Medium | 480円 | チップ / Tip |
| `com.imblacksteelai.sdimporter.tip.large` | Tip Large | 1,000円 | 大きなチップ / Big Tip |

- 説明（日本語）：「開発を応援するチップです。機能は増えません。」（英語：「A tip to support development. It does not unlock features.」）
- 審査用スクリーンショット：アプリの「開発を支援する」画面のスクリーンショット
- 最初のバージョンの提出時に、この3つも一緒に審査に出します（バージョンのページの「アプリ内課金」に追加）。

### 3. 掲載情報

`AppStore/metadata/<言語>/` のテキストを貼り付けます（ja / en-US / ko / zh-Hans / zh-Hant）。

| 項目 | ファイル |
|---|---|
| 名前・サブタイトル | `name.txt`・`subtitle.txt` |
| 概要 | `description.txt` |
| キーワード | `keywords.txt` |
| プロモーション用テキスト | `promotional_text.txt` |
| サポート URL | `support_url.txt` |
| マーケティング URL | `marketing_url.txt` |
| プライバシーポリシー URL | `privacy_url.txt` |

スクリーンショットは `scripts/make_screenshots.sh` で `build/screenshots/` に作ります（2880×1800、言語ごとに4枚）。

### 4. そのほかの設定

- **カテゴリ**：写真（Photography）。サブカテゴリ：仕事効率化（任意）
- **価格**：無料
- **App のプライバシー**：「データを収集しない」
- **年齢制限**：すべての質問に「なし」→ 4+
- **輸出コンプライアンス**：暗号化は使っていない（`ITSAppUsesNonExemptEncryption = NO` を設定済み。ハッシュ計算は対象外）
- **審査メモ**（例）：

  > CullCopy copies photos and videos from an SD card (or any folder) into folders by capture date.
  > No SD card is needed for review: choose any folder with "Folder…" as the source and press "Start Import".
  > The Duplicates tab finds identical files in a folder. Tips are consumable in-app purchases and do not unlock features.

## ローカルでの確認

```sh
xcodegen generate
open CullCopy.xcodeproj
```

Xcode で実行すると、`AppStore/Tips.storekit` のテスト用の商品でチップを試せます（実際には課金されません）。

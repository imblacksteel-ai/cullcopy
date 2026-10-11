# リリース手順（GitHub Releases で配布）

公証（notarization）済みの `.dmg` を作って、GitHub Releases に公開します。
鍵やパスワードはリポジトリに入れません。すべてこの Mac のキーチェーンから読みます。

## 毎回の手順

```sh
cd ~/claude_workspace/photo_manager_project
git status                      # コミットしていない変更がないこと
scripts/release.sh 1.0.0        # バージョンを指定
```

スクリプトがすること：

1. `Resources/Info.plist` のバージョンを書き換える（ビルド番号はコミット数）
2. Intel と Apple シリコンの両方で動くアプリをビルド
3. 「Developer ID Application」証明書で署名（Hardened Runtime つき）
4. `build/SD-Importer-<バージョン>.dmg` を作って署名
5. Apple の公証に出し、結果を `.dmg` に添付（staple）
6. バージョンを書き換えたコミットを作り、**確認のあと** タグを付けて GitHub に公開

途中で失敗した場合は、書き換えたバージョンは元に戻ります。直してからもう一度実行してください。

公証や公開をせずに `.dmg` だけ試しに作るとき：

```sh
scripts/release.sh 1.0.0 --local
```

## 最初に一度だけ

### 1. App Store Connect API キー

kumofuton と同じキー（キーチェーンのアカウント名 `kumofuton`）をそのまま使います。
登録の方法は kumofuton の `docs/release.md`「キーチェーンに登録する」を見てください。
別の名前で登録した場合は、`KEYCHAIN_ACCOUNT=名前 scripts/release.sh 1.0.0` のように指定します。

使う項目：`ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8_BASE64`、`APPLE_TEAM_ID`

### 2. 「Developer ID Application」証明書

App Store 以外で配るアプリの署名に必要です（チームのアカウント所有者だけが作れます）。

1. Xcode → Settings… → Accounts → チームを選ぶ → **Manage Certificates…**
2. 左下の **＋** → **Developer ID Application**
3. 次のコマンドで表示されれば準備完了です。

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

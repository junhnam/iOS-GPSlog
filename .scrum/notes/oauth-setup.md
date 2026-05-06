# Google Drive OAuth セットアップ手順

このドキュメントは、Google Drive 連携機能を実機またはシミュレーター（iOS 26）でテストするために必要な OAuth クライアント ID の取得・設定手順を説明します。

## 前提条件

- Google アカウントを持っていること
- Google Cloud Console にアクセスできること（https://console.cloud.google.com/）
- Xcode がインストールされていること

---

## Step 1: Google Cloud Console でプロジェクトを用意する

1. https://console.cloud.google.com/ にアクセスし、Google アカウントでサインイン
2. 画面上部の「プロジェクトを選択」から既存プロジェクトを選ぶか、「新しいプロジェクト」を作成する
   - プロジェクト名の例: `GPS Logger`

---

## Step 2: Google Drive API を有効化する

1. 左メニューから「APIとサービス」→「ライブラリ」を選択
2. 検索ボックスに「Google Drive API」と入力して表示された項目をクリック
3. 「有効にする」ボタンを押す

---

## Step 3: OAuth 同意画面を設定する

1. 「APIとサービス」→「OAuth 同意画面」を選択
2. ユーザーの種類: 「外部」を選択して「作成」
3. アプリ名（例: `GPSログ`）、サポートメールを入力して「保存して次へ」
4. スコープの追加で以下を選択:
   - `https://www.googleapis.com/auth/drive.file`（アプリが作成したファイルへのアクセス）
5. 残りはデフォルトのまま「保存して次へ」

---

## Step 4: iOS 用 OAuth 2.0 クライアント ID を発行する

1. 「APIとサービス」→「認証情報」を選択
2. 「認証情報を作成」→「OAuth クライアント ID」を選択
3. アプリケーションの種類: **iOS** を選択
4. 名前（任意）: `GPSLogger iOS`
5. バンドル ID: `com.junhnam.gpslogger`（Xcode の PRODUCT_BUNDLE_IDENTIFIER と一致させる）
6. 「作成」をクリック
7. 表示されたクライアント ID（`123456789-xxxxxxxxxx.apps.googleusercontent.com` 形式）をコピーして控える

---

## Step 5: plist ファイルに値を設定する

1. リポジトリ内の example ファイルをコピーして実ファイルを作成する:

   ```bash
   cp GPSLogger/Resources/GoogleDriveOAuth-Info.plist.example GPSLogger/Resources/GoogleDriveOAuth-Info.plist
   ```

2. 作成した `GoogleDriveOAuth-Info.plist` をテキストエディタで開き、以下を書き換える:

   | キー | 設定値 |
   |------|--------|
   | `GoogleDriveOAuthClientID` | Step 4 で取得したクライアント ID（例: `123456789-xxx.apps.googleusercontent.com`） |
   | `GoogleDriveOAuthReverseClientID` | クライアント ID をドット区切りで逆順にした文字列（例: `com.googleusercontent.apps.123456789-xxx`） |

3. `GPSLogger/Resources/Info.plist` の `CFBundleURLSchemes` にも同じ Reverse Client ID を設定する:

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.googleusercontent.apps.123456789-xxx</string>
           </array>
       </dict>
   </array>
   ```

---

## Step 6: Xcode で参照を確認する

1. Xcode を開いて `GPSLogger.xcodeproj`（または `.xcworkspace`）を起動
2. ビルドターゲット「GPSLogger」→「Build Phases」→「Copy Bundle Resources」に `GoogleDriveOAuth-Info.plist` が含まれていることを確認
   - 含まれていなければ「+」ボタンで追加する
3. `xcodebuild clean build`（またはメニュー「Product」→「Clean Build Folder」→「Build」）を実行してエラーがないことを確認

---

## 注意事項

- `GoogleDriveOAuth-Info.plist`（実値入り）は `.gitignore` に登録済みのため、**コミットされない**
- `GoogleDriveOAuth-Info.plist.example`（プレースホルダー入り）はリポジトリに含まれており、手順の参照元として使う
- クライアント ID 自体は機密情報ではないが、誤ってコミットしないようにするための運用ルールとして gitignore パターンを維持する

---

## Dropbox 対応について

Dropbox 用の OAuth 設定は、商用化（App Store 公開）時に対応する。
現時点（Sprint 6）では Google Drive のみ対応。`CloudStorageProvider` プロトコルは抽象化済みのため、Dropbox 追加のコストは低い。

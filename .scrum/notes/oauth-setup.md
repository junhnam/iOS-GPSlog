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

## Step 5: Info.plist に値を設定する

`GPSLogger/Resources/Info.plist` を直接編集して、以下 2 箇所を書き換える:

1. `GoogleDriveOAuthClientID`（空文字 → クライアント ID）

   ```xml
   <key>GoogleDriveOAuthClientID</key>
   <string>123456789-xxx.apps.googleusercontent.com</string>
   ```

2. `CFBundleURLTypes` 内の `CFBundleURLSchemes`（`PLACEHOLDER` → Reverse Client ID）

   Reverse Client ID は、クライアント ID をドット区切りで逆順にした文字列です。
   例: `123456789-xxx.apps.googleusercontent.com` → `com.googleusercontent.apps.123456789-xxx`

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLName</key>
           <string>GoogleDriveOAuth</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.googleusercontent.apps.123456789-xxx</string>
           </array>
       </dict>
   </array>
   ```

---

## Step 6: Xcode でビルド確認

1. Xcode を開いて `GPSLogger.xcodeproj` を起動
2. メニュー「Product」→「Clean Build Folder」→「Build」を実行してエラーがないことを確認

---

## 注意事項

- OAuth クライアント ID 自体は **公開して問題ない値**（PKCE フロー前提でクライアントシークレットを持たない設計）
  - Google 公式も iOS アプリの場合は plist にそのまま書く運用を案内しています
  - そのため `Info.plist` に直書き＆コミットして問題ありません
- `GoogleDriveOAuth-Info.plist`（gitignore 対象）は **現行実装では使用していません**
  - コードは `Bundle.main.object(forInfoDictionaryKey: "GoogleDriveOAuthClientID")` でメインの Info.plist を直接読んでいます
  - `.example` ファイルは将来的に別 plist 運用へ移行する場合に備えて残してあります

---

## Dropbox 対応について

Dropbox 用の OAuth 設定は、商用化（App Store 公開）時に対応する。
現時点（Sprint 6）では Google Drive のみ対応。`CloudStorageProvider` プロトコルは抽象化済みのため、Dropbox 追加のコストは低い。

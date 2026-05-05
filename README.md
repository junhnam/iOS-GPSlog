# GPSLogger

iOS 26+ 向けの GPS 移動経路ロガー。Swift / SwiftUI / Google Maps SDK で構築。

> ビルド・実行手順の本格的な整備は S1-009 で行います。本ファイルは S1-002 時点の最小説明です。

## 必要環境

- macOS 26 以上
- Xcode 26 以上（App Store または Apple Developer サイトから入手）
- Homebrew（XcodeGen のインストールに使用）

## 初回セットアップ

```bash
# 1. XcodeGen をインストール（プロジェクト生成に必要）
brew install xcodegen

# 2. リポジトリ直下で Xcode プロジェクトを生成
xcodegen generate

# 3. Xcode で開く
open GPSLogger.xcodeproj
```

## Google Maps API キーの設定

地図機能を使うには Google Cloud Console で発行した API キーが必要です。

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. プロジェクトを作成（既存のものを使っても OK）
3. 「APIとサービス」 → 「ライブラリ」から **Maps SDK for iOS** を有効化
4. 「APIとサービス」 → 「認証情報」で「APIキー」を作成
5. 必要に応じてキーの制限（iOSアプリ向け、Bundle ID `com.junhnam.gpslogger`）を設定
6. リポジトリ内のテンプレートをコピーしてキーを書き込む:

   ```bash
   cp GPSLogger/Resources/GoogleMaps-Info.plist.example GPSLogger/Resources/GoogleMaps-Info.plist
   # 開いて GMSApiKey の値を発行したキーに置き換える
   ```

7. `xcodegen generate` を再実行（または Xcode を再起動）してビルド

`GoogleMaps-Info.plist` は `.gitignore` で除外されているのでコミットされません。

キー未設定でもアプリは起動しますが、起動時のコンソールに警告ログが出力され、地図表示は動作しません。

# GPSLogger

車などで遠方に出かける際に、GPS から自動的に位置情報を記録し、移動経路を地図上で可視化する iOS アプリです。
個人利用が主目的ですが、品質次第で App Store 公開も視野に入れています。

> 開発進行中（現在 Sprint 1）。本 README は Sprint 1 完了時点のセットアップ手順です。

## プロジェクト概要

- 移動経路を地図上に青いラインで表示
- 10 分以上の滞留を検出し、ピンとして自動記録（後続スプリントで実装）
- iOS カレンダーと連動し「いつどこに行ったか」を管理（後続スプリントで実装）
- 日付ごとにローカル DB へ保存し、CSV エクスポート / Google Drive 同期に対応（後続スプリントで実装）
- 自宅登録時は記録停止、常時記録 / トリガー記録の切替などをサポート（後続スプリントで実装）

技術スタック: Swift / SwiftUI / Google Maps SDK for iOS / Core Location / SwiftData / EventKit

詳細は [`CLAUDE.md`](./CLAUDE.md) と [`.scrum/config.md`](./.scrum/config.md) を参照してください。

## 必要な環境

| 項目 | バージョン / 備考 |
|---|---|
| macOS | 26 以上推奨（Apple Silicon 推奨） |
| Xcode | 26 以上（App Store または Apple Developer サイトから入手） |
| iOS | 26 以上（シミュレータ / 実機どちらも可） |
| Homebrew | XcodeGen のインストールに使用 |
| XcodeGen | 任意。`project.yml` から `xcodeproj` を再生成する際に必要 |
| Apple Developer Account | **不要**（Sprint 1 時点ではシミュレータで動作確認可） |

## 初回セットアップ手順

```bash
# 1. リポジトリを clone
git clone https://github.com/junhnam/iOS-GPSlog.git
cd iOS-GPSlog

# 2. XcodeGen をインストール（未インストールの場合のみ）
brew install xcodegen

# 3. Xcode プロジェクトを生成
xcodegen generate

# 4. Xcode で開く
open GPSLogger.xcodeproj
```

Xcode を起動すると、Google Maps SDK の Swift Package が自動的に解決されます（初回は数分かかります）。

## Google Maps API キーの設定

地図機能を使うには Google Cloud Console で発行した API キーが必要です。
キーが未設定でもアプリ自体は起動しますが、地図は真っ黒のまま表示されません（コンソールに警告が出ます）。

### 1. Google Cloud Console で API キーを発行

1. [Google Cloud Console](https://console.cloud.google.com/) にログイン
2. プロジェクトを作成（既存のものでも可）
3. 「APIとサービス」 → 「ライブラリ」で **Maps SDK for iOS** を有効化
4. 「APIとサービス」 → 「認証情報」 → 「APIキーを作成」
5. キーの制限で「iOS アプリ」を選び、Bundle ID `com.junhnam.gpslogger` を登録（推奨）

### 2. リポジトリ内に設定ファイルを配置

```bash
# テンプレートをコピーして、自分のキーで書き換える
cp GPSLogger/Resources/GoogleMaps-Info.plist.example GPSLogger/Resources/GoogleMaps-Info.plist
# 開いて GMSApiKey の値を、上で発行したキーに置き換える
open GPSLogger/Resources/GoogleMaps-Info.plist
```

### 3. ビルド（再生成は不要）

`GoogleMaps-Info.plist` は `.gitignore` で除外されているため、API キーがリポジトリにコミットされることはありません。

## ビルド・実行

### Xcode から実行（通常はこちら）

1. `GPSLogger.xcodeproj` を Xcode で開く
2. 上部のスキーム/シミュレータを `GPSLogger` / `iPhone 17` などに設定
3. ⌘R で実行

### コマンドラインからビルド

```bash
xcodebuild -project GPSLogger.xcodeproj \
  -scheme GPSLogger \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -configuration Debug build
```

`** BUILD SUCCEEDED **` が表示されればビルド成功です。

## シミュレータでの GPS テスト

iOS シミュレータには疑似 GPS データを流す機能があります。これを使えば実機がなくても経路描画の動作確認ができます。

1. シミュレータでアプリを起動
2. シミュレータのメニューバーから **Features → Location** を選択
3. 以下のいずれかを選ぶ:
   - **Apple** … Apple 本社周辺で固定
   - **City Bicycle Ride** … 自転車での市街地走行
   - **City Run** … ランニング経路
   - **Freeway Drive** … 高速道路を車で走行（推奨。経路ラインの確認に最適）
   - **Custom Location** … 緯度経度を直接指定

「Freeway Drive」を選ぶと、地図上に青いラインが継続的に描画されることが確認できます。

> 初回起動時に「位置情報の許可」を求めるダイアログが表示されます。「アプリの使用中は許可」または「常に許可」を選んでください。

## ディレクトリ構成

```
iOS-GPSlog/
├── GPSLogger/
│   ├── App/                    # アプリエントリポイント、ナビゲーション骨格
│   ├── Features/               # 機能別 UI（Map / History / Settings）
│   ├── Services/               # サービス層（LocationService 等）
│   ├── Models/                 # データモデル（Sprint 2 以降）
│   ├── Resources/              # Assets、Info.plist、GoogleMaps-Info.plist
│   └── Design/                 # Designer 用モック（ビルド対象外）
├── GPSLoggerTests/             # ユニットテスト
├── GPSLogger.xcodeproj/        # Xcode プロジェクト（XcodeGen で生成）
├── project.yml                 # XcodeGen 設定
├── .scrum/                     # スクラム開発のチケット・スプリント管理
└── README.md                   # 本ファイル
```

## 開発ワークフロー

このプロジェクトは **スクラム方式** で開発しています。

- スプリント計画 / チケット / ボードは `.scrum/` 配下で管理
  - `.scrum/config.md` … プロジェクト全体のメタ情報
  - `.scrum/sprint-{N}/plan.md` … スプリント計画
  - `.scrum/sprint-{N}/board.md` … 進捗ボード（Todo / In Progress / Review / Done）
  - `.scrum/tickets/S{N}-{nnn}.md` … 各チケットの詳細
- 各チケットは GitHub Issues とも紐付け（`github_issue` フィールド参照）
- ブランチ戦略: `main` ＋ `feature/sprint-{N}-{ticket-id}`
- コミットメッセージ: `feat:` / `fix:` / `chore:` / `docs:` のプレフィックス + `(S{N}-{nnn})`

## トラブルシューティング

### 地図が真っ黒で何も表示されない

- `GPSLogger/Resources/GoogleMaps-Info.plist` が存在しないか、`GMSApiKey` の値が空。Xcode のコンソールに `Google Maps API key is not configured` の警告が出ているはずです。
- API キーは設定したが地図が出ない場合: Google Cloud Console でキーの「iOS アプリ制限」が `com.junhnam.gpslogger` を許可しているか、Maps SDK for iOS が有効化されているかを確認してください。

### ビルドエラーが消えない / Swift Package が解決できない

DerivedData を削除してから再ビルドします:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/GPSLogger-*
xcodegen generate
open GPSLogger.xcodeproj
```

### シミュレータの位置情報が変化しない

- シミュレータを一度終了し、再起動してから **Features → Location → Freeway Drive** を再設定してください。
- アプリ側で位置情報の許可が「許可しない」になっていると更新が止まります。シミュレータの **Settings → プライバシーとセキュリティ → 位置情報サービス** で許可状態を確認してください。

## スクリーンショット

<!-- TODO(S1-009): メイン画面のスクリーンショットを Sprint 1 完了時に貼る -->
<!-- TODO: シミュレータで Freeway Drive 中の経路描画スクリーンショットを追加 -->

（Sprint 1 完了後に追加予定）

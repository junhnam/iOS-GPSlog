# Product Backlog: iOS GPSロガーアプリ

最終更新: 2026-05-05

## バックログ構成方針
- CLAUDE.md の全要件を 6 スプリントに分割
- Sprint 1〜2 で MVP（地図表示+経路+ピン+ローカルDB保存）を稼働させる
- Sprint 3〜4 で設定／同期系を整備
- Sprint 5 で外部クラウド連携（Google Drive / Dropbox）
- Sprint 6 で運用機能（DB自動消去、バッテリー最適化、リリース準備）

---

## 優先度: Must（MVP に必須）

### Sprint 1: プロジェクト基盤 + 地図表示 + 位置情報取得

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S1-001 | Xcode プロジェクト雛形作成 (SwiftUI / iOS 26+) | M | dev-1 | sprint | 1 |
| S1-002 | Swift Package Manager 設定 + Google Maps SDK 導入 | M | dev-1 | sprint | 1 |
| S1-003 | Info.plist に位置情報・バックグラウンド権限を設定 | S | dev-1 | sprint | 1 |
| S1-004 | アプリエントリポイント + ナビゲーション骨格 | S | dev-1 | sprint | 1 |
| S1-005 | LocationManager サービス実装 (Core Location ラッパー) | M | dev-2 | sprint | 1 |
| S1-006 | Google Maps ビュー（現在地表示） | M | dev-2 | sprint | 1 |
| S1-007 | 移動経路ライン描画（Polyline） | M | dev-2 | sprint | 1 |
| S1-008 | メイン画面 UI モック作成（Figma 風 SwiftUI プロトタイプ） | M | designer | sprint | 1 |
| S1-009 | README にビルド・実行手順を追記 | S | dev-1 | sprint | 1 |

### Sprint 2: ローカル DB + 滞留検出 + ピン記録

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S2-001 | SwiftData モデル定義（DailyLog / RoutePoint / Pin） | M | - | backlog | 2 |
| S2-002 | DBリポジトリ層（CRUD） | M | - | backlog | 2 |
| S2-003 | 走行中の RoutePoint 保存処理（経路の永続化） | M | - | backlog | 2 |
| S2-004 | 滞留検出アルゴリズム（10分以上同一エリア判定） | M | - | backlog | 2 |
| S2-005 | MKLocalSearch によるお店情報取得 | M | - | backlog | 2 |
| S2-006 | ピン記録 + 地図上ピン表示 | M | - | backlog | 2 |
| S2-007 | 日付単位の履歴一覧画面 | M | - | backlog | 2 |
| S2-008 | 履歴詳細画面 UI（地図+ピン+滞在情報） | M | - | backlog | 2 |

### Sprint 3: 設定画面 + 自宅登録 + 記録モード切替

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S3-001 | 設定画面の骨格（List + UserDefaults 連携） | M | - | backlog | 3 |
| S3-002 | 自宅位置の登録 UI（地図上タップ + 住所表示） | M | - | backlog | 3 |
| S3-003 | 自宅判定ロジック（半径 100m 以内で記録停止） | M | - | backlog | 3 |
| S3-004 | 常時記録 / トリガー記録の切替 | M | - | backlog | 3 |
| S3-005 | トリガー記録時の開始 / 停止フローティングボタン | M | - | backlog | 3 |
| S3-006 | Significant Location Changes による自宅退出検知 | M | - | backlog | 3 |
| S3-007 | 設定画面 UI デザイン | M | - | backlog | 3 |

### Sprint 4: iOSカレンダー同期 + CSV エクスポート（ローカル）

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S4-001 | EventKit 連携基盤（権限取得 + カレンダー選択） | M | - | backlog | 4 |
| S4-002 | 滞留ピン → カレンダーイベント自動作成 | M | - | backlog | 4 |
| S4-003 | カレンダー同期 ON/OFF 設定 | S | - | backlog | 4 |
| S4-004 | CSV エクスポート機能（DBスキーマそのまま出力） | M | - | backlog | 4 |
| S4-005 | UIDocumentPickerViewController での保存先選択 | M | - | backlog | 4 |
| S4-006 | エクスポート UI 画面 | M | - | backlog | 4 |

---

## 優先度: Should（MVP 後でも可）

### Sprint 5: クラウドストレージ同期

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S5-001 | Google Drive SDK 導入 + OAuth 認証 | L→分割 | - | backlog | 5 |
| S5-002 | Dropbox SDK 導入 + OAuth 認証 | L→分割 | - | backlog | 5 |
| S5-003 | クラウド保存先選択 UI | M | - | backlog | 5 |
| S5-004 | 自動同期 ON/OFF 設定 | S | - | backlog | 5 |
| S5-005 | 「GPSログ/{日付}/data.csv」階層での自動アップロード | M | - | backlog | 5 |
| S5-006 | 同期失敗時のリトライ + 通知 | M | - | backlog | 5 |

### Sprint 6: 運用機能 + リリース準備

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S6-001 | DBクリア機能（日付指定削除） | M | - | backlog | 6 |
| S6-002 | DB自動消去（1GB超で古い順削除） | M | - | backlog | 6 |
| S6-003 | バッテリー最適化（精度動的調整 / distanceFilter / 一時停止） | L→分割 | - | backlog | 6 |
| S6-004 | バックグラウンド復帰時の挙動安定化 | M | - | backlog | 6 |
| S6-005 | アプリアイコン + ローンチスクリーン | M | - | backlog | 6 |
| S6-006 | App Store 申請用メタデータ準備 | M | - | backlog | 6 |
| S6-007 | プライバシーマニフェスト作成 | S | - | backlog | 6 |

---

## 優先度: Could（余裕があれば）

| ID | タイトル | 見積 | スプリント |
|---|---|---|---|
| C-001 | ピンの手動編集（場所名・メモ） | M | - |
| C-002 | 月次サマリ画面（移動距離・滞在時間集計） | L | - |
| C-003 | 経路の色分け（速度や時間帯で） | M | - |
| C-004 | iCloud バックアップ対応 | M | - |

---

## 優先度: Won't（今回スコープ外）

- Android 版
- 複数ユーザー対応／クラウド同期（位置情報の共有）
- リアルタイム共有機能
- Apple Watch 連携

---

## 全体サマリ

| スプリント | 主テーマ | チケット数 | 主目標 |
|---|---|---|---|
| 1 | プロジェクト基盤＋地図 | 9 | シミュレータで地図に経路表示 |
| 2 | DB＋滞留検出＋ピン | 8 | 滞留時にピンが記録される |
| 3 | 設定／自宅／記録モード | 7 | バッテリー懸念のベース対策 |
| 4 | カレンダー同期＋CSV出力 | 6 | データの外部化 |
| 5 | クラウド同期 | 6 | Drive/Dropbox 連携 |
| 6 | 運用＋リリース準備 | 7 | App Store 申請可能状態 |
| 合計 | | **43** | |

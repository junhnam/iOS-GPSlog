# Product Backlog: iOS GPSロガーアプリ

最終更新: 2026-05-06（Sprint 5 planning_review 時点）

## バックログ構成方針
- CLAUDE.md の全要件を 6 スプリントに分割
- Sprint 1〜2 で MVP（地図表示+経路+ピン+ローカルDB保存）を稼働させる
- Sprint 3〜4 で設定／同期系を整備
- Sprint 5 で外部クラウド連携（Google Drive / Dropbox）
- Sprint 6 で運用機能（DB自動消去、バッテリー最適化、リリース準備）

---

## 優先度: Must（MVP に必須）

### Sprint 1: プロジェクト基盤 + 地図表示 + 位置情報取得（完了）

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S1-001 | Xcode プロジェクト雛形作成 (SwiftUI / iOS 26+) | M | dev-1 | done | 1 |
| S1-002 | Swift Package Manager 設定 + Google Maps SDK 導入 | M | dev-1 | done | 1 |
| S1-003 | Info.plist に位置情報・バックグラウンド権限を設定 | S | dev-1 | done | 1 |
| S1-004 | アプリエントリポイント + ナビゲーション骨格 | S | dev-1 | done | 1 |
| S1-005 | LocationManager サービス実装 (Core Location ラッパー) | M | dev-2 | done | 1 |
| S1-006 | Google Maps ビュー（現在地表示） | M | dev-2 | done | 1 |
| S1-007 | 移動経路ライン描画（Polyline） | M | dev-2 | done | 1 |
| S1-008 | メイン画面 UI モック作成（Figma 風 SwiftUI プロトタイプ） | M | designer | done | 1 |
| S1-009 | README にビルド・実行手順を追記 | S | dev-1 | done | 1 |

### Sprint 2: ローカル DB + 総移動距離 + 滞留検出 + 復元 + 履歴タブ

スプリントゴール: アプリを閉じても経路・ピン・総移動距離が復元できる状態を作る

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S2-001 | SwiftData モデル定義（TripRecord / RoutePoint / PinRecord、totalDistanceMeters 含む） | M | dev-1 | sprint | 2 |
| S2-002 | ModelContainer セットアップとアプリ統合 | M | dev-1 | sprint | 2 |
| S2-003 | TripRepository（取得・作成・更新・距離加算） | M | dev-1 | sprint | 2 |
| S2-004 | 総移動距離計算ロジック（CLLocation.distance ベース、km 表示） | S | dev-2 | sprint | 2 |
| S2-005 | LocationService と DB の連携（RoutePoint 永続化 + 距離加算） | M | dev-2 | sprint | 2 |
| S2-006 | 滞留検出（10分・30m半径）と PinRecord 作成 | M | dev-2 | sprint | 2 |
| S2-007 | アプリ起動時の最新 TripRecord 復元（経路・ピン・総移動距離） | M | dev-1 | sprint | 2 |
| S2-008 | 履歴タブ実装（日付一覧 + 詳細で経路・ピン・距離・滞留時間） | M | dev-2 | sprint | 2 |

注: Sprint 2 では「お店情報の自動取得（旧 MKLocalSearch チケット）」は **Sprint 3 へ移動**。理由は (1) 自宅判定とセットの方が UX 上自然、(2) Sprint 2 のキャパシティを復元・履歴に集中させるため。

### Sprint 3: 設定画面 + 自宅登録 + 記録モード + お店情報 + 復元エラー通知（完了）

スプリントゴール: 自宅 / 外出を区別して記録モードを自動切替し、滞留地点に店舗情報を紐付ける

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S3-001 | 設定画面の骨格（List + UserDefaults + AppSettings） | M | dev-1 | done | 3 |
| S3-002 | 自宅位置の登録 UI（地図ピック + 住所 + 候補選択） | M | dev-1 | done | 3 |
| S3-003 | 自宅判定ロジック（半径内で記録自動停止） | M | dev-2 | done | 3 |
| S3-004 | 常時 / トリガー記録モード切替（AppSettings 統合） | S | dev-1 | done | 3 |
| S3-005 | トリガー記録用フローティングボタン（開始/停止） | M | dev-1 | done | 3 |
| S3-006 | Significant Location Changes 併用 + 動的精度調整 | M | dev-2 | done | 3 |
| S3-007 | MKLocalSearch によるお店情報取得（placeName/placeURL） | M | dev-2 | done | 3 |
| S3-008 | restoreTodayTrip の silent failure をユーザー通知化（retro #4） | S | dev-1 | done | 3 |
| S3-009 | iOS 26 SwiftData / Swift 6 落とし穴メモを notes 化（retro Try） | S | dev-1 | done | 3 |

注: Sprint 3 では旧バックログの「設定画面 UI デザイン」独立チケットは S3-001 / S3-002 / S3-005 に内包し、S3-008（復元エラー通知）と S3-009（落とし穴ノート）を Sprint 2 retro/QA 申し送りから繰り上げて 9 件構成。Sprint 6 候補だった Significant Location Changes は S3-006 として先取り。

### Sprint 4: iOS 26 API 移行 + iOSカレンダー同期 + CSV エクスポート（ローカル・完了）

スプリントゴール: 移動記録を外部に持ち出せる状態を作る（カレンダー連携 + CSV 出力）

| ID | タイトル | 見積 | 担当 | ステータス | スプリント |
|---|---|---|---|---|---|
| S4-001 | CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002 解消・jun さん指示で冒頭に固定） | M | dev-2 | done | 4 |
| S4-002 | EventKit 連携基盤（権限取得 + カレンダー選択） | M | dev-2 | done | 4 |
| S4-003 | 滞留ピン → カレンダーイベント自動作成 | M | dev-2 | done | 4 |
| S4-004 | カレンダー同期 ON/OFF 設定 | S | dev-1 | done | 4 |
| S4-005 | CSV エクスポート機能（DBスキーマそのまま出力） | M | dev-2 | done | 4 |
| S4-006 | UIDocumentPickerViewController での保存先選択 | M | dev-1 | done | 4 |
| S4-007 | エクスポート UI 画面 | M | dev-1 | done | 4 |
| S4-008 | MapView HUD warning ロジックを HomeDetector へ統一（Sprint 3 retro #4） | S | dev-1 | done | 4 |

加えて QA フェーズで Agent A が QA-S4-001（MKMapItem.placemark deprecated 解消）を 42e1b2c で修正。QA-S4-002（CalendarSyncService.addressFromPlaceURL の no-op fallback）は Low で機能影響なしのため Sprint 5 へ申し送り。

注: 旧 S4-001（EventKit 連携基盤）から S4-007（CLGeocoder 移行）の番号を、jun さん指示「CLGeocoder は Sprint 4 の最初に対応」を反映して再採番。新 S4-001 を CLGeocoder 移行、メインスコープのカレンダー / CSV を S4-002〜S4-007 に詰め直し、Sprint 3 retro #4（MapView HUD 重複解消）を S4-008 として追加した。Sprint 3 申し送り 6 件のうち、残る #2 / #3（strict concurrency warning）と #7（RootView の Environment 整理）は Sprint 5 へ、#5 / #6（MKLocalSearch / SLC 実機検証）は Sprint 6（バッテリー実機検証時）へ繰越。

---

## 優先度: Should（MVP 後でも可）

### Sprint 5: クラウドストレージ同期 + 申し送り解消（planning_review）

スプリントゴール: **移動記録をクラウドストレージに自動同期し、機器を変えても残せる状態にする**

| ID | タイトル | 見積 | 担当 | 優先度 | ステータス | スプリント |
|---|---|---|---|---|---|---|
| S5-001 | Google Drive SDK 導入 + OAuth 認証 | L→分割可 | dev-2 | must | sprint | 5 |
| S5-002 | Dropbox SDK 導入 + OAuth 認証 | L→分割可 | dev-2 | should | sprint | 5 |
| S5-003 | クラウド保存先選択 UI | M | dev-1 | must | sprint | 5 |
| S5-004 | 自動同期 ON/OFF 設定 | S | dev-1 | must | sprint | 5 |
| S5-005 | 「GPSログ/{日付}/data.csv」階層での自動アップロード | M | dev-2 | must | sprint | 5 |
| S5-006 | 同期失敗時のリトライ + 通知 | M | dev-2 | must | sprint | 5 |
| S5-007 | PinRecord.address 追加 + addressFromPlaceURL 実体化（QA-S4-002 解消） | M | dev-2 | must | sprint | 5 |
| S5-008 | MapView Coordinator strict concurrency warning 解消（Sprint 4 申し送り #1） | S | dev-1 | should | sprint | 5 |
| S5-009 | テスト群の @MainActor strict concurrency warning 解消（Sprint 4 申し送り #2） | M | dev-1 | could | sprint | 5 |

注:

- S5-007 は jun さん指示「PinRecord に address を追加」を反映した Sprint 4 申し送り #3 のチケット化
- S5-008 / S5-009 は Sprint 4 申し送り #1 / #2 を取り込み（concurrency warning。クラウド連携と独立で吸収可能）
- S5-002 は jun さんの「Sprint 5 で Dropbox を入れるか / Sprint 6 へ繰越か」の判断次第。Sprint 6 へ繰越時は Sprint 5 を 8 チケット構成（Must 5 / Should 1 / Could 1）にする
- パッケージ追加（Google Drive / Dropbox SDK）は development 開始**前**に jun さん承認を取得
- 運用変更: Dev フェーズ完了基準に「`xcodebuild clean build` warning 0 確認」を追加（`.scrum/process/dev-completion-checklist.md` 新規作成）。Sonnet サブエージェントの xcodebuild は引き続きメインエージェント（Opus）が代行

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
| 1 | プロジェクト基盤＋地図 | 9 | シミュレータで地図に経路表示（達成済） |
| 2 | DB＋総移動距離＋滞留＋復元＋履歴 | 8 | 閉じても復元できる状態を作る |
| 3 | 設定／自宅／記録モード／お店情報／復元通知／ノート | 9 | バッテリー懸念のベース対策＋ピン情報拡充＋retro 反映 |
| 4 | iOS 26 API 移行＋カレンダー同期＋CSV出力＋HUD 統一 | 8 | データの外部化 + 申し送り解消 |
| 5 | クラウド同期＋申し送り解消 | 9（Dropbox 繰越時 8） | Drive/Dropbox 連携 + concurrency warning 解消 + PinRecord.address |
| 6 | 運用＋リリース準備 | 7（+α Dropbox 繰越時） | App Store 申請可能状態 |
| 合計 | | **約 50** | |

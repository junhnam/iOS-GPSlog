# Sprint 2 Plan

- スプリント期間: 2026-05-05 起点（1イテレーション完結）
- 体制: PO/SM + Dev x2（Dev-1 / Dev-2）+ QA（qa-multi-agent）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ）

---

## スプリントゴール

> アプリを閉じても、経路・ピン・総移動距離が復元できる状態を作る。

検証条件:
- iOS シミュレータで Freeway Drive を流し、アプリを kill → 再起動したときに、polyline・ピン・総移動距離（km）が復元される
- 同シナリオで 10 分以上の停止を挟むと PinRecord が自動生成され、復元時にも残っている
- ユニットテストでデータ層・ロジック層が独立に動くこと（pass 100%）

---

## Sprint 2 のテーマ

CLAUDE.md の MVP 定義「Sprint 1〜2 までで地図表示+経路+ピン+ローカルDB保存が動く」を、
Sprint 2 で **「保存して終わり」ではなく「閉じても続きから動く」** レベルまで引き上げる。

ユーザー要望で追加された「**総移動距離(km)**」も Sprint 2 で同時に対応する（CLAUDE.md 更新済）。

---

## チケット一覧（8件）

| ID | タイトル | 担当 | 見積 | 依存 |
|---|---|---|---|---|
| S2-001 | SwiftData モデル定義（TripRecord / RoutePoint / PinRecord） | dev-1 | M | - |
| S2-002 | ModelContainer セットアップとアプリ統合 | dev-1 | M | S2-001 |
| S2-003 | TripRepository（取得・作成・更新・距離加算） | dev-1 | M | S2-001, S2-002 |
| S2-004 | 総移動距離計算ロジック（CLLocation.distance ベース） | dev-2 | S | - |
| S2-005 | LocationService と DB の連携（永続化 + 距離加算） | dev-2 | M | S2-003, S2-004 |
| S2-006 | 滞留検出（10分・30m半径）と PinRecord 作成 | dev-2 | M | S2-001, S2-005 |
| S2-007 | アプリ起動時の最新 TripRecord 復元 | dev-1 | M | S2-001〜005 |
| S2-008 | 履歴タブ実装（日付一覧 + 詳細） | dev-2 | M | S2-001〜006 |

合計: 7M + 1S = 中〜大規模（Sprint 1 と同等以上）

---

## 担当分担方針

ファイル競合を避けるため、Dev-1 / Dev-2 を**レイヤー軸 + 機能軸の混合**で分割する。

### Dev-1: データ層 + 復元（4チケット）
- S2-001: `GPSLogger/Models/{TripRecord,RoutePoint,PinRecord}.swift` 新規
- S2-002: `GPSLogger/Services/Persistence/PersistenceController.swift` 新規 + `GPSLoggerApp.swift` 修正
- S2-003: `GPSLogger/Services/Persistence/TripRepository.swift` 新規
- S2-007: `GPSLogger/Features/Map/MapViewModel.swift`（or Coordinator 拡張）+ MapView との接続

担当範囲のキーワード: **「保存」と「読み出し」を一気通貫で担当**

### Dev-2: ロジック + UI（4チケット）
- S2-004: `GPSLogger/Services/Trip/TripDistanceCalculator.swift` 新規（純粋関数）
- S2-005: `GPSLogger/Services/Location/LocationService.swift` 拡張（既存）
- S2-006: `GPSLogger/Services/Trip/StayDetector.swift` 新規 + LocationService フック
- S2-008: `GPSLogger/Features/History/{HistoryListView,HistoryDetailView}.swift` 新規

担当範囲のキーワード: **「センサーデータ → ロジック → 表示」のパイプラインを担当**

### 共有ファイル（要連携）
- `project.yml`: S2-001 で sources 追加が必要。Dev-1 が触る回を最初の1回にまとめる
- `LocationService.swift`: Sprint 1 で Dev-2 が作成済。S2-005 / S2-006 とも Dev-2 の担当なので競合なし
- `MapView.swift`: Sprint 1 で Dev-2 が作成済。S2-007 で Dev-1 が「VM/Coordinator の差し込み口」だけ追加。MapView 本体には触らず Coordinator 経由で操作する

### 競合ガード
- Dev-1 の S2-007 は他の S2-001〜005 が完了してから着手（依存が満たされてから）
- Dev-2 の S2-008 は S2-006 完了後に着手
- 並行可能な区間: S2-001〜003（Dev-1）と S2-004（Dev-2）は完全並列。Dev-2 は S2-004 → S2-005 待機 → S2-006 → S2-008 の順

---

## 実行順序の目安

```
Day 1 前半:
  Dev-1: S2-001 → S2-002
  Dev-2: S2-004（独立）

Day 1 後半:
  Dev-1: S2-003
  Dev-2: S2-005（S2-003 + S2-004 完了待ち）

Day 2 前半:
  Dev-1: S2-007（S2-001〜005 完了待ち）
  Dev-2: S2-006

Day 2 後半:
  Dev-2: S2-008（S2-006 完了後）
  Dev-1: S2-007 完了 → 全体結合確認

QA フェーズ:
  qa-multi-agent でテスト → 不具合修正 → 再テスト
```

---

## DB スキーマ設計

### TripRecord
- `date: Date`（`@Attribute(.unique)`、当日0時固定、主キー）
- `startedAt: Date`
- `endedAt: Date?`
- `totalDistanceMeters: Double`（内部メートル保持）
- `routePoints: [RoutePoint]`（cascade delete）
- `pins: [PinRecord]`（cascade delete）
- 計算プロパティ: `totalDistanceKm: Double`（小数点第2位、表示用）

### RoutePoint
- `latitude: Double` / `longitude: Double` / `timestamp: Date`
- `trip: TripRecord?`（逆参照）

### PinRecord
- `latitude: Double` / `longitude: Double`
- `stayedFrom: Date` / `stayedDurationSeconds: Double`
- `placeName: String?` / `placeURL: URL?`（**Sprint 3 で MKLocalSearch 連携、Sprint 2 では nil**）
- `trip: TripRecord?`（逆参照）

### 設計判断
- 距離は内部「メートル」で保持し、表示時に km へ変換（精度ロス防止）
- 日付PKは `Calendar.current.startOfDay(for:)` で正規化
- お店情報フィールドは Sprint 2 でフィールドだけ用意（Sprint 3 のスキーマ変更コストを下げる）

---

## Sprint 1 retro からの反映

| Try 項目 | Sprint 2 での扱い |
|---|---|
| Sprint 2 開始前の実機確認チェックポイント | jun さんに「Sprint 1 シミュレータ検証」を planning_review 段階で依頼（このプランのレビュー時に確認） |
| QA 開始時に Task ツール可否を確認 | qa-multi-agent 起動時の最初の手順として Agent A が判定する運用を継続 |
| Xcode Canvas エクスポート（PNG2枚） | jun さん側タスク。Sprint 2 のキックオフ時に再依頼 |
| 区切りでの push 確認 | Dev フェーズ完了直後と Sprint 完了時の2回、PO/SM が push 確認をユーザーに行う |
| GitHub Issue クローズ自動化 | Sprint 2 完了時に board.md の Done 列から `gh issue close` 一括実行する手順を retro に追記予定 |
| `.qa-workspace/` の `.gitignore` 反映 | Sprint 2 冒頭で必ずコミット（Agent F が修正済・未コミット） |

---

## バッテリー消費の進捗（更新）

Sprint 1 で実装済の対策に加え、Sprint 2 では:
- 5m 未満の点間引き（S2-005）→ DB 書き込み頻度削減
- 滞留中の RoutePoint 間引き（S2-006）→ 同一場所で延々と座標を保存しない

未対応（後続スプリントへ）:
- 自宅滞在時の完全停止（Sprint 3）
- Significant Location Changes API 併用（Sprint 3）
- desiredAccuracy の動的調整（Sprint 3）

---

## QA 計画（フェーズ3 で実施）

qa-multi-agent スキル起動時の主要観点:
- 起動 → kill → 再起動で経路・ピン・距離が復元される
- シミュレータの Simulate Location（Freeway Drive / City Run / Custom）で経路保存・距離計算が正しい
- 滞留シナリオ（同一座標を 10 分以上模擬）で PinRecord が作成される
- 履歴タブから過去データを開いて、地図・ピン・距離が再描画される
- ビルド warning 0 / ユニットテスト pass 100%

---

## 完了条件

- 全8チケットが Done
- ビルド warning 0、ユニットテスト pass 100%
- スプリントゴール（kill → 再起動で復元）が iOS シミュレータで確認可能
- レビュー / レトロ文書を作成し、ユーザー承認を得る

---

## ブロッカー候補と対策

| 候補 | 影響 | 対策 |
|---|---|---|
| SwiftData マイグレーション失敗（Sprint 1 起動 DB が未初期化のまま Sprint 2 のスキーマが適用される） | 中 | Sprint 1 ではまだ DB を持っていないため発生しない想定。万一発生時は PersistenceController がインメモリへフォールバック |
| `@Model` のリレーション双方向定義の罠 | 低 | `@Relationship(deleteRule: .cascade, inverse: ...)` を必ず両側に書く運用をモデルファイルに日本語コメントで明示 |
| Swift 6 strict concurrency と SwiftData の組み合わせ | 中 | リポジトリ層を `@MainActor` 前提に統一、`ModelContext` は main で扱う |
| Xcode 環境差異 | 中 | jun さん側で Sprint 1 と同じ手順でビルド確認（XcodeGen → ⌘B）。失敗時の切り分け手順を README に整備済 |

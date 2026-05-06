# Sprint 4 Plan

- スプリント期間: 2026-05-06 開始（1 イテレーション完結予定）
- 体制: PO/SM + Dev x2（Dev-1 / Dev-2）+ QA（Single-Agent モード継続見込み）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・Sprint 3 まで origin と同期済 = a4ab592）

---

## スプリントゴール

> **移動記録を外部に持ち出せる状態を作る（カレンダー連携 + CSV 出力）**

達成判定:

| # | 判定基準 | 確認方法 |
|---|---|---|
| 1 | 滞留ピンが立った時に iOS カレンダーへ自動で予定が登録される（同期 ON 時） | EventKit の権限取得 + S4-003 のテスト + シミュレータでのカレンダーアプリ確認 |
| 2 | 設定画面でカレンダー同期の ON/OFF と対象カレンダーが選べる | S4-004 のテスト + 設定画面の静的レビュー |
| 3 | 「設定 → エクスポート」から CSV を書き出し、保存先を選んで保存できる | S4-005 / S4-006 / S4-007 のテスト + シミュレータでの fileExporter 動作確認 |
| 4 | フル再コンパイルで CLGeocoder の deprecated warning が 0 件になる | `xcodebuild -clean -build` の警告ゼロ確認（QA-S3-002 解消） |
| 5 | MapView HUD の自宅判定ロジックが HomeDetector 1 箇所に集約されている | S4-008 のテスト + コード静的レビュー |

ユニットテスト + 静的レビューで 1〜5 を担保し、jun さん側のシミュレータ確認は別途依頼する。

---

## スプリントバックログ

| ID | タイトル | type | 見積 | 担当 | 優先度 |
|---|---|---|---|---|---|
| S4-001 | CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002 解消） | chore | M | dev-2 | must |
| S4-002 | EventKit 連携基盤（権限取得 + カレンダー選択） | feature | M | dev-2 | must |
| S4-003 | 滞留ピン → カレンダーイベント自動作成 | feature | M | dev-2 | must |
| S4-004 | カレンダー同期 ON/OFF 設定 | feature | S | dev-1 | must |
| S4-005 | CSV エクスポート機能（DBスキーマそのまま出力） | feature | M | dev-2 | must |
| S4-006 | UIDocumentPickerViewController での保存先選択 | feature | M | dev-1 | must |
| S4-007 | エクスポート UI 画面 | feature | M | dev-1 | must |
| S4-008 | MapView HUD warning ロジックを HomeDetector へ統一 | chore | S | dev-1 | should |

合計 8 チケット（M=6 / S=2）。Sprint 3 と同等のキャパシティ（Sprint 3 は M=6 / S=3 = 9 チケットで完了率 100%）。

---

## 担当分割の方針

ファイル競合をゼロに保つために以下のルールで分ける:

### Dev-1（設定 / UI 系）

- `Features/Settings/` 内の **新規ファイル**（`CalendarPickerView.swift`）
- `Features/Settings/SettingsView.swift` の **「カレンダー同期」「データ」セクション追記**
- `Features/Export/` ディレクトリ全体（`ExportView.swift` / `DocumentPickerView.swift` / `CSVExportDocument.swift` / `ExportViewModel.swift`）
- `Features/Map/MapView.swift` の **HUD 表示判定部分のみ**（S4-008）
- 担当チケット: **S4-004 / S4-006 / S4-007 / S4-008**

### Dev-2（サービス / ロジック系）

- `Services/Place/PlaceLookupService.swift`（S4-001 の `AppleGeocoder` 部分）
- `Features/Settings/HomeRegistrationView.swift` の **CLGeocoder 利用部分のみ**（S4-001。Dev-1 は同ファイルの設定セクションは触らない約束）
- `Services/Calendar/CalendarSyncService.swift`（新規）
- `Services/Export/CSVExportService.swift`（新規）
- `Models/AppSettings.swift` の **calendarSyncEnabled / calendarIdentifier 追加**（Dev-1 の S4-004 と協業。Dev-2 が AppSettings 拡張、Dev-1 が UI 側）
- `Models/PinRecord.swift` の **calendarEventIdentifier 追加**（S4-003）
- 担当チケット: **S4-001 / S4-002 / S4-003 / S4-005**

### 共有ファイル（事前合意）

- `Models/AppSettings.swift`: Dev-2 が S4-002 着手時に `calendarSyncEnabled` / `calendarIdentifier` を追加 → Dev-1 が S4-004 で UI バインドのみ参照
- `Features/Map/MapView.swift`: Dev-1 が S4-008 で HUD 判定部分のみ編集（Dev-2 は本ファイルを触らない）
- `Features/Settings/SettingsView.swift`: Dev-1 が S4-004 / S4-007 で 2 セクション追加（Dev-2 は触らない）
- `Features/Settings/HomeRegistrationView.swift`: Dev-2 が S4-001 で CLGeocoder 部分のみ書き換え（Dev-1 は触らない）

git 競合 0 件を Sprint 3 から継続する。

---

## 着手順序の推奨

1. **S4-001（CLGeocoder 移行）**: jun さん指示で**冒頭固定**。Dev-2 が最優先で着手し、iOS 26 API 流儀をプロジェクトに揃える。
2. **S4-002（EventKit 連携基盤）**: S4-001 完了後に Dev-2 が着手。`AppSettings` に `calendarSyncEnabled` / `calendarIdentifier` を追加するタイミングで Dev-1 へ通知する。
3. **S4-004（カレンダー同期設定）**: Dev-1 は S4-002 の AppSettings 追加完了後に着手。並行で **S4-008（HUD 統一）** を進められる。
4. **S4-003（カレンダーイベント自動作成）**: S4-002 が動く状態になったら Dev-2 が着手。
5. **S4-005（CSV 出力ロジック）**: Dev-2 は S4-003 と並行 or 後段で着手。CSV 出力は独立サービスなので順序自由。
6. **S4-006（fileExporter / FileDocument）**: Dev-1 は S4-004 / S4-008 完了後に着手。CSV 出力ロジック（S4-005）の URL 仕様だけ Dev-2 と事前合意。
7. **S4-007（エクスポート UI）**: Dev-1 が S4-005 / S4-006 揃った後に統合。

並行のしやすさ:

```
時系列 →
Dev-2: S4-001 -> S4-002 -> S4-003 -> S4-005
Dev-1:                     S4-008 -> S4-004 -> S4-006 -> S4-007
                           (S4-002 の AppSettings 拡張完了を待つ)
```

---

## Sprint 3 申し送り 6 件の取り込み判断

| # | 申し送り内容 | Sprint 4 での扱い | 理由 |
|---|---|---|---|
| 1 | CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002） | **取り込み（S4-001）** | jun さん指示で Sprint 4 冒頭固定 |
| 2 | MapView Coordinator strict concurrency warning（フル再ビルド時のみ） | **Sprint 5 へ繰越** | 外形 warning。Sprint 4 のメインスコープ（カレンダー / CSV）にキャパを使う |
| 3 | テスト群 @MainActor strict concurrency warning（フル再ビルド時のみ） | **Sprint 5 へ繰越** | 同上 |
| 4 | MapView HUD warning ロジックを HomeDetector に統一（重複実装） | **取り込み（S4-008）** | Sprint 3 retro Try で先送りした技術メモ通り。S サイズで Dev-1 のキャパに余裕 |
| 5 | MKLocalSearch レート制限の実機検証 | **Sprint 6 へ** | バッテリー実機検証と一緒に実施するのが効率的 |
| 6 | SLC 実機検証 | **Sprint 6 へ** | 同上 |
| 7 | RootView AppSettings の `@Environment` ベース整理 | **Sprint 5 へ繰越** | 構造リファクタ。Sprint 5 のクラウド同期で RootView 周辺を触る前段で実施 |

Sprint 4 のキャパシティを「メインスコープ + jun さん指示の S4-001 + 重複解消の S4-008」に集中させ、外形 warning とリファクタは Sprint 5 にまとめる方針。

---

## 受け入れ条件（スプリント全体）

- [ ] 全 8 チケットが Done
- [ ] スプリントゴール判定基準 1〜5 すべて静的に確認可能
- [ ] フル再コンパイル warning 0、ユニットテスト pass 100%（既存 79 件 + Sprint 4 で追加されるテスト）
- [ ] Sprint 1 / Sprint 2 / Sprint 3 で導入したテスト 79 件の回帰なし
- [ ] API キー漏洩スキャン 0 件（`AIza` で grep 0 を継続）
- [ ] レビュー / レトロ文書を作成
- [ ] jun さん承認（git push 承認 = 各 Sprint と同様の流れ）

---

## QA 観点（Sprint 4 想定）

QA フェーズで qa-multi-agent スキルを起動する際の主要観点:

| 観点 | 目的 | 期待 |
|---|---|---|
| カレンダー権限フロー | requestFullAccess の境界（許可 / 拒否 / 未決定） | 拒否時に Toggle が OFF へ戻る |
| カレンダー同期重複 | 同じ PinRecord に 2 回 createEvent しても 1 件のみ作成 | 2 回目の呼び出しで `calendarEventIdentifier` を再利用 |
| CSV エスケープ | `,` `"` `\n` を含む placeName / address が正しくエスケープされる | RFC 4180 準拠 |
| CSV インジェクション | `=`, `+`, `-`, `@` で始まる値の先頭にシングルクォート | 全て検証 |
| UTF-8 BOM | エクスポートファイル先頭が `EF BB BF` で始まる | バイナリ検証 |
| fileExporter キャンセル | キャンセルしてもアプリがクラッシュしない | onCompletion で `.failure(.cancelled)` を握る |
| HomeDetector HUD 統一 | MapView と HomeDetector の判定が同一 | 両方の atHome 判定が一致 |
| iOS 26 API 流儀 | MKReverseGeocodingRequest 失敗時のフォールバック | 既存挙動と差分なし |

QA 観点 50〜60 件を目標。Sprint 3 は 60 件で 100% 充足したので同等を維持する想定。

---

## リスクと対策

| リスク | 対策 |
|---|---|
| EventKit 権限ダイアログがシミュレータで挙動が完全には再現しない | ユニットテストでは `EKEventStore` をモック化し、シミュレータ実機相当の確認は jun さん依頼項目に追加する |
| iOS 26 の MKReverseGeocodingRequest API が想定と異なる引数 | S4-001 開始時に Apple 公式ドキュメントを確認し、想定と差異があれば PO/SM に即報告（停止して相談）。Sprint 4 のメインスコープを止めないよう冒頭固定にしているのはこのため |
| AppSettings に複数プロパティを追加することによる既存テストの回帰 | Sprint 3 の AppSettingsTests 8 ケースを必ず通すこと。新規プロパティは Optional or 既定値ありで後方互換を確保 |
| PinRecord に新規プロパティ（calendarEventIdentifier）を追加することによる SwiftData マイグレーション | iOS 26 SwiftData ノート #5 「新規プロパティは Optional」のルールに従う。`String?` で追加 |
| Dev-2 の作業集中（4 チケット）による持ち越し | 並列着手可能な S4-005（CSV）を Dev-2 のバッファとし、進捗が苦しくなったら Dev-1 が S4-005 をピックする待機運用を許可 |
| jun さんが非エンジニアのため、技術用語が伝わらない | チケット末尾の「平易な補足」を必ず書く。Sprint 3 と同様の運用を継続 |

---

## ノート（Sprint 4 開始前に作成）

- `.scrum/notes/ios26-api-changes.md`（Sprint 3 retro Try）: iOS 26 で deprecated になった API の集約。CLGeocoder 起点
- `.scrum/notes/simulator-scenarios.md`（Sprint 3 retro Try）: jun さんがシミュレータで Sprint レビュー確認するための Simulate Location 手順集

---

## 完了基準

- [ ] 全 8 チケット Done
- [ ] スプリントゴール判定基準 1〜5 OK
- [ ] フル再ビルド warning 0
- [ ] ユニットテスト pass 100%（既存 79 + 追加分）
- [ ] QA フェーズで残存バグ 0
- [ ] レビュー / レトロ文書を作成
- [ ] jun さん承認 + git push（Sprint 3 と同じフロー）

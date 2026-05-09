# Sprint 6 Board

## Sprint Goal

> **個人利用版として jun さんの iPhone 16 Pro に Xcode から実機インストールでき、CLAUDE.md 記載の全機能（DB クリア / DB 自動消去 / バッテリー最適化を含む）が実機で動作する状態に到達する**

期間: 2026-05-07 開始（最終スプリント）
フェーズ: **development**（jun さん 5 項目回答取得済 2026-05-06）
方針: A 案採用（1-sprint 完結 / 個人利用版リリース）

---

## Todo

- [ ] **S6-008** (#51): 実機検証総合チェック（MKLocalSearch / SLC / バッテリー実測 / バックグラウンド / アイコン） → **po-sm** / Must / M（**S6-010 完了後に再実行**）

## In Progress

- [ ] **S6-010** (TBD): 滞留検知の堅牢化（B: RoutePoint 後追い検知 + A: StayDetector 状態永続化） → **dev-2** / Must / L（実機検証で発覚 / Sprint Goal 直結 / S6-008 再実行の前提）

## Done

- [x] **S6-001** (#44): DI 経路カバレッジテストの定型化（`dev-completion-checklist.md` 改訂 + `RootViewIntegrationTests.swift` 末尾雛形コメント追加） → **po-sm（メイン代行）** / Must / S（コミット `954f23d` / 既存 173 テスト pass / 回帰なし）
- [x] **S6-002** (#45): `AppDependencyContainer` 導入（`RootView.init` の DI 集約 / `@MainActor final class`） → **dev-1** / Must / M（コミット `8853972` / 176/176 pass / DI 検証ケース 3 件追加 / Swift 6 strict concurrency 整合）
- [x] **S6-009** (#52): QA-S5-004 retryCount 加算 + QA-S5-003 Info.plist 運用整理（Google Drive 限定） → **dev-2** / Should / S（コミット `39dba0e` / 179/179 pass / CSV 失敗時 retryCount 加算ロジック + テスト 3 件 / `.gitignore` + `.example` + `oauth-setup.md` / メイン代行修正: テスト DI 漏れ 1 件）
- [x] **S6-004** (#47): DB 自動消去（1GB 超で古い順削除 + 設定 ON/OFF Toggle） → **dev-2** / Must / M（コミット `7029d2f` / 185/185 pass / `DatabaseAutoCleanupService` 新規 + AppSettings 拡張 + LocationService 連携 + Container 統合 + Settings UI / 単体テスト 5 件 + DI カバレッジ 1 件 / メイン代行修正: `ModelContainer.defaultDirectoryURL` → `FileManager` 経由に変更 + `attrs[.size]` → `attrs[FileAttributeKey.size]` 明示）
- [x] **S6-005** (#48): バッテリー最適化（精度動的 / distanceFilter / pausesLocationUpdatesAutomatically 検証） → **dev-2** / Must / L（コミット `bb7e7c0` / 193/193 pass / warning 0 / `BatteryAdaptiveLocationPolicy` Sendable 構造体新規 + LocationService 統合（distanceFilter 動的切替）+ pausesLocationUpdatesAutomatically=true 確認済 / 単体テスト 7 件 + DI 統合 1 件 = 計 8 件追加 / メイン代行確認済）
- [x] **S6-006** (#49): バックグラウンド復帰時の挙動安定化（SLC 復帰 / applicationDidBecomeActive 経路） → **dev-2** / Must / M（コミット `0bce4be` / 204/204 pass / warning 0 / `AppSettings.wasTracking` 追加 + `LocationService.startTrackingFromSLC()` / `resumeTrackingAfterRelaunch()` 新規 + `RootView.onChange(scenePhase)` 追加 / 単体テスト 6 件 + DI カバレッジ 1 件 = 計 7 件追加 / メイン代行確認依頼）
- [x] **S6-003** (#46): DB クリア機能（指定日付のデータ削除 + 設定画面 UI） → **dev-1** / Must / M（コミット `c11516a` / TripRepository に deleteTrip / deleteAllTrips / availableDates 追加 / DBClearView.swift 新規 / SettingsView に DB クリア行追加 / RootView に tripRepository 注入 / 単体テスト 4 件追加 / DI カバレッジテスト不要（新規サービスなし）/ ビルド確認: メイン代行依頼）
- [x] **S6-007** (#50): アプリアイコン（全サイズ）+ ローンチスクリーン → **designer + メイン代行** / Must / M（コミット `7b77d28` / 204/204 pass / warning 0 / IconDesignPreview.swift 新規（SwiftUI ベース、jun さんが Xcode Preview から本番 PNG 書き出し可）/ AppIcon-1024.png placeholder（Designer 配色のグラデーション + 簡易ピン、Swift CLI で生成）/ LaunchBackground.colorset 新規 / Info.plist UILaunchScreen 設定 / 副次対応: SettingsView Preview の dead code warning 解消）

---

## 着手順序メモ

### Phase 0（PO/SM 主導 / Dev 着手前）

1. **S6-001** DI 経路カバレッジテスト定型化（po-sm）

### Phase 1（Dev-1 主導 / 構造改善）

1. **S6-002** `AppDependencyContainer` 導入（dev-1 / S6-001 完了後）

### Phase 2（Dev-2 並行開始 / プロダクト機能）

1. **S6-009** QA-S5-003/004 解消（依存なし軽量・ウォームアップ）
2. **S6-004** DB 自動消去（AppSettings 拡張 → DB サービス容量計測 → 自動消去サービス）
3. **S6-005** バッテリー最適化（LocationService 動的精度切替）

### Phase 3（Dev-1 / Dev-2 並行）

- Dev-1: **S6-003** DB クリア機能（S6-002 完了後 / S6-004 AppSettings 拡張コミット後）
- Dev-2: **S6-006** バックグラウンド復帰（S6-005 完了後）

### Phase 4（デザイン取り込み）

1. メインから scrum-designer 起動 → アイコン + ローンチスクリーン素材生成
2. **S6-007** Dev-1 が Designer 成果物を Assets.xcassets に反映

### Phase 5（Sprint 6 末 / 実機検証）

1. メイン代行が `xcodebuild clean build` / `clean test` で warning 0 確認
2. **S6-008**（1 回目 / 2026-05-09 jun さん実施 → ピン化バグ検出 → S6-010 起票）

### Phase 6（実機フィードバック対応 / 2026-05-09 追加）

1. **S6-010** dev-2 が滞留検知の堅牢化を実装
   - B: `RetroactiveStayDetector` 新規 + `LocationService.resumeTrackingAfterRelaunch` から発火
   - A: `StayDetector` の anchor / 開始時刻を UserDefaults に永続化
   - ユニットテスト 8 ケース以上 + DI カバレッジテスト 1 件追加
2. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認
3. **S6-008（再実行）** jun さんが iPhone 16 Pro で再度「喫茶店 1 時間滞在」シナリオを試す
   - ピン履歴に該当滞在のピンが残っていれば S6-010 完了 → Sprint 6 完了 → 個人利用版リリース可能
   - まだ残らない場合は dev-2 に追加調査依頼（Sprint 内で 1 周まで対応 / それでもダメなら Sprint 7 切出）

---

## ビルド状態スタンプ

`.scrum/process/dev-completion-checklist.md` の運用に従い、各チケット Done 時に以下を記入:

| チケット | 担当 | コミット | フル再ビルド warning | メイン代行確認 | 追加テスト数 |
|---|---|---|---|---|---|
| S6-001 | po-sm（メイン代行） | TBD | 0（コード変更はコメント追加のみ） | 確認済 / 173/173 pass | 0（仕組み導入のため） |
| S6-002 | dev-1 | 8853972 | 0（メイン代行確認済） | 確認済 / 176/176 pass | 3（DI 検証ケース） |
| S6-003 | dev-1 | c11516a | 0（メイン代行確認済）| 確認済 / 197/197 pass | 4（単体: deleteTrip cascade / deleteAll / noOp / availableDates） |
| S6-004 | dev-2 | 7029d2f | 0（メイン代行確認済） | 確認済 / 185/185 pass | 6（単体 5 + DI カバレッジ 1） |
| S6-005 | dev-2 | bb7e7c0 | 0（メイン代行確認済） | 確認済 / 193/193 pass | 8（単体 7 + DI 統合 1） |
| S6-006 | dev-2 | 0bce4be | 0（メイン代行確認済） | 依頼中 | 7（単体 6 + DI カバレッジ 1） |
| S6-007 | designer + メイン代行 | 7b77d28 | 0（メイン代行確認済） | 確認済 / 204/204 pass | 0（UI/デザイン変更のみ） |
| S6-008 | po-sm | - | - | jun さん実機（1 回目: 2026-05-09 ピン化バグ検出 → S6-010 起票 / 2 回目: S6-010 完了後に再実行） | - |
| S6-009 | dev-2 | 39dba0e | 0（メイン代行確認済） | 確認済 / 179/179 pass | 3（CSV 失敗時 retryCount 加算） |
| S6-010 | dev-2 | TBD | TBD | 未着手 / 2026-05-09 起票 | 8 件以上想定（B 5 件 + A 3 件 + DI 1 件） |

---

## ステータスサマリ

| 状態 | 件数 |
|---|---|
| Todo | 2（S6-008 / S6-010） |
| In Progress | 0 |
| Done | 8 |
| **Sprint 6 完了** | **8/10** |

> 2026-05-09 更新: 実機検証 1 回目で滞留ピン化のバグを検出。S6-010 を Must で追加し、S6-008 は S6-010 完了後に再実行する流れに変更。

---

## メイン代行修正欄（Dev エージェントの sandbox 制約により Opus メインが代行）

| コミット | 内容 |
|---|---|
| `39dba0e` | `CloudUploadRetryQueueTests.swift` の `test_successAfterCsvFailure_removesEntry_S6_009` で `stubProvider` を `makeQueue` に渡しておらず内部 default が `.failure` を返してしまうテスト DI 漏れを修正（S6-001 で導入した DI カバレッジ運用がテストコード側にも適用されるべきという学び） |
| `7029d2f` | `DatabaseAutoCleanupService.swift` の DB ファイル URL 取得を `ModelContainer.defaultDirectoryURL`（iOS 26 で存在せず）から `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` 経由に変更。`attrs[.size]` の型推論エラーを `attrs[FileAttributeKey.size]` 明示で解消 |
| `7b77d28` | `AppIcon-1024.png` placeholder を Swift CLI（AppKit/CoreGraphics）で生成して配置（Designer は画像生成不可のため）。Designer 配色（深藍 #1A3A5C → 青 #2E7FC0 グラデーション）+ 中央に簡易ピン。jun さんは `IconDesignPreview.swift` から書き出した本番 PNG にいつでも差し替え可能。`SettingsView.swift` の `#Preview` で `return` 文後の `_ = container` が dead code warning を出していた件も同時解消（`return` の前に移動） |

---

## 完了基準（再掲）

- [ ] 全 10 チケット Done（S6-001〜S6-007 / S6-009 完了済 / S6-008 / S6-010 残）
- [ ] スプリントゴール検証条件 7 項目すべて静的に確認可能
- [ ] フル再ビルド warning 0 / error 0
- [ ] ユニットテスト pass 100%（約 210 件想定 / S6-010 で +8 件以上）
- [ ] Sprint 1〜5 のテスト 173 件の回帰なし
- [ ] API キー漏洩スキャン 0 件
- [ ] DI 検証テストが新規サービスに対して必須化されている（S6-001 効果確認）
- [ ] **S6-010 完了**: 滞留検知の堅牢化（B 案 + A 案）が pass
- [ ] **S6-008 再実行**: 実機検証 7 観点すべて jun さん側で OK 判定（特に観点 2「MKLocalSearch / ピン化」）
- [ ] レビュー / レトロ文書を作成
- [ ] ユーザー承認 + git push 承認

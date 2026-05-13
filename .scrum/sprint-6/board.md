# Sprint 6 Board

## Sprint Goal

> **個人利用版として jun さんの iPhone 16 Pro に Xcode から実機インストールでき、CLAUDE.md 記載の全機能（DB クリア / DB 自動消去 / バッテリー最適化を含む）が実機で動作する状態に到達する**

期間: 2026-05-07 開始（最終スプリント）
フェーズ: **development**（jun さん 5 項目回答取得済 2026-05-06）
方針: A 案採用（1-sprint 完結 / 個人利用版リリース）

---

## Todo

- [ ] **S6-008** (#51): 実機検証総合チェック（MKLocalSearch / SLC / バッテリー実測 / バックグラウンド / アイコン / **自宅設定** / **タスクキル後の自宅 → 再出発** / **タブ切替後の記録継続** / **自宅出発直後の記録**） → **po-sm** / Must / M（**S6-011 / S6-012 / S6-013 / S6-014 / S6-015 / S6-016 / S6-017 完了後に再実行**。1 回目の検証で判明した UX バグ 2 件を S6-011 / S6-012 で潰し、2 回目の検証で判明した残バグ 2 件を S6-013 で潰し、3 回目の検証で判明した自宅設定の致命バグを S6-014 で潰し、4 回目（2026-05-11）の検証で判明したタスクキル後の自宅 → 再出発バグを S6-015 で潰し、5 回目（2026-05-12）の検証で判明したタブ切替で記録停止バグを S6-016 で潰し、6 回目（2026-05-12〜13）の検証で判明した SLC 空白ウィンドウバグを S6-017 で潰した上で、既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発 + タブ切替後の記録継続 + **自宅出発直後の記録** を最終判定する。jun さんは買い物検証 + 自宅設定確認 + 履歴ピンタップ確認 + タスクキル後再出発確認 + タブ切替後の記録継続確認 + **自宅出発直後の記録確認**（徒歩 300m のショッピングモール / 車で出発直後の数百メートル）を順次実施）

## In Progress

（なし）

## Done

- [x] **S6-017** (ffd432b): 自宅 → 出発時の SLC 空白ウィンドウ修正（atHome 中も低精度通常 GPS 維持） → **dev-2** / Must / S（コミット `ffd432b` / **リリースブロッカー** / 2026-05-12〜13 jun さん実機検証 6 回目で発覚 / 修正: SLC 廃止 + `desiredAccuracy=kCLLocationAccuracyHundredMeters` + `distanceFilter=100m` で通常 GPS 維持 + `.atHome → .away` 遷移時に `desiredAccuracy=Best / distanceFilter=kCLDistanceFilterNone` に復元 / `SignificantLocationChangesTests` 2 件書き換え（SLC 仕様変更のため）+ `SLCSpaceWindowFixTests.swift` 新規 5 件追加 / メイン代行ビルド確認依頼）
- [x] **S6-016** (2abc6b5): タブ切替で wasTracking が false になり記録が止まる致命バグの修正 → **dev-2** / Must / XS（コミット `2abc6b5` / **リリースブロッカー** / 根本原因: `MapView.swift` の `.onDisappear` で `stopUpdatingLocation()` を呼んでいたため、タブ切替のたびに `wasTracking=false` にリセットされ S6-015 の SLC 起床復帰ガードが機能しなかった / 修正: `.onDisappear` から `stopUpdatingLocation()` 呼び出しを削除しコメントで理由を明記 / 新規テスト 3 件 `MapViewTabSwitchTests.swift` 追加（常時同期でタブ切替後も `wasTracking=true` 維持 / トリガーモードで `stopUpdatingLocation` 呼び出すと `wasTracking=false` になる既存挙動維持 / 常時同期 `.onAppear` で `wasTracking=true` になる）/ メイン代行ビルド確認依頼）
- [x] **S6-015** (0e7c082): タスクキル後の自宅 → 再出発で記録が再開されないバグの修正 → **dev-2** / Must / S（コミット `0e7c082` / バグ1: `handleHomeStateTransition` の `previous == .atHome` 条件を廃止し `current != .atHome` ＋ `wasTracking=true` ガードに変更（.unknown → .away 遷移でも GPS 再開を保証）/ バグ2: `didUpdateLocations` 冒頭に `needsResume = !isUpdating && wasTracking` フラグを追加し `handleNewLocations` 後に `resumeTrackingAfterRelaunch` を呼ぶ保険経路を追加 / 新規ユニットテスト 4 件（LocationServiceTaskKillResumeTests.swift 新規）/ メイン代行ビルド確認依頼）
- [x] **S6-014** (TBD): 自宅登録画面で保存値が破棄される問題の修正 → **po-sm（メイン代行 / 緊急対応）** / Must / S（コミット `5bc9145` / 実機検証 3 回目で発覚した致命バグ 2 件（自宅ピン位置修正→保存後に元に戻る / 自宅削除→再登録すると東京駅で固定）を修正 / 根本原因: `HomeRegistrationView` の `@State` を `init` 内で `State(initialValue: settings.homeLocation)` で外部値から初期化していたため、save() による親 SettingsView 再描画で initialValue が再適用される SwiftUI 既知アンチパターン / 修正: `@State` をリテラル既定値で宣言（`selectedCoordinate=defaultCenter` / `radius=defaultHomeRadiusMeters` / `selectedAddress=nil`）+ `init` からの State 初期化を全廃 + `.onAppear` 内で `didLoadFromSettings` フラグで初回ガード付き復元 / 実コード変更 22+/-8 行 / 検証: xcodebuild clean test 242/242 pass / warning 0 / 実機検証は jun さん依頼中）
- [x] **S6-013** (TBD): 履歴画面のピンタップ詳細表示 + placeName 住所混入修正 → **dev-1** / Must / S（コミット `25bd2c4` / A: `HistoryDetailMapContainer.Coordinator` を `NSObject` + `@preconcurrency GMSMapViewDelegate` + `@MainActor` に拡張 / `makeUIView` で `mapView.delegate = context.coordinator` 設定 / `marker.userData` を `RestoredPin` に変更 / `mapView(_:didTap marker:)` + `handleMarkerTap(pin:)` 実装 / `HistoryDetailView` に `selectedPin` State + `.sheet(item:)` 追加 / B: `LocationService.swift` の `?? candidate.address` fallback 削除（メイン代行実装済を取り込み）/ `PlaceLookupServiceTests` のアサーション更新 / ユニットテスト 4 件追加（T-1 × 2 + T-2 × 3）/ メイン代行ビルド確認依頼）
- [x] **S6-011** (TBD): ピンタップ詳細表示 + 外部マップ起動導線 → **dev-1** / Must / M（コミット `df3d076` / `MapView.Coordinator` に `mapView(_:didTap marker:)` + `handleMarkerTap(marker:)` 実装 / `marker.userData = pin` 設定 / `PinDetailModel.swift` 新規（URL 生成 / 文字列整形）/ `PinDetailView.swift` 新規（SwiftUI シート）/ `Info.plist` に `LSApplicationQueriesSchemes: comgooglemaps` 追加 / `RestoredPin` に `Identifiable` + `address` 追加 / ユニットテスト 10 件 / メイン代行ビルド確認依頼）
- [x] **S6-012** (TBD): StayDetector 半径を 30m → 100m に拡大（大型店対応） → **dev-2** / Must / S（コミット `9d0676e` / `StayDetectionConfig.radiusMeters` デフォルト 30→100（1 行変更）/ RetroactiveStayDetector 共有 config 自動追従 + コメント追加 / 冪等性ガード 100m 追従（config 共有）/ DI テストアサーション更新 / 100m 境界値テスト 4 件追加 / メイン代行ビルド確認依頼）
- [x] **S6-010** (TBD): 滞留検知の堅牢化（B: RoutePoint 後追い検知 + A: StayDetector 状態永続化） → **dev-2** / Must / L（コミット `5d6ef29` + メイン代行修正 `1dc0386` / RetroactiveStayDetector 新規 + StayDetector UserDefaults 永続化 + TripRepository 拡張 + LocationService DI + RootView 発火 / テスト 13 件 / メイン代行確認済）
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

1. **S6-010** dev-2 が滞留検知の堅牢化を実装（**Done**: `5d6ef29` + メイン代行修正 `1dc0386`）
   - B: `RetroactiveStayDetector` 新規 + `LocationService.resumeTrackingAfterRelaunch` から発火
   - A: `StayDetector` の anchor / 開始時刻を UserDefaults に永続化
   - ユニットテスト 13 件 + DI カバレッジテスト 1 件
2. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認（**Done**）
3. **S6-008（中間判定 / 2026-05-09 夕方）**: jun さんが実機で再検証 → 滞留ピンは記録されたが UX バグ 2 件検出 → S6-011 / S6-012 起票

### Phase 7（実機フィードバック対応 第 2 ラウンド / 2026-05-09 夕方追加）

1. **S6-011** dev-1 が `MapView.Coordinator` にピンタップ → 詳細シート → Apple/Google Maps 起動導線を実装（並行可）
2. **S6-012** dev-2 が `StayDetectionConfig.radiusMeters` のデフォルトを 30 → 100 に拡大（並行可 / S6-011 とファイル競合なし）
3. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認
4. **S6-013（実機検証 2 回目フィードバック対応 / 2026-05-09 21:30 追加）** dev-1 が以下を 1 コミットで実装:
   - A: `HistoryDetailMapContainer.Coordinator` を `GMSMapViewDelegate` 準拠（`@preconcurrency` 必須）+ didTap で既存 `PinDetailView` シート表示
   - B: `LocationService.swift:739` の `pin.placeName = candidate.name ?? candidate.address` を `?? candidate.address` 削除（**メイン代行が実装済 / コミット未** → S6-013 のコミットに含める）
   - ユニットテスト 2 件以上追加 / 既存 237 件 pass / warning 0
   - **S6-008 の前に実施**
5. **S6-008（最終判定）** jun さんが iPhone 16 Pro で再々検証
   - 観点 2「MKLocalSearch / ピン化」: 4 店舗滞在 → 4 件ピン化 + 地図タブ・履歴タブ両方でピンタップ詳細表示 + 店舗情報が見える（住所混入なし）
   - 全 7 観点 OK → Sprint 6 完了 → 個人利用版リリース可能
   - 一部 NG → Sprint 6 完了後の追加コミットで対応 or Sprint 7 切出（jun さんと合意）

### Phase 8（実機フィードバック対応 第 3 ラウンド / 2026-05-09 22:30 追加）

1. **S6-014** メイン代行が `HomeRegistrationView.swift` の `@State` 初期化アンチパターンを修正（**Done**: `5bc9145`）
   - `@State` をリテラル既定値で宣言（`selectedCoordinate` / `radius` / `selectedAddress`）
   - `init` からの State 初期化を全廃
   - `.onAppear` で `didLoadFromSettings` フラグ付き復元
   - 22+/-8 行 / 242/242 pass / warning 0 / 緊急対応のため po-sm 経由ではなくメイン代行直
2. po-sm が S6-014 を遡及起票 + board.md / 完了基準を 13 → 14 チケットに更新（**Done**: 本コミット）
3. **S6-008（最終判定 / 観点拡張）** jun さんが iPhone 16 Pro で再検証
   - 既存 7 観点 + **観点 8: 自宅設定の保存反映**（自宅ピン位置修正→保存後の値が反映 / 自宅削除→再登録で正しい座標が保存）
   - 順次実施: 買い物検証 → 自宅設定確認 → 履歴ピンタップ確認
   - 全観点 OK → Sprint 6 完了 → 個人利用版リリース可能
   - 一部 NG → Sprint 6 完了後の追加コミットで対応 or Sprint 7 切出（jun さんと合意）

### Phase 9（実機フィードバック対応 第 4 ラウンド / 2026-05-11 追加）

1. **S6-015** dev-2 が `LocationService` のバックグラウンド復帰経路を修正（**Done**: `0e7c082`）
   - A: `handleHomeStateTransition` の `previous == .atHome` 条件を廃止し `current != .atHome` ＋ `wasTracking=true` ガードに変更（タスクキル後に `lastHomeState` がメモリから消えても `.unknown → .away` 遷移で `startUpdatingLocation` を呼ぶ）
   - B: `didUpdateLocations` 冒頭で `needsResume = !isUpdating && wasTracking` フラグを設定し、`handleNewLocations` 後に `resumeTrackingAfterRelaunch()` を呼ぶ保険経路を追加（scenePhase 非依存）
   - C: `LocationServiceTaskKillResumeTests.swift` 新規 / 計 4 件のユニットテスト追加
2. po-sm が S6-015 を起票 + 技術ノート `.scrum/notes/slc-wake-tracking-resume.md` 追加 + board.md / 完了基準を 14 → 15 チケットに更新（**Done**: 本コミット）
3. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認（**Done**: 246/246 pass）
4. **S6-008（観点拡張）** は Phase 10 着手後に再度予定変更（S6-016 完了後に最終判定へ）

### Phase 10（実機フィードバック対応 第 5 ラウンド / 2026-05-12 追加）

1. **S6-016** dev-2 が `MapView.swift` の `.onDisappear` から `stopUpdatingLocation()` を削除（**Done**: `2abc6b5`）
   - 根本原因: `.onDisappear` の `stopUpdatingLocation()` が `wasTracking=false` にリセット → タブ切替で `wasTracking` が壊れ、S6-015 で実装した SLC 起床経路（`wasTracking=true` ガード）が発火しない致命バグ
   - 修正: `.onDisappear` の 1 ブロック削除（理由コメント付き）
   - 維持: 常時同期の `.onAppear` 自動 start / トリガーモードの `RecordingToggleButton` 経由停止 / 自宅滞在中の自動停止経路（`handleHomeStateTransition` の `.atHome` 経路は `stopUpdatingLocation` を呼ばないので影響なし）
   - 新規ユニットテスト 3 件（`MapViewTabSwitchTests.swift` 新規 / 常時同期でタブ切替後も `wasTracking=true` 維持 / トリガーモードで `stopUpdatingLocation` 呼び出すと `wasTracking=false` になる既存挙動維持 / 常時同期 `.onAppear` で `wasTracking=true` になる）
   - レビュー観点: バッテリー影響（S6-005 で吸収）/ `wasTracking` 他経路への波及（resumeTrackingAfterRelaunch / startTrackingFromSLC / handleHomeStateTransition / didUpdateLocations の保険経路）/ トリガーモードの挙動破壊なし / 既存 LocationServiceTests / MapViewTests への影響
2. po-sm が S6-016 を起票 + 技術ノート `.scrum/notes/swiftui-ondisappear-pitfall.md` 追加 + board.md / 完了基準を 15 → 16 チケットに更新（**Done**: 本コミット）
3. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認（**依頼中** / dev-2 コミット `2abc6b5` 後）
4. **S6-008（最終判定 / 観点拡張）** は Phase 11 着手後に再度予定変更（S6-017 完了後に最終判定へ）

### Phase 11（実機フィードバック対応 第 6 ラウンド / 2026-05-12〜13 追加）

1. **S6-017** dev-2 が `LocationService.startSignificantChangesIfHome` の SLC 空白ウィンドウを修正（**In Progress**: dev-2 並行作業中 / コミット TBD）
   - 根本原因: `LocationService.swift:274-285` の `startSignificantChangesIfHome` が atHome 中に通常 GPS を完全停止し SLC のみに切替えていた。SLC は「500m〜1km 以上動かないと配信されない」OS 仕様のため、**自宅判定半径 70m と SLC 配信距離 500m の差分（70m〜500m）が「SLC 空白ウィンドウ」になり、その範囲の移動はまったく検出できない**。jun さんの 2026-05-12〜13 実機検証で「徒歩 300m のショッピングモールがまったく記録されない」「車で出発直後の 500m が記録されない」事例として発生
   - 修正方針（jun さん承認済 / 方針 A）: SLC 開始呼び出しを削除 + atHome 中も通常 GPS を維持（`desiredAccuracy=kCLLocationAccuracyHundredMeters` + `distanceFilter=100m`）+ `.atHome → .away` 遷移で `BatteryAdaptiveLocationPolicy` 経由で通常精度復帰
   - 維持: 家の中で動かない時は `distanceFilter=100m` が配信を抑制 → 実質バッテリー消費ゼロ / トリガーモード経路 / 自宅滞在中の自動停止挙動（精度低下による実質停止）
   - 新規ユニットテスト 3 件以上（atHome モードの精度・filter 設定 / `.atHome → .away` 遷移時の精度復元 / 70m 圏外で `.atHome → .away` 検出）
   - レビュー観点: SLC を完全廃止するか保険として残すか / `BatteryAdaptiveLocationPolicy`（S6-005）との整合 / `isMonitoringSignificantChanges` フラグの扱い / S6-006 / S6-015 / S6-016 テストへの回帰影響 / バッテリー消費の理論値見積もり
2. po-sm が S6-017 を起票 + 技術ノート `.scrum/notes/slc-vs-low-power-gps.md` 追加 + board.md / 完了基準を 16 → 17 チケットに更新（**Done**: 本コミット）
3. メイン代行が `xcodebuild clean test` で warning 0 / 全 pass 確認（**未着手** / dev-2 コミット後）
4. **S6-008（最終判定 / 観点拡張）** jun さんが iPhone 16 Pro で次回外出時に再検証
   - 既存 7 観点 + 観点 8（自宅設定の保存反映）+ 観点 9（タスクキル後の自宅 → 再出発）+ 観点 10（タブ切替後の記録継続）+ **観点 11: 自宅出発直後の記録**（徒歩 300m のショッピングモール往復 / 車で出発直後の数百メートル / 自宅滞在中のバッテリー消費）
   - 順次実施: 買い物検証 → 自宅設定確認 → 履歴ピンタップ確認 → タスクキル後再出発確認 → タブ切替後の記録継続確認 → **自宅出発直後の記録確認**
   - 全観点 OK → Sprint 6 完了 → 個人利用版リリース可能
   - 一部 NG → Sprint 6 完了後の追加コミットで対応 or Sprint 7 切出（jun さんと合意）

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
| S6-010 | dev-2 | 5d6ef29 + メイン代行修正 1dc0386 | 0（メイン代行確認済） | 確認済 / 全 pass | 13（B 5+境界値 2+haversine 2+A 3+DI 1） |
| S6-011 | dev-1 | df3d076 | TBD（メイン代行確認依頼） | 未確認 | 10（T-1: Identifiable/userData 2 件 / T-2: Apple Maps URL 2 件 / T-3: Google Maps URL 2 件 / T-4: 表示文字列 4 件） |
| S6-012 | dev-2 | 9d0676e | TBD（メイン代行確認依頼） | 未確認 | 4（100m 境界値: StayDetector 2 件 + RetroactiveStayDetector 2 件）+ DI テスト更新 1 件 |
| S6-013 | dev-1 | 25bd2c4 | TBD（メイン代行確認依頼） | 未確認 | 4 件追加（T-1: handleMarkerTap → callback 呼び出し 2 件 / T-2: RestoredPin 変換 3 件）+ 既存 PlaceLookupServiceTests 1 件更新（メイン代行作業済） |
| S6-014 | po-sm（メイン代行 / 緊急対応） | 5bc9145 | 0（メイン代行確認済） | 確認済 / 242/242 pass | 0（既存テスト回帰なしを確認 / SwiftUI `@State` の挙動修正のため新規ユニットテスト追加は対象外 / 実機検証で確認） |
| S6-015 | dev-2 | 0e7c082 | 0（メイン代行確認済 / clean test） | 確認済 / 246/246 pass | 4（`LocationServiceTaskKillResumeTests.swift` 新規 / `.unknown → .away` 遷移で `startUpdatingLocation` 呼び出し / `didUpdateLocations` 経路で `resumeTrackingAfterRelaunch` 呼び出し / `wasTracking=false` のときガードで発火しない / handleHomeStateTransition の `.atHome` 経路保護） |
| S6-016 | dev-2 | 2abc6b5 | TBD（メイン代行確認依頼） | 未確認 | 3（`MapViewTabSwitchTests.swift` 新規 / 常時同期でタブ切替後も `wasTracking=true` 維持 / トリガーモードで `stopUpdatingLocation` 呼び出すと `wasTracking=false` になる既存挙動維持 / 常時同期 `.onAppear` で `wasTracking=true` になる） |
| S6-017 | dev-2 | TBD（dev-2 並行作業中） | TBD | 未確認 | 3 件以上見込み（atHome モードで `kCLLocationAccuracyHundredMeters` + `distanceFilter=100m` + `isUpdating=true` 設定確認 / `.atHome → .away` 遷移で `BatteryAdaptiveLocationPolicy` 経由の精度復帰 / 70m 圏外で `.atHome → .away` 検出） |

---

## ステータスサマリ

| 状態 | 件数 |
|---|---|
| Todo | 1（S6-008） |
| In Progress | 1（S6-017 / dev-2 並行作業中） |
| Done | 14（S6-011 / S6-012 / S6-013 / S6-014 / S6-015 / S6-016 含む） |
| **Sprint 6 完了** | **14/17**（残: S6-017 完了 + S6-008 実機検証総合 + メイン代行による S6-016 / S6-017 ビルド確認） |

> 2026-05-09 更新（朝）: 実機検証 1 回目で滞留ピン化のバグを検出。S6-010 を Must で追加し、S6-008 は S6-010 完了後に再実行する流れに変更。
>
> 2026-05-09 更新（夕方）: S6-010 完了（コミット `5d6ef29` + メイン代行修正 `1dc0386`）。jun さんによる実機再検証（中間判定）で UX バグ 2 件追加検出:
> - **4 店舗で各 20 分滞在 → ピン 1 件のみ**（StayDetector 半径 30m が大型店内回遊で分断 → **S6-012**）
> - **ピンに店舗情報が出ない / タップしても何も起こらない**（`MapView.Coordinator` に `didTap marker` 未実装 → **S6-011**）
>
> jun さん判断: S6-011 起票 OK / 半径は 100m に拡大 / 設定可変化は不要。8/10 → **8/12** に拡張。S6-008 は **S6-011 / S6-012 完了後** に再実行する。
>
> 2026-05-09 更新（21:30 頃）: S6-011 / S6-012 完了後の jun さん実機再検証 2 回目で残バグ 2 件検出 → **S6-013** を Must で追加:
> - **履歴タブの地図でピンタップしても詳細シートが出ない**（S6-011 は地図タブの `MapView` のみ対応 / 履歴タブの `HistoryDetailMapContainer` は未対応 → **S6-013 A**）
> - **PinRecord.placeName に住所が混入**（`LocationService.swift:739` の `?? candidate.address` fallback が原因 → **S6-013 B / メイン代行が手元で修正済 / コミット未**）
>
> Sprint 6 スコープを **11/13** に拡張。S6-008 は **S6-013 完了後** に再実行する。
>
> 2026-05-09 更新（22:30 頃）: S6-013 完了後、jun さんの実機検証 3 回目で **自宅設定の致命バグ 2 件** を検出 → **S6-014** を Must で遡及起票（メイン代行が緊急対応で実装済 / コミット `5bc9145`）:
> - **自宅でピン位置を修正して保存しても、保存前の値に戻る**
> - **自宅を削除して再登録すると、地図上では修正できるが保存すると東京駅で固定される**
>
> 根本原因: `HomeRegistrationView` の `@State` を `init` 内で `State(initialValue: settings.homeLocation)` で外部値から初期化していたため、`save()` による親 SettingsView 再描画で initialValue が再適用される SwiftUI 既知アンチパターン。修正は `@State` をリテラル既定値で宣言し、設定値の復元は `.onAppear` で `didLoadFromSettings` ガード付きで実行する形に変更（22+/-8 行）。242/242 pass / warning 0 確認済。
>
> Sprint 6 スコープを **12/14** に拡張。S6-008 最終判定では **既存 7 観点 + 自宅設定の保存反映** を確認する流れ。再発防止のため SwiftUI `@State` init アンチパターンの技術メモを `.scrum/notes/swiftui-state-init-pitfall.md` に追加。
>
> 2026-05-11 更新: jun さんの 1 日通し実機検証で **タスクキル後の自宅 → 再出発で記録が再開されない致命バグ** を検出 → **S6-015** を Must / リリースブロッカーで起票:
> - 朝の出発（自宅 → 外出先）は記録された
> - 帰宅後にタスクキルした状態で再度外出 → **約 40km 移動が完全に拾われなかった**
>
> 根本原因（実装漏れ 2 箇所の複合）:
> 1. `LocationService.handleHomeStateTransition`（line 514-527）の `previous == .atHome` 条件が、タスクキル後にメモリから消えた `lastHomeState == .unknown` 経路を救えていない（SLC で起床して自宅外と判定されても通常 GPS が再開されない）
> 2. `resumeTrackingAfterRelaunch()` が `RootView.onChange(scenePhase)` でしか呼ばれず、バックグラウンド SLC 起床時は scenePhase が `.active` にならないため、保険ロジック側でも記録復元が走らない
>
> 修正方針: handleHomeStateTransition の条件緩和（`.unknown → .away` も通常 GPS 再開）+ `didUpdateLocations` 冒頭で SLC 起床経路を検出して `resumeTrackingAfterRelaunch()` 発火 + ユニットテスト 2 件以上追加。dev-2 が並行実装し、コミット `0e7c082` で完了（バグ1: `previous == .atHome` 条件を廃止し `current != .atHome` ＋ `wasTracking=true` ガード / バグ2: `didUpdateLocations` 冒頭に `needsResume = !isUpdating && wasTracking` フラグ + `handleNewLocations` 後に `resumeTrackingAfterRelaunch` 呼び出し / 新規ユニットテスト 4 件 `LocationServiceTaskKillResumeTests.swift`）。
>
> Sprint 6 スコープを **13/15** に確定（残: S6-008 実機検証総合 + メイン代行による S6-015 ビルド確認）。S6-008 最終判定では **既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発** を確認する流れ。再発防止のため SLC 起床経路の技術メモを `.scrum/notes/slc-wake-tracking-resume.md` に追加。
>
> 2026-05-12 更新: jun さんの実機検証 5 回目で **タブ切替後にタスクキルすると記録が止まる致命バグ** を検出 → **S6-016** を Must / リリースブロッカーで起票:
> - 常時同期 ON で 10km 運転、アプリはタスクキルされたまま運転中一度も起動していない
> - 帰宅後アプリを開くと **移動経路もピンも一切記録されていなかった**
> - Console.app 実機ログで **iOS 側は GPSLogger に位置情報を正常送信していたことを確認** → アプリ側の起動 / GPS 再開経路にバグが残っていることが確定
>
> 根本原因（S6-015 の前提を破壊していた経路）:
> 1. `MapView.swift:108-110` の `.onDisappear` で `stopUpdatingLocation()` を呼んでいた
> 2. `stopUpdatingLocation()` 内部で `wasTracking=false` にリセットされる（`LocationService.swift:228`）
> 3. タブ切替（地図 → 設定 / 履歴）で `.onDisappear` 発火 → `wasTracking=false` で永続化
> 4. その状態でタスクキル → 翌日 SLC 起床しても、S6-015 の `wasTracking=true` ガード（`handleHomeStateTransition` / `didUpdateLocations` 冒頭の保険経路）が **false で発火せず、記録再開しない**
>
> S6-015 の wasTracking ガード自体は設計として正しいが、その値を破壊する経路（`.onDisappear` 副作用）を残していたため、ガードの効力が事実上ゼロになっていた。
>
> 修正方針: `MapView.swift` の `.onDisappear` の `stopUpdatingLocation()` を削除（数行）+ 新規ユニットテスト 3 件追加。dev-2 が並行実装し、コミット `2abc6b5` で完了。常時同期の `.onAppear` 自動 start は維持 / トリガーモードは `RecordingToggleButton` 経由でのみ停止する設計に統一 / バッテリー懸念は S6-005 の `BatteryAdaptiveLocationPolicy` で吸収。新規テストは `MapViewTabSwitchTests.swift` 新規（タブ切替後も `wasTracking=true` 維持 / トリガーモードでの既存挙動維持 / 常時同期 `.onAppear` で `wasTracking=true` になる）。
>
> Sprint 6 スコープを **14/16** に確定（残: S6-008 実機検証総合 + メイン代行による S6-016 ビルド確認）。S6-008 最終判定では **既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発 + タブ切替後の記録継続** を確認する流れ。再発防止のため SwiftUI `.onDisappear` の落とし穴（タブ切替でも発火する仕様 / 長寿命サービスの制御に使うべきでない）の技術メモを `.scrum/notes/swiftui-ondisappear-pitfall.md` に追加。
>
> 2026-05-12〜13 更新: jun さんの実機検証 6 回目で **自宅 → 出発時に最初の数百メートルが記録されない致命バグ**（SLC 空白ウィンドウ）を検出 → **S6-017** を Must / リリースブロッカーで起票:
> - 自宅から **徒歩 300m のショッピングモール** に歩いたが、まったく記録されなかった
> - 車で出発した時も、**家を出てから 500m 分くらいは記録されない**
> - 自宅判定半径は **70m**（jun さんのデフォルト 100m より狭い運用）
>
> 根本原因: `LocationService.swift:274-285` の `startSignificantChangesIfHome`（S3-006 で実装）が、atHome 中に通常 GPS を完全停止し SLC のみに切替えていた。Apple の SLC（Significant Location Changes）は **「500m〜1km 以上動かないと配信されない」OS 仕様**のため、**自宅判定半径 70m と SLC 配信距離 500m の差分（70m〜500m）が「SLC 空白ウィンドウ」になり、その範囲の移動はまったく検出できない**。位置情報が来ない → `lastHomeState` は `.atHome` のまま → `handleHomeStateTransition` も発火しない → 通常 GPS も再開されない、という連鎖でユーザーの目的地（家から徒歩圏 / 車で出発直後）が永久に記録されない致命バグだった。
>
> 修正方針（jun さん承認済 / 方針 A）: SLC 開始呼び出しを削除 + atHome 中も通常 GPS を維持（`desiredAccuracy=kCLLocationAccuracyHundredMeters` + `distanceFilter=100m`）+ `.atHome → .away` 遷移で `BatteryAdaptiveLocationPolicy` 経由で通常精度復帰。家の中で動かない時は `distanceFilter=100m` が配信を抑制 → 実質バッテリー消費ゼロ。家を出た瞬間（70m 外）に `didUpdateLocations` が発火 → `.atHome → .away` 検出 → 通常精度に復帰、という設計に切替える。dev-2 が並行実装中（コミット TBD / コード変更 10〜20 行 + 新規ユニットテスト 3 件以上）。
>
> Sprint 6 スコープを **14/17** に確定（残: S6-017 完了 + S6-008 実機検証総合 + メイン代行による S6-016 / S6-017 ビルド確認）。S6-008 最終判定では **既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発 + タブ切替後の記録継続 + 自宅出発直後の記録** を確認する流れ。再発防止のため SLC vs 低精度通常 GPS の選択肢比較・採用判断の技術メモを `.scrum/notes/slc-vs-low-power-gps.md` に追加。

---

## メイン代行修正欄（Dev エージェントの sandbox 制約により Opus メインが代行）

| コミット | 内容 |
|---|---|
| `39dba0e` | `CloudUploadRetryQueueTests.swift` の `test_successAfterCsvFailure_removesEntry_S6_009` で `stubProvider` を `makeQueue` に渡しておらず内部 default が `.failure` を返してしまうテスト DI 漏れを修正（S6-001 で導入した DI カバレッジ運用がテストコード側にも適用されるべきという学び） |
| `7029d2f` | `DatabaseAutoCleanupService.swift` の DB ファイル URL 取得を `ModelContainer.defaultDirectoryURL`（iOS 26 で存在せず）から `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` 経由に変更。`attrs[.size]` の型推論エラーを `attrs[FileAttributeKey.size]` 明示で解消 |
| `7b77d28` | `AppIcon-1024.png` placeholder を Swift CLI（AppKit/CoreGraphics）で生成して配置（Designer は画像生成不可のため）。Designer 配色（深藍 #1A3A5C → 青 #2E7FC0 グラデーション）+ 中央に簡易ピン。jun さんは `IconDesignPreview.swift` から書き出した本番 PNG にいつでも差し替え可能。`SettingsView.swift` の `#Preview` で `return` 文後の `_ = container` が dead code warning を出していた件も同時解消（`return` の前に移動） |
| `5bc9145` | **S6-014 緊急対応**: `HomeRegistrationView.swift` の `@State` を `init` 内で `State(initialValue: settings.homeLocation)` で外部値から初期化していたため、`save()` の親 `SettingsView` 再描画 → sheet content closure 経由の init 再評価で initialValue が再適用され、ユーザー入力値（ピン位置 / 半径 / 住所）が「保存前の値」または「東京駅の defaultCenter」に戻ってしまう SwiftUI 既知アンチパターン。修正: `@State` をリテラル既定値で宣言（`selectedCoordinate=defaultCenter` / `radius=defaultHomeRadiusMeters` / `selectedAddress=nil`）、`init` からの State 初期化を全廃、`.onAppear` 内で `didLoadFromSettings` フラグで初回ガード付きで settings から復元。実コード変更 22+/-8 行 / `xcodebuild clean test` 242/242 pass / warning 0 / 同類の罠を Sprint 7 以降の他画面で踏まないよう `.scrum/notes/swiftui-state-init-pitfall.md` に技術メモを残した |

---

## 完了基準（再掲）

- [ ] 全 17 チケット Done（S6-001〜S6-007 / S6-009〜S6-016 完了済 / **S6-008 / S6-017 残**）
- [ ] スプリントゴール検証条件 7 項目すべて静的に確認可能
- [x] フル再ビルド warning 0 / error 0（S6-015 含む確認済 / clean test / **S6-016 / S6-017 はメイン代行による再確認待ち**）
- [x] ユニットテスト pass 100%（246/246 pass / S6-015 で新規 4 件追加 / **S6-016 で 3 件追加 → 249 件見込み / S6-017 で 3 件以上追加 → 252 件以上見込み / メイン代行確認待ち**）
- [ ] Sprint 1〜5 のテスト 173 件の回帰なし
- [ ] API キー漏洩スキャン 0 件
- [ ] DI 検証テストが新規サービスに対して必須化されている（S6-001 効果確認）
- [x] **S6-010 完了**: 滞留検知の堅牢化（B 案 + A 案）が pass
- [x] **S6-011 完了**: ピンタップ詳細表示 + 外部マップ起動導線（実機検証 1 回目フィードバック対応 / 地図タブ）
- [x] **S6-012 完了**: StayDetector 半径 30m → 100m 拡大（実機検証 1 回目フィードバック対応 / jun さん「大型店優先」判断）
- [x] **S6-013 完了**: 履歴画面のピンタップ詳細表示 + placeName 住所混入修正（実機検証 2 回目フィードバック対応）
- [x] **S6-014 完了**: 自宅登録画面で保存値が破棄される問題の修正（実機検証 3 回目フィードバック対応 / メイン代行緊急対応 / `5bc9145`）
- [x] **S6-015 完了**: タスクキル後の自宅 → 再出発で記録が再開されないバグの修正（実機検証 4 回目フィードバック対応 / 2026-05-11 / dev-2 / `0e7c082` / リリースブロッカー）
- [x] **S6-016 完了**: タブ切替で `wasTracking` が false になり記録が止まる致命バグの修正（実機検証 5 回目フィードバック対応 / 2026-05-12 / dev-2 / `2abc6b5` / リリースブロッカー / S6-015 の前提を破壊していた経路の修正 / 新規テスト 3 件 `MapViewTabSwitchTests.swift`）
- [ ] **S6-017 完了**: 自宅 → 出発時の SLC 空白ウィンドウ修正（atHome 中も低精度通常 GPS 維持）（実機検証 6 回目フィードバック対応 / 2026-05-12〜13 / dev-2 / コミット TBD / リリースブロッカー / SLC の 500m〜1km 配信距離制約により自宅 70m〜500m が空白ウィンドウになっていた致命バグの修正 / 新規テスト 3 件以上 / 技術ノート `.scrum/notes/slc-vs-low-power-gps.md`）
- [ ] **S6-008 再実行（最終）**: 実機検証 7 観点 + 自宅設定の保存反映 + タスクキル後再出発 + タブ切替後の記録継続 + **自宅出発直後の記録** すべて jun さん側で OK 判定（特に観点 2「MKLocalSearch / ピン化」: 4 店舗 → 4 ピン + 地図タブ・履歴タブ両方で詳細シート確認 + 住所混入なし、加えて自宅ピン位置修正→保存後の値が反映 / 自宅削除→再登録で正しい座標が保存、加えて朝出発 → 帰宅 → タスクキル → 再出発で記録が再開される、加えて地図 → 設定 → 履歴 → 地図 タブ切替後にタスクキル → 翌日運転で記録される、加えて **自宅から徒歩 300m のショッピングモール往復が記録される / 車で出発直後の数百メートルが記録される / 自宅滞在中のバッテリー消費が許容範囲**）
- [ ] レビュー / レトロ文書を作成
- [ ] ユーザー承認 + git push 承認

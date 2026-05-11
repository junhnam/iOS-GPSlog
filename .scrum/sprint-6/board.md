# Sprint 6 Board

## Sprint Goal

> **個人利用版として jun さんの iPhone 16 Pro に Xcode から実機インストールでき、CLAUDE.md 記載の全機能（DB クリア / DB 自動消去 / バッテリー最適化を含む）が実機で動作する状態に到達する**

期間: 2026-05-07 開始（最終スプリント）
フェーズ: **development**（jun さん 5 項目回答取得済 2026-05-06）
方針: A 案採用（1-sprint 完結 / 個人利用版リリース）

---

## Todo

- [ ] **S6-015** (TBD): タスクキル後の自宅 → 再出発で記録が再開されないバグの修正 → **dev-2** / Must / S（**リリースブロッカー** / 2026-05-11 jun さん実機検証で発覚 / 朝の出発は記録されたが帰宅後タスクキル → 再出発 40km が完全に拾われなかった / 根本原因: `LocationService.handleHomeStateTransition`（line 514-527）の `previous == .atHome` 条件がタスクキル後の `lastHomeState == .unknown` 経路を拾えない + `resumeTrackingAfterRelaunch()` が `RootView.onChange(scenePhase)` でしか呼ばれず SLC 起床時に保険ロジックが効かない、の 2 点複合 / dev-2 が並行実装中（チケット文書化は po-sm が本コミットで完了）/ 受け入れ条件: 既存 242 件 pass + 新規ユニットテスト 2 件（`.unknown → .away` 遷移で `startUpdatingLocation` 呼び出し / `didUpdateLocations` 経路で `resumeTrackingAfterRelaunch` 呼び出し）/ 実機検証は S6-008 で同時実施）
- [ ] **S6-008** (#51): 実機検証総合チェック（MKLocalSearch / SLC / バッテリー実測 / バックグラウンド / アイコン / **自宅設定** / **タスクキル後の自宅 → 再出発**） → **po-sm** / Must / M（**S6-011 / S6-012 / S6-013 / S6-014 / S6-015 完了後に再実行**。1 回目の検証で判明した UX バグ 2 件を S6-011 / S6-012 で潰し、2 回目の検証で判明した残バグ 2 件を S6-013 で潰し、3 回目の検証で判明した自宅設定の致命バグを S6-014 で潰し、4 回目（2026-05-11）の検証で判明したタスクキル後の自宅 → 再出発バグを S6-015 で潰した上で、既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発 を最終判定する。jun さんは買い物検証 + 自宅設定確認 + 履歴ピンタップ確認 + タスクキル後再出発確認 を順次実施）

## In Progress

- [ ] **S6-015** dev-2 が `LocationService` の SLC / 自宅判定経路を実装中（チケット文書化 + 技術ノートは po-sm が本コミットで完了。コミットハッシュ確定後に Done 行へ移動）

## Done

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

1. **S6-015** dev-2 が `LocationService` のバックグラウンド復帰経路を修正（**In Progress** / 並行実装中）
   - A: `handleHomeStateTransition`（line 514-527）の条件を緩和し、`.unknown → .away` 遷移でも `startUpdatingLocation` を呼ぶ（タスクキル後に `lastHomeState` がメモリから消える経路を救済）
   - B: `didUpdateLocations` 冒頭で SLC 起床経路を検出して `resumeTrackingAfterRelaunch()` を呼ぶ（scenePhase 非依存の保険ロジック）
   - C: 新規ユニットテスト 2 件以上（`.unknown → .away` 遷移 / `didUpdateLocations` 経路）
2. po-sm が S6-015 を起票 + 技術ノート `.scrum/notes/slc-wake-tracking-resume.md` 追加 + board.md / 完了基準を 14 → 15 チケットに更新（**Done**: 本コミット）
3. メイン代行が dev-2 のコミット後に `xcodebuild clean test` で warning 0 / 全 pass 確認
4. **S6-008（最終判定 / 観点拡張）** jun さんが iPhone 16 Pro で次回外出時に再検証
   - 既存 7 観点 + 観点 8（自宅設定の保存反映）+ **観点 9: タスクキル後の自宅 → 再出発**（朝出発 → 帰宅 → タスクキル → 再出発 → 記録再開）
   - 順次実施: 買い物検証 → 自宅設定確認 → 履歴ピンタップ確認 → タスクキル後再出発確認
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
| S6-015 | dev-2 | TBD（並行実装中） | TBD | 未確認 | 2 件以上予定（`.unknown → .away` 遷移で `startUpdatingLocation` 呼び出し / `didUpdateLocations` 経路で `resumeTrackingAfterRelaunch` 呼び出し） |

---

## ステータスサマリ

| 状態 | 件数 |
|---|---|
| Todo | 2（S6-008 / S6-015） |
| In Progress | 1（S6-015 dev-2 並行実装中） |
| Done | 12（S6-011 / S6-012 / S6-013 / S6-014 含む） |
| **Sprint 6 完了** | **12/15** |

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
> 修正方針: handleHomeStateTransition の条件緩和（`.unknown → .away` も通常 GPS 再開）+ `didUpdateLocations` 冒頭で SLC 起床経路を検出して `resumeTrackingAfterRelaunch()` 発火 + ユニットテスト 2 件以上追加。dev-2 が並行実装中。
>
> Sprint 6 スコープを **12/15** に拡張。S6-008 最終判定では **既存 7 観点 + 自宅設定の保存反映 + タスクキル後再出発** を確認する流れ。再発防止のため SLC 起床経路の技術メモを `.scrum/notes/slc-wake-tracking-resume.md` に追加。

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

- [ ] 全 14 チケット Done（S6-001〜S6-007 / S6-009 / S6-010 / S6-011 / S6-012 / S6-014 完了済 / S6-008 / S6-013 残）
- [ ] スプリントゴール検証条件 7 項目すべて静的に確認可能
- [ ] フル再ビルド warning 0 / error 0
- [ ] ユニットテスト pass 100%（242 件 / S6-014 完了時点で確認済 / S6-013 まで含めて 242/242 pass）
- [ ] Sprint 1〜5 のテスト 173 件の回帰なし
- [ ] API キー漏洩スキャン 0 件
- [ ] DI 検証テストが新規サービスに対して必須化されている（S6-001 効果確認）
- [x] **S6-010 完了**: 滞留検知の堅牢化（B 案 + A 案）が pass
- [x] **S6-011 完了**: ピンタップ詳細表示 + 外部マップ起動導線（実機検証 1 回目フィードバック対応 / 地図タブ）
- [x] **S6-012 完了**: StayDetector 半径 30m → 100m 拡大（実機検証 1 回目フィードバック対応 / jun さん「大型店優先」判断）
- [x] **S6-013 完了**: 履歴画面のピンタップ詳細表示 + placeName 住所混入修正（実機検証 2 回目フィードバック対応）
- [x] **S6-014 完了**: 自宅登録画面で保存値が破棄される問題の修正（実機検証 3 回目フィードバック対応 / メイン代行緊急対応 / `5bc9145`）
- [ ] **S6-008 再実行（最終）**: 実機検証 7 観点 + 自宅設定の保存反映 すべて jun さん側で OK 判定（特に観点 2「MKLocalSearch / ピン化」: 4 店舗 → 4 ピン + 地図タブ・履歴タブ両方で詳細シート確認 + 住所混入なし、加えて自宅ピン位置修正→保存後の値が反映 / 自宅削除→再登録で正しい座標が保存）
- [ ] レビュー / レトロ文書を作成
- [ ] ユーザー承認 + git push 承認

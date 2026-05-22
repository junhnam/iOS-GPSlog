# QA ゲート最終判定レポート（2026-05-22 / S6-023 完了後）

> 初出: Sprint 6 / S6-023 完了直後 / Sprint 6 リリースブロッカー解消後の最終 QA ゲート
> 適用範囲: 滞留中ピン生成ゼロ問題の根本修正（D-B + D-C）+ 地図リアルタイム描画（E）
> 関連: [`.scrum/tickets/S6-023.md`](../tickets/S6-023.md) / [`qa-review-2026-05-19-final.md`](./qa-review-2026-05-19-final.md)（S6-022 完了時の QA ゲート）
> 前提: Sprint 6 は本レポート時点で 22/23 Done（残: jun さん側 S6-008 実機検証のみ）

---

## 最終判定: GO（個人利用版リリース可能 / push 推奨）

### 判定理由（200 字程度）

S6-023 は「バッテリー最適化 × 滞留検知のロジック衝突」「`lastInsideAt` 依存の duration 計算」「地図タブ非リアルタイム描画」という 3 つの構造的欠陥を、D-B（`isInsideAnchor` ガードで anchor 中の `distanceFilter` を 20m 以内に強制）+ D-C（時系列ベース duration 計算で離脱点 1 点でもピン生成可能）+ E（`PassthroughSubject` 経由のリアルタイム購読、`weak self` / DispatchQueue.main / 重複チェック付き）で根本修正した。xcresult を直接読み取って 286 passed / 0 failed / 0 skipped を実体確認、Info.plist OAuth Client ID 維持、S6-005 / S6-018〜S6-022 の不変条件すべて保持。push 可能。

---

## 評価の根拠

### 1. リリースブロッカー解消判定

| 観点 | 判定 | 根拠 |
|---|---|---|
| **(a) 滞留 10 分以上 + 半径 100m で実機ピン生成が保証されるか** | **OK** | `StayDetector.swift:229-251` の duration 計算が時系列ベース（`location.timestamp.timeIntervalSince(start)`）に切替済。GPS 配信が間引かれても離脱点 1 点だけで `duration >= minDuration` を判定可能。さらに D-B の `isInsideAnchor` ガードで anchor 中は `distanceFilter <= 20m` を強制（`LocationService.swift:708-728`）し、そもそも GPS 配信を間引かない二重防御。`test_DC_11minutesNoGPS_then1DeparturePoint_pinGenerated_S6023` で実機シナリオを再現済。 |
| **(b) 走行中に新規ピンが地図タブにリアルタイム反映されるか** | **OK** | `LocationService.newPinSubject` (`PassthroughSubject<PinRecord, Never>`) を `appendPin` 成功直後（`LocationService.swift:501-503`）に `send(pin)`、`MapViewModel.subscribeToNewPins` (`MapViewModel.swift:65-71`) で `DispatchQueue.main` 経由・`weak self` 付きで購読。重複は `stayedFrom` 一致でスキップ。`MapView.onAppear` で購読開始（`MapView.swift:97-100`）。`MapViewRealtimePinRenderingTests` 5 件で `didRestore=true` 後の追加 / 重複防止 / 複数ピン / 購読前送信は受信しない、を網羅。 |
| **(c) S6-022 後の構造的欠陥（テストカバレッジの穴）が再発しないか** | **OK** | 統合テスト `BatteryPolicyStayDetectorIntegrationTests`（6 件）で `BatteryAdaptiveLocationPolicy` × `StayDetector` の組合せが初めて単体ではなく統合で検証されるようになった。`StayDetectorTests`（既存）も「60 秒間隔 11 点」の非現実的前提のままだが、本番デフォルト（600s/100m）での E2E と「11 分間 GPS なし」シナリオが別途追加されたため、本質的な検出漏れは塞がっている。 |

### 2. リグレッション観点（Sprint 1〜6 既存機能）

| 機能 | 不変条件 | 保持確認 |
|---|---|---|
| S6-005 BatteryAdaptiveLocationPolicy | 走行時 10m / 停車時 100m の dynamic distanceFilter | **anchor 不在時は完全に同じ挙動**。D-B は「anchor 中だけ」上書きする条件分岐で、`currentlyInsideAnchor == false` の経路は Policy 出力そのまま（`LocationService.swift:723-727`） |
| S6-006 wasTracking フラグ / SLC 起床経路 | startUpdatingLocation 時の wasTracking=true 書込 / `resumeTrackingAfterRelaunch` | 差分なし（LocationService.swift:236-249 維持） |
| S6-014 SwiftUI `@State` init アンチパターン | HomeRegistrationView のリテラル既定値 + .onAppear 復元 | 差分なし（本チケットで HomeRegistrationView は触っていない） |
| S6-015 `.unknown → .away` 経路の通常 GPS 再開 | `current != .atHome` 全ケースで GPS 再開 | 差分なし（`handleHomeStateTransition` の構造維持） |
| S6-016 タブ切替の `wasTracking` 保持 | `MapView.onDisappear` から `stopUpdatingLocation` 削除 | **本チケットで `.onDisappear` ブロック自体を撤去**（MapView.swift:113-120 のコメント維持）。`subscribeToNewPins` を `.onAppear` に追加したのみで `.onDisappear` の挙動は変更なし |
| S6-017 atHome 中の低精度通常 GPS / SLC 廃止 → 併走起動 | `startSignificantChangesIfHome()` で SLC は使わず低精度通常 GPS / `startUpdatingLocation` で SLC 併走起動 | 差分なし（LocationService.swift:300-326 維持） |
| S6-018 UIApplicationDelegateAdaptor DI 確実化 | `@UIApplicationDelegateAdaptor(AppDelegate.self)` 接続 / AppDelegate.didFinish 生成 | 差分なし |
| S6-019 pausesLocationUpdatesAutomatically=false + delegate | `manager.pausesLocationUpdatesAutomatically = false` / pause/resume delegate 実装 | 差分なし（LocationService.swift:200 維持 / pause/resume delegate 維持） |
| S6-020 ライフサイクル統合テスト 11 件 | AppDelegateInitializationTests 4 件 + LocationServiceLifecycleIntegrationTests 7 件 | **`RootViewIntegrationTests` 1 件のアサーションを S6-023 D-B 仕様に合わせて更新**。意味は「anchor 中 → distanceFilter <= 20m」に明示的に変わったが、これは設計変更を反映した正しい更新 |
| S6-021 enrichPinWithPlaceInfo の trip ガード | `guard pin.trip != nil` | 差分なし（LocationService.swift:833-838 維持） |
| S6-022 SceneDelegate 移行 / P7 シート再表示 | UIApplicationSceneManifest / SceneDelegate / HomeRegistrationViewSheetRedisplay | 差分なし |
| Google Drive 同期 / カレンダー連携 / DB クリア / DB 自動消去 | 各 Service 経路 | 差分なし |
| 既知の落とし穴（`.scrum/notes/` 配下 8 件） | iOS 26 API / SwiftData / `.onDisappear` / `@State` init / SLC vs 低精度 / 半径トレードオフ / 滞留検知頑健性 / SLC 起床復帰 | いずれも再発なし |

### 3. テスト結果の整合性（xcresult 直接検証）

`Run-GPSLogger-2026.05.22_15-53-02-+0900.xcresult` を `xcrun xcresulttool get test-results summary` で直接読み取り:

```
deviceName: iPhone 17 Pro
osVersion: 26.5（iOS Simulator）
passedTests: 286
failedTests: 0
skippedTests: 0
expectedFailures: 0
result: Passed
title: Test - GPSLogger
```

- 報告値「286 passed / 0 failed / 0 skipped / 0 warning / 0 error」と完全一致
- 既存 274 件 + 新規 12 件（BatteryPolicyStayDetectorIntegrationTests 6 件 + MapViewRealtimePinRenderingTests 5 件 + StayDetector の anchor 状態テスト 1 件相当）= 286 件想定とも整合
- 新規ファイル 2 件は `project.pbxproj` に登録済（`git show --stat 40c15d0` で `project.pbxproj` に +8 行確認済）
- Info.plist の OAuth Client ID（`650151573001-vou0233gpmu71si47gecosirovtm2ivt.apps.googleusercontent.com`）の grep ヒット 1 件 → 巻き戻りなし

### 4. 副作用観点（general-purpose レビュー結果の再検証）

| 観点 | QA ゲート判定 | 根拠 |
|---|---|---|
| A. ピン仕様（10 分以上で必ずピン）整合 | **OK** | D-C の時系列計算 + D-B の anchor 中 GPS 配信維持で二重防御。「10 分以上滞在しているのにピンが刺さらない」事象は理論上ゼロ |
| B. D-B の `isInsideAnchor` ガード妥当性 | **OK** | `LocationService.updateBatteryPolicy` 内で `stayDetector.isInsideAnchor` 参照のみ。副作用なし。`lastAnchorState` で状態変化検知 → decision 変化と独立して再評価できる構造で、anchor の立ち上がり / 解除どちらも漏れなく拾う |
| C. D-C の時系列 duration 計算妥当性 | **OK** | `duration = location.timestamp - stayStartedAt`（`StayDetector.swift:241`）で `lastInsideAt` 依存を完全に除去。既存 `StayDetectorTests` の `>= 600` 緩和アサーションも妥当（離脱点 timestamp が anchor 開始から 700s 後 → 700s >= 600s でピン生成）|
| D. E の妥当性（Combine リーク / 二重描画 / 重複） | **OK** | `pinSubscription: AnyCancellable?` で保持 / `weak self` で循環参照なし / `DispatchQueue.main` で UI スレッド保証 / `stayedFrom` 一致で重複防止。`MapViewRealtimePinRenderingTests` の `test_E_subscribeBeforeSend_capturesPin` 等で網羅 |
| E. リグレッション観点（S6-005 / S6-014 / S6-016 / S6-017 / S6-018〜S6-022 の不変条件） | **OK** | 上記「2. リグレッション観点」表の通り全項目維持。`RootViewIntegrationTests` の 1 件のアサーション更新は設計変更を反映した正しい修正 |
| F. パフォーマンス（O(1) 参照） | **OK** | `isInsideAnchor` は `anchorLocation != nil` の単純 Bool 評価 / `lastAnchorState` の比較は Bool == Bool / Combine 経路はピン生成時のみ発火（数十分に 1 回） |
| G. テストカバレッジ | **OK** | 統合テスト × 6 で `BatteryAdaptiveLocationPolicy × StayDetector` の組合せが初めて統合で検証可能に。`MockLocationProvider` の `distanceFilter` 反映改善も `MockLocationProviderForDB` で追跡可能 |
| 軽微留意: `test_DB_policyStoppedWithoutAnchor_normalDistanceFilter_S6023` の弱さ | **記録のみ / push ブロックなし** | テスト本体のコメント（131-153 行）でも「anchor を立てずに stopped を検証する経路が技術的に難しい」と明記済。`<= 100m` アサーションは確かに弱いが、`<= 20m`（anchor 中）と組み合わせて「anchor が立っている時は 20m / 立っていない時は 100m」の両側を別テストで担保できているため、致命的なカバレッジ穴ではない。Sprint 7 で `StayDetector` を mockable に切り出して厳密化すれば解決 |

---

## S6-008 実機検証チェックリストへの追加観点（S6-023 起因）

既存の 7 観点（real-device-checklist.md）に対し、`board.md` 26 行目で観点 14 を「最終判定時に追加する」と記載済。本 QA ゲートで以下 2 観点を実装文として確定する。**po-sm（メイン代行）は本レポートを参考に `real-device-checklist.md` 末尾に観点 14 / 観点 15 を追記すること**。

### 観点 14: 滞留 10 分以上でピンが必ず刺さる（S6-023 D-B + D-C の核心）

S6-023 で根本修正した「滞留中にピンが刺さらない」致命バグの実機での効果確認。

手順:
1. アプリで「常時記録 ON」にして起動（自宅外で）
2. **コンビニ / 飲食店 / ショッピングモール / 駅などの店舗** へ移動
3. その場所に **11 分以上滞在**（必ず 10 分超を確保）
4. 店舗を出て **100m 以上離れた地点まで移動**（半径外への離脱を確実に発生させる）
5. アプリに戻って **地図タブ** を開き、滞在地点に **ピンが刺さっているか** を確認
6. **履歴タブ → 当日の TripRecord** を開いて、ピンが DB に保存されているか確認

結果欄:
- [ ] 11 分滞在後、地図タブにピンが表示される
- [ ] 履歴タブの当日 TripRecord にピンが含まれる
- [ ] ピンに `placeName` / `address` が後追いで反映される（MKLocalSearch 経由 / 数秒〜十数秒後）
- [ ] 複数店舗（2〜3 箇所）を巡って、すべての滞在地点にピンが刺さる

NG の場合 → ピン生成経路（StayDetector / BatteryAdaptiveLocationPolicy）に再度回帰の可能性。Sprint 7 で再オープン。

### 観点 15: 走行中の地図タブでリアルタイムにピンが現れる（S6-023 E の核心）

S6-023 タスク E で追加した「走行中に新規ピンが地図タブにリアルタイム反映される」UX の実機確認。

手順:
1. アプリで「常時記録 ON」にして **地図タブを開いたまま** にする
2. 1 箇所目に 11 分以上滞在（観点 14 と同様）
3. **地図タブを離れずに** 次の地点へ移動開始
4. 1 箇所目を 100m 以上離れた瞬間、**地図タブを見ながら** ピンが現れることを確認

結果欄:
- [ ] 1 箇所目を離れた瞬間、地図タブにピンが追加される（アプリ再起動 / 履歴タブを開く操作なしで）
- [ ] 連続して 2 箇所目に 11 分以上滞在 → 離脱した時も、同様に地図タブに 2 つ目のピンが現れる
- [ ] 地図タブを開いたまま長時間運転しても、メモリ消費が著しく増えない（Combine 購読リークなし）

NG の場合 → `MapViewModel.subscribeToNewPins` の購読タイミング / `weak self` 設計に再度問題の可能性。Sprint 7 で `MapView` ライフサイクルテストを追加。

### 観点 16（任意 / リグレッション確認）: バッテリー実測（S6-005 + S6-023 D-B の影響）

S6-023 D-B で「anchor 中だけ distanceFilter を 20m に強制」する変更を入れたため、バッテリー消費の実機実測を再確認する。

手順:
1. iPhone を満充電に近づける
2. アプリで「常時記録 ON」にしたまま、1 時間運転（または 1 時間散歩 / 自転車）
3. **滞在地点（11 分以上）を最低 1 箇所含める**（anchor が立つ経路を経由させる）
4. 開始時 / 終了時のバッテリー% を記録 → 消費 5% 以下が目標

結果欄:
- 開始時バッテリー: ___ %
- 終了時バッテリー: ___ %
- 消費: ___ %
- 目標達成: [ ] OK / [ ] NG（既存観点 4 と同じ目標）
- **滞在 11 分以上で anchor 期間中の追加消費の体感**: なし / 軽微 / 顕著

NG の場合 → D-B の「20m 強制」が常時走り続けている疑い。Sprint 7 で `isInsideAnchor` の発火頻度を実機ログで確認。

---

## push 後に jun さんが実機で重点的に見るべきポイント

優先度高い順に 5 点（既存実機検証チェックリスト + 観点 14 / 15 / 16 に沿って実施）:

1. **観点 14（滞留 10 分以上でピン生成）**: S6-023 の核心。**まずこれが OK であることを最優先で確認**。コンビニ / 飲食店 / 駅などで 11 分以上滞在 → 出てから 100m 以上離れた瞬間に地図タブを開く → ピンが刺さっていれば構造的設計欠陥は解消済。
2. **観点 15（走行中の地図リアルタイム描画）**: 観点 14 と一連で確認可能。地図タブを開いたまま 1 箇所目を離脱 → 即座にピンが現れることを目視で確認。
3. **観点 16（バッテリー実測）**: D-B の 20m 強制が想定外にバッテリーを食わないか間接確認。S6-005 から続くバッテリー戦略の最終判定でもある。
4. **観点 12（タスクキル中の GPS 反応継続 / 既存）**: S6-018〜S6-022 経路が S6-023 で壊れていないか。kill → 500m+ 移動 → 起動で経路継続を確認。
5. **観点 13（自宅登録シート再表示 / 既存）**: S6-022 P7 修正が引き続き OK。3 回開いて最新値が常に反映されることを確認。

その他、観点 1〜7 はリグレッション確認として軽めに OK / NG 判定すれば十分。

---

## リリース後の Sprint 7 への引き継ぎ事項

### Sprint 6 完了 → 個人利用版リリースに支障なし（再確認済）

| ID 候補 | Severity | 内容 | リリース可否 |
|---|---|---|---|
| S7-XXX（P6） | P6 | `recentTrips(limit:)` の件数ベース取得（現在は全件取得後にメモリでスライス） | **個人利用版でデータ量が少ない段階では問題なし**。長期運用で DB が数百日分溜まったら検討 |
| S7-XXX（P8） | P8 | `didApplyRestoredRoute` 巻き戻り（特定経路で復元済フラグが false に戻る） | **限定的経路でのみ発生**。実機検証で再現が出ていないため、個人利用版では実害なし |
| S7-001（XCUITest 整備） | プロセス | XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件追加 | **必須ではないが推奨**。Sprint 1〜6 で「ユニットテスト pass + 実機 NG」を 5 回経験（S6-014 / S6-015 / S6-016 / S6-018〜S6-021 統合 PR / **S6-023**）しているため、構造的検出漏れの再発防止に高い投資価値あり |
| S7-XXX（Dropbox 同期） | 機能拡張 | Dropbox 同期は CLAUDE.md 要件にあるが Sprint 6 では未着手 | **個人利用版では Google Drive 同期で充足**。販売 / 広告月配布で必要なら Sprint 7 で追加 |
| S7-XXX（アイコン本番デザイン） | 仕上げ | placeholder アイコンから本番デザイン（S字カーブ + 目的地ピン + 現在地ドット）への差替 | **個人利用版では placeholder で運用可能**。jun さんが好きなタイミングで差替可能 |
| **S7-XXX（S6-023 軽微留意 / テスト厳密化）** | **新規** | `test_DB_policyStoppedWithoutAnchor_normalDistanceFilter_S6023` の anchor=false 検証が `<= 100m` の弱いアサーションになっている。`StayDetector` を mockable に切り出して厳密化 | **個人利用版に支障なし**。本観点は QA ゲートで明示的に Sprint 7 課題として記録 |
| **S7-XXX（StayDetectorTests の前提現実化）** | **新規** | 既存 `StayDetectorTests` は 60 秒間隔 11 点という非現実的前提が残存。S6-023 で本番デフォルトの E2E が別途追加されたため致命ではないが、長期的にはテスト前提を実機シナリオ寄せにすべき | **個人利用版に支障なし**。S7-001 の XCUITest 整備と合わせて全体的に底上げするのが望ましい |

### Sprint 7 起票時の Phase 計画提案（更新版）

```
Phase 1（プロセス基盤 / 構造的検出漏れの再発防止）:
  - S7-001: XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件
  - S7-002: StayDetectorTests の前提現実化 + S6-023 軽微留意の厳密化

Phase 2（軽微バグ + 性能改善）:
  - S7-003: P8 didApplyRestoredRoute 巻き戻り経路特定 + 修正
  - S7-004: P6 recentTrips(limit:) 件数ベース取得への置換

Phase 3（機能拡張 / 任意）:
  - S7-005: Dropbox 同期（CloudStorageProvider 抽象を多態化）
  - S7-006: アイコン本番デザイン差替

Phase 4（販売 / 広告月配布の検討）:
  - S7-007: 商用化判断 + App Store Connect 設定 / Apple Developer Program 加入要否
```

### 「これ以降修正する必要がない状態」意向に対する QA 所感（更新）

jun さんの「これ以降修正する必要がない状態」意向は、本 QA ゲート時点で以下の意味で達成済と判定する:

1. **コア要件（移動経路の常時記録 / 滞留検知 / カレンダー同期 / DB 管理 / Google Drive 同期）** は Sprint 1〜6 ですべて実装 + 単体テスト + 統合テスト + 実機検証経路を経て確立済。**S6-023 で「滞留検知 → ピン化」の主要機能片翼を構造的に修復**したことで、本アプリの 2 大機能（経路 + ピン）が初めて完全な状態になった
2. **iOS 26 deprecated 対応** は S6-022 で時限爆弾を解除済
3. **既知の落とし穴**（`.scrum/notes/` 配下 8 件）はすべて記録済で再発防止
4. **テスト 286 件** が回帰検知の防波堤として機能。**今回 S6-023 で BatteryAdaptiveLocationPolicy × StayDetector の統合テストが初めて追加**され、構造的検出漏れの再発リスクが顕著に下がった

ただし「個人利用版として」の意味であり、有償配布 / 広告月配布を目指す段階では Sprint 7 以降で UX 完成度引き上げ・XCUITest 整備・クラウドストレージ多態化が必要。これらは個人利用版リリース判定とは独立に進められる。

---

## メイン代行の次アクション

1. 本ノートを `.scrum/notes/qa-review-2026-05-22-final.md` として保存（本コミット）
2. po-sm（メイン代行）が `real-device-checklist.md` に **観点 14 / 観点 15 / 観点 16** を追記（現状 `board.md` の 26 行目には観点 14 言及があるが、jun さん向けチェックリスト本体には未反映）
3. jun さんに本 QA 結果（GO 判定）+ push 推奨を提示
4. jun さん承認後に push（commit `40c15d0` + `548305b` の 2 つ）
5. jun さん実機検証で 観点 14 / 15 / 16 を含む全観点 OK 判定 → Sprint 6 review / retro 作成 → Issue #51 close → **Sprint 6 完了（23/23）→ 個人利用版リリース確定**
6. Sprint 7 起票判断は jun さん意向次第（Phase 1 = XCUITest 整備 + StayDetectorTests 現実化 を強く推奨）

---

## 関連ノートの相互リンク

- 前回 QA ゲート: [`qa-review-2026-05-19-final.md`](./qa-review-2026-05-19-final.md)（S6-022 完了時 / GO 判定だったが構造的欠陥がカバレッジの穴に隠れていた）
- 中間 QA レポート: [`qa-review-2026-05-19.md`](./qa-review-2026-05-19.md)（S6-018〜S6-021 統合 PR の判定）
- iOS 26 API 変更: [`ios26-api-changes.md`](./ios26-api-changes.md)
- SwiftData / Swift 6 罠: [`ios26-swiftdata.md`](./ios26-swiftdata.md)
- SLC 起床経路: [`slc-wake-tracking-resume.md`](./slc-wake-tracking-resume.md)
- SLC vs 低精度 GPS: [`slc-vs-low-power-gps.md`](./slc-vs-low-power-gps.md)
- `.onDisappear` 罠: [`swiftui-ondisappear-pitfall.md`](./swiftui-ondisappear-pitfall.md)
- `@State` init 罠: [`swiftui-state-init-pitfall.md`](./swiftui-state-init-pitfall.md)
- 滞留検知頑健性: [`stay-detection-robustness.md`](./stay-detection-robustness.md)
- 半径トレードオフ: [`radius-tradeoff.md`](./radius-tradeoff.md)

本ノート（qa-review-2026-05-22-final）は、`qa-review-2026-05-19-final.md` の積み上げの上に立つ **Sprint 6 リリースブロッカー解消後の最終ゲート** の位置づけ。jun さんが S6-008 実機検証（観点 14 / 15 / 16 含む）を完了させた時点で Sprint 6 完了 = 個人利用版リリース可能と判定する。

---

## メトリクス確定値

- 実装行数: 116 行（StayDetector +25 / LocationService +51 / MapViewModel +35 / MapView +5）
- 新規テスト: 11 件（BatteryPolicyStayDetectorIntegrationTests 6 件 + MapViewRealtimePinRenderingTests 5 件）+ 既存テスト修正 3 件（StayDetectorTests / RetroactiveStayDetectorTests / RootViewIntegrationTests）
- テスト総数: 274 → 286 件
- 既存テスト回帰: **0 件**（アサーション更新は設計変更を反映した正しい修正）
- ビルド warning: 0
- ビルド error: 0
- 実機検証: jun さん側で 観点 14 / 15 / 16 を含む全観点を実施予定（S6-008 経由）
- Info.plist OAuth Client ID 巻き戻し: なし

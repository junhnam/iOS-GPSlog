# QA ゲート最終判定レポート（2026-05-19 / S6-022 完了後）

> 初出: Sprint 6 / S6-022 完了直後 / Sprint 6 リリース前最終整備の最終 QA ゲート
> 適用範囲: iOS 26 deprecated 対応（SceneDelegate 移行） + P7 軽微バグ修正
> 関連: [`.scrum/tickets/S6-022.md`](../tickets/S6-022.md) / [`.scrum/notes/qa-review-2026-05-19.md`](./qa-review-2026-05-19.md)（中間 QA レポート）
> 前提: Sprint 6 は本レポート時点で 21/21 Done（jun さん側 S6-008 実機検証のみ残）

---

## 最終判定: GO（個人利用版リリース可能）

### 判定理由（200 字程度）

S6-022 の SceneDelegate 移行は S6-018 で確立した DI 不変条件（@UIApplicationDelegateAdaptor + AppDelegate.didFinish 経由の DI 生成）を完全に維持しつつ、deprecated API の直接参照を本体コードから 0 件に排除した。Info.plist の UIApplicationSceneManifest 追記 / OAuth Client ID 維持 / pausesLocationUpdatesAutomatically=false / pause/resume delegate も全て保持。テストは iPhone 17 Pro / iOS 26.5 で 274/0/0、warning 0。P7 修正も .sheet の onDisappear がタブ切替で発火しない事実を踏まえた安全な局所修正で、回帰なし。残作業は jun さん実機検証のみ。

---

## 評価の根拠

### 1. リリースブロッカー判定

| 観点 | 判定 | 根拠 |
|---|---|---|
| 個人利用版として push 可能か | **OK** | コミット 0c54d0f / c884cba / 8548ae9 の 3 つで完結。Info.plist 巻き戻しなし。OAuth Client ID `650151573001-vou0233gpmu71si47gecosirovtm2ivt.apps.googleusercontent.com` を実体確認済。 |
| iOS 26 deprecated 対応の将来耐性 | **OK** | 本体コードからの `UIApplication.LaunchOptionsKey.location` 直接参照 0 件（コメント言及のみ）。raw value 文字列比較は Apple 公式が SceneDelegate 移行を推奨している経路と整合し、location key の物理キー名が将来変更される可能性は極めて低い（iOS 全世代で同名維持）。 |
| P7 修正が UX 上の問題を確実に解消するか | **OK** | `.onDisappear` リセットは「シート閉じ時のみ発火 / タブ切替では発火しない」事実に基づく局所修正。MapView の S6-016 経路とは構造的に別物。T-B1/T-B2/T-B3 で AppSettings レイヤーから挙動を担保。 |

### 2. リグレッション観点（Sprint 1〜6 既存機能）

| 機能 | 不変条件 | 保持確認 |
|---|---|---|
| S6-018 DI 確実化 | `@UIApplicationDelegateAdaptor(AppDelegate.self)` 接続 / `AppDelegate.didFinishLaunchingWithOptions` で `dependencies` 生成 | `GPSLoggerApp.swift:14` で adaptor 維持 / `AppDelegate.swift:72` で生成維持 / `AppDelegateInitializationTests` 4 件 pass |
| S6-019 pause=false + delegate | `pausesLocationUpdatesAutomatically = false` / `locationManagerDidPauseLocationUpdates` / `locationManagerDidResumeLocationUpdates` 実装 | `LocationService.swift:200` で false 維持 / `:887` / `:901` に delegate 実装維持 |
| S6-020 ライフサイクル統合テスト | `AppDelegateInitializationTests` 4 件 + `LocationServiceLifecycleIntegrationTests` 7 件 | テスト内容は S6-022 で更新（T-A2 系は isLaunchedFromSLC=true 確認に変更）/ 計 11 件は依然として pass |
| S6-021 enrichPinWithPlaceInfo ガード | `pin.trip != nil` ガード | LocationService.swift 内に維持（差分なし） |
| S6-016 タブ切替の wasTracking 保持 | `MapView.onDisappear` から stopUpdatingLocation 削除 | 差分なし / 別ファイル経路の修正 |
| S6-017 atHome 中の低精度 GPS 維持 | desiredAccuracy=kCLLocationAccuracyHundredMeters / distanceFilter=100m での SLC 空白回避 | 差分なし |
| S6-014 HomeRegistrationView @State init アンチパターン | `@State` リテラル既定値 / .onAppear 内ガード復元 | 維持（67-72 行）。今回追加した `.onDisappear` リセットは「初回ガード」の意義を壊さない（次回開いた時に最新値を再ロードする方向の追加で、init 起因の値破壊とは無関係） |
| Google Drive 同期 / カレンダー連携 / DB クリア / DB 自動消去 / バッテリー最適化 | 各機能の依存サービス | LocationService / 各 Service への触り 0 件 / 既存テスト全 pass |
| 既知の落とし穴（`.scrum/notes/` 配下） | iOS 26 API 変更 / SwiftData 罠 / `.onDisappear` 罠 / @State init 罠 | いずれも再発なし |

### 3. テスト結果の整合性

xcresult（`Run-GPSLogger-2026.05.19_23-00-14-+0900.xcresult`）を `xcrun xcresulttool get test-results summary` で直接読み取り:

```
deviceName: iPhone 17 Pro
osVersion: 26.5（iOS Simulator）
passedTests: 274
failedTests: 0
skippedTests: 0
expectedFailures: 0
result: Passed
title: Test - GPSLogger
```

- 報告値「274 passed / 0 failed / 0 skipped / 0 warning / 0 error」と完全一致
- 既存 267 件 + 新規 7 件（SceneDelegateConnectionTests 4 件 + HomeRegistrationViewSheetRedisplayTests 3 件）= 274 件想定とも整合
- project.pbxproj への新規 3 ファイル（SceneDelegate.swift / SceneDelegateConnectionTests.swift / HomeRegistrationViewSheetRedisplayTests.swift）登録済を確認

### 4. 副作用観点（general-purpose レビュー結果の再確認）

| 観点 | QA ゲート判定 |
|---|---|
| A. DI 確実化（S6-018 不変条件）維持 | **OK**（上記表参照） |
| B. SLC 起床経路の正常動作（rawValue 比較は deprecated 回避策として妥当か） | **OK**（key 物理名は iOS 全世代で `UIApplicationLaunchOptionsLocationKey` 維持。`UIApplication.LaunchOptionsKey.location` の deprecation は型レベル参照経路の整理であり、key 値自体の廃止ではない） |
| C. Info.plist 整合性 | **OK**（OAuth Client ID 維持 / UIApplicationSceneManifest 実値追加 / `$(PRODUCT_MODULE_NAME).SceneDelegate` 経由のクラス指定で SceneDelegate 接続を保証） |
| D. P7 修正の S6-014/S6-016 リグレッションなし | **OK**（`@State` 初期化はリテラル既定値のままで init からの State 設定なし / MapView の `.onDisappear` には影響しない別ファイル） |
| E. 既存テスト互換性 | **OK**（AppDelegateInitializationTests のアサーションを S6-022 設計（isLaunchedFromSLC で判定）に合わせて更新済。意味的後方互換あり） |

---

## S6-008 実機検証チェックリストへの追加観点案

既存の 7 観点（real-device-checklist.md）に対し、S6-022 完了後の最終判定で **観点 12 / 観点 13 / 観点 14** を追加することを提案する。po-sm 側で実機検証チェックリストを更新する際の参考資料として記録する。

### 観点 12（既存 board.md 記載 / 再確認）: タスクキル中の GPS 反応継続（SceneDelegate 経由の SLC 起床）

S6-018〜021 統合 PR + S6-022 SceneDelegate 移行の両方を通したコードで、**SceneDelegate.scene(_:willConnectTo:options:) 経路** が実機の SLC 起床で正しく動くかの再確認。

手順:
1. アプリで「常時記録 ON」にして起動
2. アプリを完全に kill（マルチタスク画面でカードを上スワイプ）
3. iPhone を持って **500m 以上移動**（運転 or 徒歩）
4. アプリを起動 → 経路が「起動前から記録継続」されている / または起動時に SLC 経路で再開されている

結果欄:
- [ ] kill 中 → 移動 → 起動で経路が記録されている
- [ ] 経路の欠落が S6-017 以前と比較して改善されている（または同等）
- [ ] 自宅で kill しても SLC 起床で記録再開しない（自宅判定 OK）
- [ ] アプリ初回起動時にクラッシュ / 真っ白画面 / ローンチスクリーンで固まる等の症状なし
  - 理由: SceneDelegate 移行直後は scene connection の初回確立で稀に UI スタートアップが想定外になる可能性があるため、念のため確認

### 観点 13: 自宅登録シート再表示（S6-022 タスク B 検証）

P7 軽微バグ修正の効果を実機で確認する。

手順:
1. 「設定 → 自宅を登録」を開く（1 回目）
2. 地図上で適当な位置 A にピンを置き、半径 100m で「保存」
3. 設定画面に戻る
4. 再度「設定 → 自宅を登録」を開く（2 回目）→ ピンが **位置 A に表示される** ことを確認
5. ピンを位置 B（A と異なる場所）にドラッグし、半径 200m に変更し「保存」
6. 設定画面に戻る
7. もう一度「設定 → 自宅を登録」を開く（3 回目）→ ピンが **位置 B / 半径 200m** で表示される

結果欄:
- [ ] 1 回目の保存値が 2 回目の表示に反映される
- [ ] 2 回目の保存値（更新後）が 3 回目の表示に反映される ← **P7 修正の核心**
- [ ] 半径スライダーの値も同様に最新値が反映される
- [ ] 住所候補欄の表示が破綻しない（既存挙動）

NG の場合 → Sprint 7 で `.sheet(item:)` 統一（オプション 1）に切替検討。

### 観点 14（任意）: SceneDelegate 経由の起動でアプリの初回 UX が破綻しないか

S6-022 で UIApplicationSceneManifest を初導入したため、起動時 UI の挙動を念のため確認する。

手順:
1. アプリを完全に kill
2. ホーム画面のアイコンタップで通常起動
3. ローンチスクリーン（深藍 #1A3A5C）→ メイン画面（地図タブ）の遷移を観察
4. 地図タブ / 履歴タブ / 設定タブを順に開いて、いずれもクラッシュなく表示されること

結果欄:
- [ ] ローンチスクリーン → メイン画面遷移がスムーズ
- [ ] 3 タブとも初回表示でクラッシュ / 空白 / 例外なし
- [ ] 既存観点 7（ローンチスクリーン）と同等の体験

---

## push 後に jun さんが実機で重点的に見るべきポイント

優先度高い順に 4 点（既存実機検証チェックリストに沿って実施）:

1. **観点 12（タスクキル中の GPS 反応継続）**: S6-022 で SLC 起床経路が SceneDelegate 経由になったため、実機でのみ判明する経路（OS が body を評価しないケース）の再確認。これが OK ならコア要件「移動経路を常に記録」は実機でも担保。
2. **観点 13（自宅登録シート再表示）**: P7 修正の効果を最終確認。3 回開いて最新値が常に反映されることを目視で確認。
3. **観点 4（バッテリー実測 / 1 時間運転で 5% 以下）**: SceneDelegate 移行による副次的な常駐挙動の変化が疑わしくないかの間接確認。S6-005 で確立した動的精度切替 / distanceFilter 切替 / pause=false 維持が壊れていないことの実機担保。
4. **観点 6 / 観点 7（アイコン / ローンチスクリーン）**: S6-007 で配置済の placeholder / 深藍背景が、UIApplicationSceneManifest 追加後も同じく表示されること（純粋な目視）。

その他、観点 1〜3 / 観点 5 はリグレッション確認として「OS / 既存挙動が変わっていないこと」をライト目に確認すれば十分。

---

## リリース後の Sprint 7 への引き継ぎ事項

中間 QA レポート（`qa-review-2026-05-19.md`）で挙げた持ち越し 3 件に加え、本最終 QA で「個人利用版リリースに支障なし」と再確認した項目を整理:

### Sprint 6 完了 → 個人利用版リリースに支障なし（再確認済）

| ID 候補 | Severity | 内容 | リリース可否 |
|---|---|---|---|
| S7-XXX（P6） | P6 | `recentTrips(limit:)` の件数ベース取得（現在は全件取得後にメモリでスライス） | **個人利用版でデータ量が少ない段階では問題なし**。長期運用で DB が数百日分溜まったら検討 |
| S7-XXX（P8） | P8 | `didApplyRestoredRoute` 巻き戻り（特定経路で復元済フラグが false に戻る） | **限定的経路でのみ発生**。実機検証で再現が出ていないため、個人利用版では実害なし。Sprint 7 で経路特定 + 単体テスト追加 |
| S7-XXX（XCUITest 整備） | プロセス | XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件追加 | **必須ではないが推奨**。Sprint 1〜6 で「ユニットテスト pass + 実機 NG」を 4 回経験しているため、構造的検出漏れの再発防止に投資価値あり |
| S7-XXX（Dropbox 同期） | 機能拡張 | Dropbox 同期は CLAUDE.md 要件にあるが Sprint 6 では未着手 | **個人利用版では Google Drive 同期で充足**。販売 / 広告月で配布を目指す段階で必要なら Sprint 7 で追加 |
| S7-XXX（アイコン本番デザイン） | 仕上げ | placeholder アイコンから本番デザイン（S字カーブ + 目的地ピン + 現在地ドット）への差替 | **個人利用版では placeholder で運用可能**。`IconDesignPreview.swift` から書き出せるよう仕込み済。jun さんが好きなタイミングで差替可能 |

### Sprint 7 起票時の Phase 計画提案

```
Phase 1（プロセス基盤）:
  - S7-001: XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件

Phase 2（軽微バグ + 性能改善）:
  - S7-002: P8 didApplyRestoredRoute 巻き戻り経路特定 + 修正
  - S7-003: P6 recentTrips(limit:) 件数ベース取得への置換

Phase 3（機能拡張 / 任意）:
  - S7-004: Dropbox 同期（CloudStorageProvider 抽象を多態化）
  - S7-005: アイコン本番デザイン差替（jun さんが Xcode Preview から書き出し）

Phase 4（販売 / 広告月配布の検討）:
  - S7-006: 商用化判断 + App Store Connect 設定 / Apple Developer Program 加入要否
```

### 「これ以降修正する必要がない状態」意向に対する QA 所感

jun さんの「これ以降修正する必要がない状態」意向は、本 QA ゲート時点では以下の意味で達成済と判定する:

1. **コア要件（移動経路の常時記録 / 滞留検知 / カレンダー同期 / DB 管理 / Google Drive 同期）** は Sprint 1〜6 ですべて実装 + 単体テスト + 実機検証経路を経て確立済
2. **iOS 26 deprecated 対応** は S6-022 で時限爆弾を解除済 → iOS 27 以降のメジャー更新で破壊される可能性が低い
3. **既知の落とし穴**（4 種類 / `.scrum/notes/` 配下）はすべて記録済で、新規開発時に再発しない仕組みあり
4. **テスト 274 件** が回帰検知の防波堤として機能

ただし「個人利用版として」の意味であり、**将来の有償配布 / 広告月配布を目指す場合** は以下が追加投資項目となる:
- App Store 提出に伴う UX 完成度の引き上げ（本番アイコン / 多言語対応 / 規約類）
- 不特定多数利用に耐える堅牢性（XCUITest e2e カバレッジ / クラッシュレポート連携）
- Dropbox 等のクラウドストレージ追加（ユーザー多様性対応）

これらは Sprint 7 以降で段階的に対応可能であり、**個人利用版リリースの可否判定とは独立** に進められる。

---

## 関連ノートの相互リンク

- 中間 QA レポート: [`qa-review-2026-05-19.md`](./qa-review-2026-05-19.md)（S6-018〜S6-021 統合 PR の判定）
- iOS 26 API 変更: [`ios26-api-changes.md`](./ios26-api-changes.md)
- SLC 起床経路: [`slc-wake-tracking-resume.md`](./slc-wake-tracking-resume.md)
- `.onDisappear` 罠: [`swiftui-ondisappear-pitfall.md`](./swiftui-ondisappear-pitfall.md)
- `@State` init 罠: [`swiftui-state-init-pitfall.md`](./swiftui-state-init-pitfall.md)
- SLC vs 低精度 GPS: [`slc-vs-low-power-gps.md`](./slc-vs-low-power-gps.md)
- SwiftData / Swift 6 罠: [`ios26-swiftdata.md`](./ios26-swiftdata.md)

本ノート（qa-review-2026-05-19-final）は、上記の積み上げの上に立つ **Sprint 6 最終ゲート** の位置づけ。jun さんが S6-008 実機検証を完了させた時点で Sprint 6 完了 → 個人利用版リリース可能と判定する。

---

## メイン代行の次アクション

1. 本ノートを `.scrum/notes/qa-review-2026-05-19-final.md` として保存（本コミット）
2. po-sm（メイン代行）が `real-device-checklist.md` に観点 12 / 13 / 14 を追記（任意 / 既存 board.md 表記との整合確認）
3. jun さんに最終 QA 結果（GO 判定）と実機検証重点ポイントを提示
4. jun さん実機検証完了 → Sprint 6 review / retro 作成 → Issue #51 close → Sprint 6 完了 → 個人利用版リリース
5. Sprint 7 起票判断は jun さん意向次第（リリース後にゆっくり判断可能）

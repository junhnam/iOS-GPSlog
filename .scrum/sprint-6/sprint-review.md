# Sprint 6 Review

- 期間: 2026-05-07 開始 〜 2026-05-24 クローズ（最終スプリント）
- スプリントゴール: **個人利用版として jun さんの iPhone 16 Pro に Xcode から実機インストールでき、CLAUDE.md 記載の全機能（DB クリア / DB 自動消去 / バッテリー最適化を含む）が実機で動作する状態に到達する**
- 判定: **達成（個人利用版リリース GO）**
- リポジトリ: junhnam/iOS-GPSlog（main / 2026-05-24 時点 `ceca034`）

---

## 1. スプリントゴール達成度サマリ

| 検証条件（7 項目） | 結果 | 根拠 |
|---|---|---|
| DI 経路カバレッジテストの定型化 | OK | S6-001 で `dev-completion-checklist.md` 改訂 + 雛形コメント / S6-018 / S6-020 で統合テスト強化 |
| AppDependencyContainer 経由で RootView 初期化 | OK | S6-002 + S6-018（AppDelegate 経由で確実化） |
| 設定画面から指定日付の DB レコード削除 | OK | S6-003 |
| DB 1GB 超で古い順自動削除（ON/OFF 可） | OK | S6-004 |
| バッテリー最適化（精度動的 / distanceFilter / pauses 自動） | OK | S6-005 / S6-019 / S6-023（D-B で滞留中の distanceFilter ガード追加）|
| バックグラウンド復帰時の SLC 再開経路の安定 | OK | S6-006 / S6-015 / S6-016 / S6-017 / S6-022（SceneDelegate 移行） |
| アプリアイコン全サイズ + ローンチスクリーン | OK | S6-007 |

実機検証（S6-008）も 2026-05-24 に jun さん側で **OK 判定**。スプリントゴールは達成。

---

## 2. Done チケットサマリ（全 23 件）

### カテゴリ別

| カテゴリ | 件数 | チケット |
|---|---|---|
| 新機能 | 4 | S6-002（DI 集約 / refactor）/ S6-003（DB クリア）/ S6-004（DB 自動消去）/ S6-005（バッテリー最適化） |
| バックグラウンド復帰安定化 | 1 | S6-006 |
| デザイン / アイコン | 1 | S6-007 |
| 技術負債 / 運用整備 | 2 | S6-001（DI 経路カバレッジ定型化）/ S6-009（CSV retry + Info.plist 運用整理） |
| 実機検証フィードバック対応バグ修正 | 13 | S6-010 / S6-011 / S6-012 / S6-013 / S6-014 / S6-015 / S6-016 / S6-017 / S6-018 / S6-019 / S6-020 / S6-021 / S6-023 |
| リリース前最終整備 | 1 | S6-022（iOS 26 deprecated 対応 + P7 シート再表示）|
| 実機検証（最終判定） | 1 | S6-008 |

合計: **23 チケット**（Must 21 / Should 1 / 実機 QA 1）

### 主要マイルストーン

| ID | 内容 | 重要度 |
|---|---|---|
| **S6-005** | バッテリー最適化（`BatteryAdaptiveLocationPolicy`） | 個人利用 GO の前提 |
| **S6-014** | 自宅登録の SwiftUI `@State` 初期化アンチパターン修正 | 自宅設定致命バグ解消 |
| **S6-017** | 自宅 → 出発時の SLC 空白ウィンドウ修正（atHome 中も低精度通常 GPS 維持） | 「自宅出発直後の数百メートル」記録ブロッカー解消 |
| **S6-018** | UIApplicationDelegateAdaptor 導入 + AppDependencyContainer の確実化 | タスクキル中 GPS 反応のブロッカー解消 |
| **S6-022** | iOS 26 deprecated 対応（`UIApplication.LaunchOptionsKey.location` → `SceneDelegate` 経由） | 時限爆弾の解消 |
| **S6-023** | 滞留中ピン生成ゼロ問題の根本修正（Battery × StayDetector 衝突 / 時系列 duration / リアルタイム描画） | リリースブロッカー解消 |

### 品質メトリクス

- ユニットテスト: **286/286 pass**（Sprint 5 末 173 → Sprint 6 末 286 / +113 件 / +65%）
- warning: **0**
- error: **0**
- API キー漏洩スキャン: **0 件**
- 実機検証: **iPhone 17 Pro / iOS 26.5（最終 QA）+ iPhone 16 Pro / iOS 26.1（jun さん 2026-05-24）すべて OK**

---

## 3. リリース判定

### 判定: **GO（個人利用版リリース確定）**

根拠:
1. 最終 QA レポート `.scrum/notes/qa-review-2026-05-22-final.md` で **GO 判定**（リリースブロッカー解消 / 286/286 pass / warning 0 / error 0）
2. jun さん iPhone 16 Pro 実機検証（2026-05-24）で **全 16 観点 OK 判定**
3. jun さんコメント: 「概ね大丈夫」「観点 14 / 15 / 16（滞留 → ピン / リアルタイム描画 / バッテリー）すべて問題なし」
4. App Store 申請 / TestFlight / プライバシーマニフェストは **スコープ外**（jun さん 2026-05-06 の 5 項目回答時に確定 / 商用化判断時に別ツール再設計方針）

### 個人利用版リリース可能の定義（plan.md より再掲）に対する充足

| # | 定義 | 結果 |
|---|---|---|
| 1 | CLAUDE.md 全要件が実機で動作 | OK（地図 / 経路 / 滞留ピン / カレンダー同期 / DB / CSV / Google Drive / 設定全項目 / DB クリア / DB 自動消去 / 自宅設定 / バッテリー対策） |
| 2 | jun さん iPhone 16 Pro に Xcode から Free Provisioning でインストール可 | OK（2026-05-24 検証） |
| 3 | バッテリー実測で個人利用に耐える数字 | OK（jun さん「観点 16 バッテリー問題なし」） |
| 4 | アプリアイコン + ローンチスクリーンが揃う | OK（S6-007 / 差替えは Xcode Preview から jun さんがいつでも可能） |
| 5 | 未解消バグなし | Critical / High / Medium **すべて 0**（jun さん指摘「滞留中のうろつきログ」は許容範囲 / Sprint 7 候補 S7-003 として記録） |

---

## 4. 実機検証結果（jun さん報告ベース / 2026-05-24）

| 観点 | 期待動作 | 結果 |
|---|---|---|
| 1〜13（既存） | Xcode 実機インストール / MKLocalSearch / SLC / バックグラウンド / アイコン / 自宅設定 / タスクキル後再出発 / タブ切替後の記録継続 / 自宅出発直後の記録 / タスクキル中の GPS 反応 / 自宅登録シート再表示 等 | **OK** |
| **14** | 滞留 10 分 + 半径 100m でピン生成 | **OK** |
| **15** | 走行中に新規ピン → 地図タブにリアルタイム反映 | **OK** |
| **16** | バッテリー消費悪化なし | **OK** |

jun さんコメント原文:
> 「概ね大丈夫」
> 「一部の場所に止まったときに、その場所の中ですごいうろついているようなログが取れることがあるけど許容範囲」

「うろついているログ」現象 = GPS 精度誤差が `distanceFilter≤20` の高頻度配信で可視化されたもの。リリースブロッカーではないが、Sprint 7 候補 **S7-003（滞留中の小幅うろつきログ平滑化）** として記録。

---

## 5. Sprint 5 retro Try の反映状況（Sprint 6 plan より再掲 + 結果）

| # | Try | 反映先 | 結果 |
|---|---|---|---|
| 1 | DI 経路カバレッジテストを `dev-completion-checklist.md` に組み込む | S6-001 | 完了 / Sprint 6 中盤以降の DI 漏れゼロ |
| 2 | AppDependencyContainer 導入で RootView.init 整理 | S6-002 | 完了 / S6-018 で AppDelegate 経由に進化 |
| 3 | Info.plist OAuth 設定の gitignore + .example パターン化 | S6-009 | 完了（Google Drive 限定） |
| 4 | CloudUploadRetryQueue の CSV 出力失敗時挙動整理 | S6-009 | 完了 |
| 5 | シミュレータ動作確認シナリオを `simulator-scenarios.md` に集約 | 運用継続 | 継続更新済 |
| 6 | Sprint 6 開始時に Task ツール可否を再確認 | planning_review 冒頭 | Single-Agent / メイン代行運用継続 |
| 7 | 節目ハンドオーバー更新の順序テンプレ化 | `.claude-handover.md` | 反映済 |
| 8 | Dev フェーズ完了直後に push 候補を提示する運用 | 運用継続 | 遵守 |
| 9 | Sonnet 化の効果検証を継続 | retro へ | retro 内に Sprint 4 / 5 / 6 比較を残す |

---

## 6. 変更ファイルサマリ（Sprint 6 全体 / 主要のみ）

新規:
- `App/AppDelegate.swift` / `App/SceneDelegate.swift` / `App/AppDependencyContainer.swift`
- `Services/Location/BatteryAdaptiveLocationPolicy.swift` / `Services/Location/RetroactiveStayDetector.swift`
- `Services/Storage/DatabaseAutoCleanupService.swift`
- `Features/Settings/DBClearView.swift` / `Features/Home/PinDetailModel.swift` / `Features/Home/PinDetailView.swift`
- `Resources/IconDesignPreview.swift` / `Resources/Assets.xcassets/AppIcon.appiconset/*`
- 新規テストファイル群（AppDelegateInitializationTests / LocationServiceLifecycleIntegrationTests / LocationServiceTaskKillResumeTests / MapViewTabSwitchTests / SLCSpaceWindowFixTests など）

更新:
- `App/GPSLoggerApp.swift` / `App/RootView.swift`
- `Services/Location/LocationService.swift` / `Services/Location/StayDetector.swift`
- `Models/AppSettings.swift`
- `Features/Map/MapView.swift` / `Features/Map/MapViewModel.swift`
- `Features/History/HistoryDetailMapContainer.swift`
- `Features/Settings/SettingsView.swift` / `Features/Settings/HomeRegistrationView.swift`
- `Resources/Info.plist`（UIApplicationSceneManifest 追加 / OAuth Client ID 維持）

---

## 7. 次スプリント方針

`sprint-retro.md` の Try ＋ Sprint 7 候補リスト（`.scrum/sprint-7/backlog.md`）で別途整理。
個人利用版リリース後の継続開発として、S7-001（XCUITest セットアップ）と S7-003（滞留中うろつきログ平滑化 / jun さんの当日フィードバック反映）を強推奨候補とする。

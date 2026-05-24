# Sprint 6 Retrospective

- 期間: 2026-05-07 〜 2026-05-24（最終スプリント）
- 結果: 23/23 Done / **個人利用版リリース GO**
- 主要メトリクス: 286/286 pass（Sprint 5 末 173 → +113 / +65%）/ warning 0 / error 0 / 実機 NG → 致命バグ追加起票 8 回（S6-010 / S6-014 / S6-015 / S6-016 / S6-017 / S6-018-021 / S6-022 / S6-023）

---

## Keep（良かったこと）

### 1. スクラム + マルチエージェント運用が機能した

- po-sm（Opus）/ dev-2（Sonnet）/ general-purpose review / qa-orchestrator の役割分担で「設計の決め事は Opus」「実装は Sonnet」「レビューは別エージェント」「品質判定は別エージェント」の構造を最後まで維持できた
- メイン代行（Opus）が xcodebuild と Info.plist の最終ガードを担うことで、Sonnet 側のサンドボックス制約に振り回されずに済んだ
- jun さんが「実機検証 + 意思決定」に集中できる導線を最後まで確保した

### 2. 構造的バグを「実機 NG → 原因特定 → 設計修正 → 再検証」のサイクルで根本解決できた

- S6-014（自宅登録 `@State` init アンチパターン）/ S6-018（UIApplicationDelegateAdaptor 欠落）/ S6-023（Battery × StayDetector 衝突）など、対症療法ではなく根本原因の設計修正で潰した
- 各致命バグ後に技術ノート（`.scrum/notes/swiftui-state-init-pitfall.md` / `swiftui-ondisappear-pitfall.md` / `slc-vs-low-power-gps.md` / `slc-wake-tracking-resume.md` / `stay-detection-robustness.md` / `qa-review-2026-05-19.md` / `qa-review-2026-05-22-final.md` 等）を残し、再発防止の knowledge を蓄積できた
- general-purpose レビューエージェントによる実装ベースの原因特定（S6-018 / S6-023）が、症状の表面だけ見て修正する罠を回避させてくれた

### 3. テスト 173 → 286 件、ライフサイクル統合テストの基盤を確立した

- 単純 mock の限界（mock manager を直接渡すスタイル）を S6-020 で `LocationServiceLifecycleIntegrationTests` として補完
- AppDelegate 経路 / SLC 起床 / pause/resume / 2 重生成保護 / Policy × StayDetector 統合 など、Sprint 5 までには無かった「ライフサイクル + サービス間相互作用」のテストカテゴリを確立した
- これが S6-023 修正の信頼性を担保した

### 4. メモリ・ハンドオーバー運用でセッション圧縮を乗り切れた

- 8 回の実機 NG → 再オープン サイクルでもセッション間の引き継ぎが破綻しなかった
- `.claude-handover.md` の節目更新 + `MEMORY.md` への要点蓄積 + `.scrum/notes/` への技術メモが効いた
- jun さんの「これ以降修正する必要がない状態」意向（2026-05-19）を Sprint 内 S6-022 として取り込めた判断は良かった

### 5. jun さんの最終フィードバック「概ね大丈夫」を Sprint 6 内で取り切った

- 個人利用版リリース GO を引き出せた
- 「うろつきログは許容範囲」と先回りで Sprint 7 候補に切り出す判断も健全

---

## Problem（課題だったこと）

### 1. **ユニットテスト pass + 実機 NG が 5 回以上発生**（最大の課題）

該当: S6-010（実機 1 回目）/ S6-014（実機 3 回目）/ S6-015（実機 4 回目）/ S6-016（実機 5 回目）/ S6-017（実機 6 回目）/ S6-018-021（実機 7 回目）/ S6-023（実機 8 回目）

- いずれも 「unit test 全 pass / warning 0 / error 0」 の状態から実機検証で致命バグが発覚
- 根本原因のカテゴリ:
  - SwiftUI ライフサイクル（`@State` init 再評価 / `.onDisappear` タブ切替発火 / `@UIApplicationDelegateAdaptor` 欠落）
  - Core Location の OS 仕様（SLC 配信距離 500m〜1km / pauses 自動 / 自動 resume 経路）
  - サービス間の相互作用（BatteryAdaptive × StayDetector）
- 単体 mock では検出できない領域が「テストカバレッジの穴」として残っていた
- S6-020 のライフサイクル統合テスト + S6-023 の本番デフォルト E2E テストでようやく構造的に潰せた

### 2. Info.plist 巻き戻しが 2 回発生（dev エージェント実行時）

- OAuth Client ID が Info.plist から消える事故が過去 2 回発生
- 都度メイン代行が手元で復元 → コミット直前に `git diff GPSLogger/Resources/Info.plist` で確認するルールで運用
- 機械的にチェックする仕組みが未整備

### 3. StayDetector の本番デフォルト（600 秒 / 100m）での End-to-End テストが無かった

- `StayDetectorTests` は短い周期（60 秒間隔 11 点）で書かれていた
- `LocationServiceLifecycleIntegrationTests` は `minDuration: 0` で書かれていた
- 本番デフォルトが組み合わさったときに「滞留中に GPS 配信が止まる」シナリオが一度もテストされていなかった
- S6-023 で初めて追加された

### 4. バッテリー最適化 × 滞留検知のロジック衝突を Sprint 5 以前で発見できなかった

- S6-005 のバッテリー最適化と S6-010 の滞留検知強化が、それぞれ単体では正しく動くが組み合わせで衝突
- 設計レビュー時点で「滞留中に distanceFilter を緩めると StayDetector の anchor 内判定が成立しなくなる」相互作用に気づけなかった
- S6-023 で「サービス間相互作用テスト」のカテゴリを明示的に追加するまで、構造的なテスト戦略が無かった

### 5. Sprint 6 は予定 9 チケット → 実際 23 チケットに拡大（+155%）

- 実機 NG 起票で +14 チケット
- planning 時点では「Sprint 5 と同等規模」と見積もったが、実機検証の発見数を読み違えた
- 期間も 2026-05-07 → 2026-05-24（18 日間 / 当初想定 7〜10 日 / +2 倍弱）
- ただし jun さんは「リリース可能になるまで Sprint 6 で潰す」意向で合意しており、スコープ拡大自体は健全な判断だった

---

## Try（次に試すこと）

### Sprint 7 で必ず試すこと

1. **【強推奨】XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件追加** → Sprint 7 S7-001
   - SwiftUI ライフサイクル + Core Location は単体 mock では再現困難
   - XCUITest なら「実際に起動 → タブ切替 → タスクキル → SLC 起床」のシナリオが書ける
   - 5 回以上発生した「unit pass / 実機 NG」を根本的に減らす唯一の手段

2. **実機相当の閾値（600 秒 / 100m）での End-to-End テストを各機能に標準で含める** → Sprint 7 S7-002
   - `test_DB_policyStoppedWithoutAnchor_normalDistanceFilter_S6023` の弱アサーション厳密化
   - 新規ロジック追加時の dev-completion-checklist に「本番デフォルト値での E2E テスト 1 件以上」を必須化

3. **Info.plist の OAuth Client ID チェックを pre-commit hook or CI で自動化** → Sprint 7 候補
   - 2 回の事故を機械的に防ぐ
   - 簡易 grep でも十分（`GIDClientID` が空でないことを確認）

4. **「滞留中の小幅うろつきログ」現象を Sprint 7 候補として記録** → Sprint 7 S7-003
   - jun さん 2026-05-24 フィードバック
   - GPS 精度誤差が `distanceFilter≤20` の高頻度配信で可視化されている
   - 地図描画平滑化 or RoutePoint の半径内マージ等で対応

### 運用として継続すること

5. メイン代行による Info.plist 最終ガード（手動でも構わない）
6. 致命バグ後の技術ノート蓄積（`.scrum/notes/`）
7. general-purpose レビューエージェントによる「実装ベース原因特定」（症状ではなく根本を見る）
8. jun さん意思決定ポイントの先回り提示（複数案 + メリデメ + 推奨）

### Sonnet 化の効果検証（Sprint 4 / 5 / 6 比較）

| 項目 | Sprint 4 | Sprint 5 | Sprint 6 |
|---|---|---|---|
| チケット数 | 〜10 | 9 | **23（拡大）** |
| テスト件数 | 〜120 | 173 | **286** |
| Dev エージェント | Sonnet | Sonnet | Sonnet（dev-2 専任） |
| 致命バグ起票回数 | 1〜2 回 | 1 回 | **8 回**（実機検証回数増 / カバレッジの穴が露呈） |
| 個人利用版リリース | × | × | **GO** |

結論: Sonnet 化はトークン消費を抑えつつ実装速度を維持できた。dev-2 専任化（dev-1 は Sprint 6 中盤以降ほぼ未使用）も「同時編集による競合リスクを下げる」効果があった。Sprint 7 以降は dev-1 / dev-2 並行起動と XCUITest 整備のバランスを再評価する。

---

## メトリクス

- 計画チケット数: **9**（planning 時点）
- 完了チケット数: **23**（実機 NG 起票で +14）
- 完了率: **100%**
- バグ検出数（実機検証フィードバック起票）: **14 件**（S6-010〜S6-017 / S6-018〜S6-021 / S6-022 P7 / S6-023）
- 残バグ: **0**（jun さん指摘「うろつきログ」は許容範囲 / Sprint 7 候補 S7-003）
- テスト追加数: **+113 件**（173 → 286 / +65%）
- フル再ビルド warning: **0**
- error: **0**
- 期間: **18 日間**（2026-05-07 〜 2026-05-24）
- リリース判定: **GO（個人利用版）**

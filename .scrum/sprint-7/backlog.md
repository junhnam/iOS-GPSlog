# Sprint 7 Backlog 候補リスト（草案 / 2026-05-24 作成）

- 作成日: 2026-05-24（Sprint 6 クローズ直後）
- ステータス: **草案**（planning 未着手 / jun さん意向次第で着手判断）
- 前提: Sprint 6 で個人利用版リリース確定 / これ以降は jun さんが「商用化判断」「継続使用」「追加機能要望」のいずれかを選んだ時点で着手

---

## 候補チケット一覧

| ID | タイトル | type | 優先度 | 見積 | 起票元 | 備考 |
|---|---|---|---|---|---|---|
| **S7-001** | XCUITest セットアップ + e2e ライフサイクル系テスト 3〜5 件追加 | test / chore | **強推奨** | M-L | Sprint 6 retro Try #1 / S6-020 提案 | unit pass + 実機 NG を構造的に減らす |
| S7-002 | StayDetectorTests の前提現実化 + S6-023 軽微留意の弱アサーション厳密化 | test | should | S-M | Sprint 6 retro Try #2 | `test_DB_policyStoppedWithoutAnchor_normalDistanceFilter_S6023` の厳密化 |
| **S7-003** | **【新規 / 2026-05-24】滞留中の小幅うろつきログ平滑化** | feature / bugfix | should | M | jun さん 2026-05-24 実機フィードバック | GPS 精度誤差が `distanceFilter≤20` の高頻度配信で可視化 / 地図描画平滑化 or RoutePoint の半径内マージ等 |
| S7-004 | P8 `didApplyRestoredRoute` 巻き戻り経路特定 | bugfix | should | M | QA レポート `.scrum/notes/qa-review-2026-05-19.md` P8 | 個人利用では非ブロッカー / 商用化前には潰したい |
| S7-005 | P6 `recentTrips(limit:)` 件数ベース取得 | refactor | could | S | QA レポート P6 | 現状は日付ベースで動作するため非ブロッカー |
| S7-006 | Dropbox 同期実装 | feature | won't（現時点） | L | CLAUDE.md 要件 / Sprint 6 で omit | jun さん明示でスコープ外 / 商用化判断時に再評価 |
| S7-007 | アイコン本番デザイン差替 | design | could | S | S6-007 設計 | jun さんが `IconDesignPreview.swift` から Xcode Preview 経由で差替可能 |
| S7-008 | 商用化判断（App Store Connect / Apple Developer Program 加入要否） | chore | could | -（要相談） | CLAUDE.md / jun さん 2026-05-06 5 項目回答 #1 | 継続使用後に判断 / 商用化決定時は別ツール再設計方針と整合 |

合計: **8 件**（強推奨 1 / should 3 / could 3 / won't 1）

---

## 優先度判定の根拠

### 強推奨（Sprint 7 最初の planning で確実に拾うべき）

- **S7-001**: Sprint 6 で 5 回以上発生した「unit pass / 実機 NG」を構造的に減らす唯一の手段。次回機能追加 or バグ修正の信頼性に直結

### Should（jun さんが Sprint 7 に踏み込むなら拾うべき）

- **S7-002**: 既存テストの精度向上。S7-001 とセットで効果が大きい
- **S7-003**: jun さん本人が許容範囲としつつも当日フィードバックで明示した現象。リリース後の体験向上に直結
- **S7-004**: 個人利用では非ブロッカーだが、商用化前には潰したい

### Could（余裕があれば）

- **S7-005**: refactor 系
- **S7-007**: jun さん自身で Xcode Preview から差替可能なため、Sprint チケット化必須ではない
- **S7-008**: jun さんの継続使用判断後

### Won't（現時点では着手しない）

- **S7-006**: jun さん明示スコープ外。商用化判断時に CloudStorageProvider 抽象化越しに再実装する

---

## Sprint 7 着手判断（jun さん意向確認待ち）

以下のいずれかに該当する場合のみ planning に進む:

1. **継続使用で追加機能要望が発生**（例: 設定追加 / UI 改善 / 他クラウド連携）
2. **商用化判断**（App Store 申請に向けた品質ベースライン整備が必要）
3. **致命バグが顕在化**（実機運用中に発覚 → 緊急 Sprint 7 として起動）

上記いずれにも該当しない場合は、Sprint 7 は **保留**（Sprint 6 完了状態を維持し、必要時に再開）。

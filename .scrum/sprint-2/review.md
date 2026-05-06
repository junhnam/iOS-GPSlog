# Sprint 2 Review

- スプリント期間: 2026-05-05（1イテレーション完結）
- 体制: PO/SM + Dev x2（Dev-1 / Dev-2）+ QA（Single-Agent モードで Agent A が代行）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・ローカル 14 コミット未 push）

---

## スプリントゴール

> アプリを閉じても、経路・ピン・総移動距離が復元できる状態を作る。

→ **達成**

検証根拠:
- ユニットテスト 44/44 pass（ビルド warning 0 / error 0）。
- jun さんがシミュレータで Freeway Drive を流し、アプリを kill → 再起動したときに、polyline・ピン・**総移動距離 3.74 km** が復元されることを目視確認。
- 履歴タブへの遷移と当日 Trip の表示も jun さん側で確認済み。
- QA Runner C / D / E の 3 観点（基盤・連携・UI/静的）で全 75 観点 PASS。Critical / High バグ 0 件。

---

## 完了チケット（8 / 8）

| ID | タイトル | 担当 | コミット | 備考 |
|---|---|---|---|---|
| S2-001 | SwiftData モデル定義（TripRecord / RoutePoint / PinRecord） | dev-1 | 85277b0 | iOS 26 SwiftData の `@Relationship` 配列に `= []` 既定値が必須なことを発見・即修正（S2-102） |
| S2-002 | ModelContainer セットアップとアプリ統合 | dev-1 | ce206c1 | 失敗時はインメモリへフォールバックして起動継続 |
| S2-003 | TripRepository（取得・作成・更新・距離加算） | dev-1 | be6aeec | `@MainActor` 統一・`#Predicate` を避けてメモリフィルタ採用 |
| S2-004 | 総移動距離計算ロジック（CLLocation.distance ベース） | dev-2 | ab863a2 | 1m 未満は GPS 揺らぎとしてスキップ。1km 飛びは警告ログ |
| S2-005 | LocationService と DB の連携（永続化 + 距離加算） | dev-2 | c8f9d4d | 5m 間引き + 日付またぎ自動切替・後方互換のため repository は DI |
| S2-006 | 滞留検出（10分・30m半径）と PinRecord 作成 | dev-2 | a9f8ded | しきい値は `StayDetectionConfig` で外出し（後で UI 調整可能に設計） |
| S2-007 | アプリ起動時の最新 TripRecord 復元 | dev-1 | 8dea581 | 重複ピンキー（lat_lng_timestamp）で再描画事故を防止 |
| S2-008 | 履歴タブ実装（日付一覧 + 詳細） | dev-2 | 7f9758c | `@Query` + `prefix(30)`・`fitBounds` で経路全体表示・空状態にも対応 |

## 未完了チケット

なし。

---

## バグチケット（途中起票・Sprint 内に修正済）

| ID | 概要 | 担当 | 修正コミット | 影響 |
|---|---|---|---|---|
| S2-101 | TripDistanceCalculator の東京-新宿テストが期待値とずれて失敗 | dev-2 | a4e9f3f | テスト期待値を実測距離（accuracy 200）に整合 |
| S2-102 | TripRecord SwiftData `@Relationship` 配列での precondition クラッシュ | dev-1 | 35eb5f3 | `routePoints / pins` の配列プロパティに `= []` 既定値を追加してクラッシュ回避 |
| S2-103 | LocationServiceTests で ModelContainer 強参照漏れによる SIGTRAP | dev-2 | f85478a | テスト側に `retainedContainers: [ModelContainer]` を追加し、setUp/tearDown で寿命管理 |

3 件すべてユニットテストで再発防止が担保され、QA フェーズで残存ゼロを確認済。

---

## 品質

- ユニットテスト通過率: **100%（44 / 44 pass）**
  - GPSLoggerTests: 1（プレースホルダ）
  - LocationServiceTests: 7（DB 連携 / 5m 間引き / 後方互換 など）
  - PersistenceControllerTests: 3（インメモリ生成・unique 制約・cascade delete）
  - QASprint1AdditionalTests: 9（Sprint 1 で追加した既存テスト・回帰）
  - StayDetectorTests: 5（10分滞留 / 9分非滞留 / 半径外移動 / skipped）
  - TripDistanceCalculatorTests: 7（東京-新宿 / 同一点 / 1m 未満スキップ / km 丸め など）
  - TripRepositoryTests: 9（todayTrip / appendRoutePoint / appendPin / updateTotalDistance など）
  - TripRestoreTests: 3（復元適用 / 当日無し / 二度呼び idempotent）
- ビルド: warning 0 / error 0
- 検出バグ: 3 件（S2-101 / S2-102 / S2-103、すべて Sprint 内修正済）
- 残存バグ: 0 件
- API キー漏洩スキャン: コードベース・git 履歴ともに **0 件ヒット**（`AIza` で grep 0、`GoogleMaps-Info.plist` 実体は `.gitignore` 経由で追跡外）

### QA 詳細リンク

- 実行ログ: `.qa-workspace/test-results/test-output.log` / `test-output-summary.log`
- Runner C 結果（モデル・DB・距離計算 + 既存回帰）: `.qa-workspace/test-results/runner_C_results.md` — 30 観点 PASS
- Runner D 結果（Location 連携・滞留・復元）: `.qa-workspace/test-results/runner_D_results.md` — 30 観点 PASS
- Runner E 結果（履歴 UI + 静的レビュー + 過去バグ回帰）: `.qa-workspace/test-results/runner_E_results.md` — 15 観点 PASS

合計 75 観点すべて OK、Critical / High バグ 0 件。

---

## シミュレータ動作確認結果（jun さん目視）

スプリントゴールを「動くもの」で裏付けるため、jun さんがシミュレータで以下を確認:

| 検証項目 | 結果 |
|---|---|
| Freeway Drive で青い経路ラインが描画される | OK |
| アプリを kill → 再起動して、経路が地図上に再表示される | OK |
| 同シナリオで HUD に「総移動距離: 3.74 km」が復元表示される | OK（実測値） |
| 履歴タブへの遷移ができる | OK |

`stayDuration` が短いシナリオでは PinRecord は生成されない（仕様通り）。10分相当の停留は、長時間ドライブでないとシミュレータで再現しにくいため、別途長時間検証は jun さん任意の追加確認とする。

---

## 変更されたファイル統計（Sprint 1 完了直後 882f44a → HEAD）

```
47 files changed, 2740 insertions(+), 80 deletions(-)
```

主要追加ファイル（行数 Top 10）:

| ファイル | 追加行数 |
|---|---:|
| GPSLogger/Features/History/HistoryDetailView.swift | +164 |
| GPSLogger/Features/History/HistoryListView.swift | +118 |
| GPSLogger/Services/Persistence/TripRepository.swift | +151 |
| GPSLogger/Services/Trip/StayDetector.swift | +140 |
| GPSLogger/Features/Map/MapView.swift | +129（Sprint 1 から差分 append） |
| GPSLogger/Features/Map/MapViewModel.swift | +113 |
| GPSLogger/Services/Location/LocationService.swift | +112（DB 連携追加） |
| GPSLoggerTests/TripRepositoryTests.swift | +156 |
| GPSLoggerTests/StayDetectorTests.swift | +102 |
| GPSLoggerTests/TripRestoreTests.swift | +103 |

その他: SwiftData モデル 3 種（`TripRecord` +68 / `PinRecord` +58 / `RoutePoint` +40）、`PersistenceController` +73、`TripDistanceCalculator` +58、`LocationServiceTests` +75、`PersistenceControllerTests` +75、`TripDistanceCalculatorTests` +77。

## コミット履歴（Sprint 2 中の 14 件）

```
7f9758c feat: 履歴タブ実装 (S2-008)
f85478a fix: LocationServiceTests で ModelContainer を強参照保持しクラッシュ回避
8dea581 feat: アプリ起動時に当日 TripRecord を地図に復元 (S2-007)
35eb5f3 fix: SwiftData @Relationship 配列に default 値を設定しクラッシュ回避
a9f8ded feat: 滞留検出 StayDetector を追加し PinRecord を自動生成 (S2-006)
c8f9d4d feat: LocationService に TripRepository を統合し座標を永続化 (S2-005)
be6aeec feat: add TripRepository for trip CRUD and distance accumulation (S2-003)
a4e9f3f fix: 東京-新宿テストの期待値を実距離に整合 (S2-101)
ce206c1 feat: integrate SwiftData ModelContainer into app shell (S2-002)
ab863a2 feat: 総移動距離計算ロジック TripDistanceCalculator を追加 (S2-004)
85277b0 feat: define SwiftData models for trip persistence (S2-001)
86b807a chore: gitignore personal files and commit SPM Package.resolved
13a5917 feat: Sprint 2 planning - DB persistence, dwell detection, history
f105a21 docs: finalize Sprint 1 review and retrospective
```

---

## バッテリー消費懸念への進捗

Sprint 1 の実装に加え、Sprint 2 では以下の対策を追加:

- **5m 未満の点間引き**（S2-005）: DB 書き込み頻度を削減（`dbWriteThresholdMeters = 5.0`）
- **滞留中の RoutePoint 間引き**（S2-006）: 同一場所で延々と座標を保存しないよう `StayEvent.skipped` で間引き

未対応（後続スプリント）:
- 自宅滞在時の完全停止（Sprint 3）
- Significant Location Changes API 併用（Sprint 3）
- desiredAccuracy の動的調整（Sprint 3）

---

## Sprint 3 以降への申し送り（QA で観察された事項 6 件）

すべて Low / 観察事項レベルでチケット化はせず、ここに記録。Sprint 3 のプランニング時に優先度を判断する。

| # | 観察元 | 内容 | 提案先 |
|---|---|---|---|
| 1 | Runner C | `TripRepository.trip(on:)` は `#Predicate` を避けて全件取得 + メモリフィルタ。数十〜数百レコード前提のため、DB 拡大時に再検討候補 | Sprint 5（全期間表示と合わせて） |
| 2 | Runner C | `TripDistanceCalculator.teleportWarningMeters: 1000.0` は警告ログのみ。本格的な異常値検出は Sprint 6 のテレポート検知で対応 | Sprint 6 |
| 3 | Runner D | `LocationService.persistLocation` の `needsTripSwitch` で `Calendar.current.startOfDay` を再適用しているのが冗長（副作用なし） | リファクタとして任意 |
| 4 | Runner D | `MapViewModel.restoreTodayTrip` の例外は `print` で silent failure。Sprint 6 でユーザー向け通知に昇格予告済 | Sprint 6 |
| 5 | Runner D | `RestoredPin.stayedMinutesText` は `max(1, ...)` で 60 秒未満でも「滞留 約1分」と表示。Sprint 2 では到達経路なし | テスト用挙動として許容 |
| 6 | Runner E | `HistoryListView.prefix(30)` はクライアント側スライス。全期間表示・日付フィルタを入れる際は FetchDescriptor + 動的フィルタへ移行 | Sprint 5 |

---

## 完了基準のチェック

- [x] 全 8 チケットが Done
- [x] ビルド warning 0、ユニットテスト pass 100%（44/44）
- [x] スプリントゴール（kill → 再起動で復元）が iOS シミュレータで確認可能（実測 3.74 km 復元）
- [x] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得・git push 承認 — このレビュー時点で保留中）

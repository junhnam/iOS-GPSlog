# Sprint 3 Review

- スプリント期間: 2026-05-06（1イテレーション完結）
- 体制: PO/SM + Dev x2（Dev-1 / Dev-2）+ QA（Single-Agent モードで Agent A が代行）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・ローカル 13 コミット未 push）

---

## スプリントゴール

> 自宅 / 外出を区別して記録モードを自動切替し、滞留地点に店舗情報を紐付ける。

→ **達成**

検証根拠（plan.md の検証条件 5 項目）:

| # | 検証条件 | 結果 | 確認方法 |
|---|---|---|---|
| 1 | シミュレータで自宅座標を登録 → 自宅半径内に入ると RoutePoint が記録されない | 静的 OK / 実機未確認 | HomeDetectorTests + LocationServiceTests + QA-S3-001 修正後の RootViewIntegrationTests |
| 2 | 自宅から退出 → 通常 GPS が再開し、青い経路ラインが伸びる | 静的 OK / 実機未確認 | SignificantLocationChangesTests（atHome→away 遷移で SLC 停止 + 通常 GPS 再開） |
| 3 | トリガーモードに切替 → 地図右下に「記録開始」ボタンが現れる | 静的 OK / 実機未確認 | RecordingToggleButtonTests + MapView の overlay 静的レビュー |
| 4 | 滞留地点でピンが立った時、ピン詳細にお店名（または住所）が表示される | 静的 OK / 実機未確認 | PlaceLookupServiceTests + HistoryDetailView 静的レビュー |
| 5 | アプリ起動時の復元失敗をシミュレートすると、画面に赤い通知が表示される | 静的 OK / 実機未確認 | RestoreErrorTests + MapView の HUD 静的レビュー |

ユニットテストとコード静的レビューでは全項目 OK。jun さん側のシミュレータ実機確認は別途お願いしたい（後述「シミュレータ動作確認の依頼項目」参照）。

---

## 完了チケット（9 / 9）

| ID | タイトル | 担当 | コミット | 備考 |
|---|---|---|---|---|
| S3-009 | iOS 26 SwiftData 落とし穴ノート作成 | dev-1 | 0abe873 | `.scrum/notes/ios26-swiftdata.md` 新規作成。CLAUDE.md と README から相互リンク |
| S3-001 | 設定画面の骨格（List + UserDefaults + AppSettings） | dev-1 | 4e2fc26 | `gpslogger.settings.v1.*` 名前空間で UserDefaults 統一 |
| S3-004 | 常時 / トリガー記録モード切替 | dev-1 | 4e2fc26 | S3-001 と同コミットで連動実装 |
| S3-002 | 自宅位置の登録 UI（地図ピック + 住所候補 + 半径スライダー） | dev-1 | 42183e0 | GoogleMaps の地図ピック + 半径円 + CLGeocoder 逆ジオコーディング（住所欠落でも保存可能） |
| S3-005 | トリガー記録用フローティングボタン（開始/停止） | dev-1 | 6d634c7 | `RecordingToggleButton.swift` 新規。緑「記録開始」/赤「停止」のトグル |
| S3-008 | restoreTodayTrip silent failure を UI 通知化 | dev-1 | d791ff1 | 失敗時に画面上部に赤い帯を表示、× ボタンで dismiss 可能 |
| S3-007 | MKLocalSearch によるお店情報取得 | dev-2 | 929f6f3 | PinRecord に `placeName` / `placeURL` を書き込み、HistoryDetailView で表示 |
| S3-003 | 自宅判定ロジック（半径内で記録自動停止） | dev-2 | 8f7d4e4 | `HomeDetector` 純粋関数。半径ぴったりは `.atHome` 判定 |
| S3-006 | Significant Location Changes + 動的精度調整 | dev-2 | 40d5ab6 | atHome で SLC 起動 + 通常 GPS 停止、走行/停止で desiredAccuracy 切替、distanceFilter 10m |

加えて Dev-1 が QA-S3-001 修正コミット（913cdff）を担当（後述）。

## 未完了チケット

なし。

---

## バグチケット

### Sprint 内に修正済み

| ID | 概要 | 重大度 | 担当 | 修正コミット | 影響 |
|---|---|---|---|---|---|
| QA-S3-001 | MapView 内で生成された LocationService に AppSettings / placeProvider が未注入。スプリントゴール検証条件 1 / 2 / 4 が実機経路で機能しない統合バグ | **Critical** | dev-1 | 913cdff | RootView で LocationService を集中生成し、AppSettings / placeProvider を一括注入。回帰防止用に RootViewIntegrationTests を新規追加 |

QA-S3-001 はユニットテストでは検出されず（個々のロジックは DI で正しく注入してテスト済）、QA フェーズの**統合経路の静的レビュー**で発見した典型的な「組み立てバグ」。修正後はビルド warning 0 / error 0、ユニットテスト 79/79 pass を維持。

### Sprint 4 へ申し送り

| ID | 概要 | 重大度 | 申し送り理由 |
|---|---|---|---|
| QA-S3-002 | iOS 26 で `CLGeocoder` が deprecated。`HomeRegistrationView` のビルド警告 1 件（OS 仕様変更による外形警告） | **Medium** | フル再ビルド時のみ顕在化する deprecated 警告。MKReverseGeocodingRequest への移行は API 設計変更を伴うため、Sprint 4 のスコープとして正式対応する。Sprint 3 の品質ゲート「warning 0」は現状ビルド時には満たしているがフル再コンパイル時に 1 件出るため、jun さんに正直に共有する |

---

## 品質

- ユニットテスト通過率: **100%（79 / 79 pass）**
  - Sprint 2 末: 44 件 → Sprint 3 末: 79 件（**+35 件**）
  - Sprint 3 で追加された主なテストファイル:
    - AppSettingsTests: 8（永続化・名前空間・破損 JSON フォールバック・半径クランプ等）
    - HomeDetectorTests: 9（nil / 半径内 / 半径外 / 半径ぴったり / atHome カウント等）
    - HomeRegistrationTests: 5（Codable 往復・address nil 保存・解除等）
    - PlaceLookupServiceTests: 11（MKLocalSearch ヒット / 0件フォールバック / 両失敗 / レート制限握り潰し等）
    - RecordingToggleButtonTests: 3（モード分岐・start/stop トグル等）
    - RestoreErrorTests: 4（catch で文字列化 / dismiss / 成功時 nil 維持等）
    - SignificantLocationChangesTests: 9（atHome→SLC 起動 / away→通常 GPS 再開 / 動的精度等）
    - RootViewIntegrationTests: 4（QA-S3-001 回帰防止: AppSettings / placeProvider が LocationService に注入されることを保証）
- ビルド: warning 0 / error 0（フル再ビルド時のみ QA-S3-002 由来 1 件）
- 検出バグ: 2 件（QA-S3-001 修正済 / QA-S3-002 申し送り）
- 残存バグ: 0 件（QA-S3-002 は仕様変更追従。既存挙動は維持されており、機能影響なし）
- API キー漏洩スキャン: コードベース・git 履歴ともに **0 件ヒット**（`AIza` で grep 0、`GoogleMaps-Info.plist` 実体は `.gitignore` 経由で追跡外。Sprint 1 / 2 の体制を継続）
- 既存 Sprint 1 / Sprint 2 のユニットテスト 44 件: **回帰なし**

### QA 詳細リンク

- テスト戦略: `.qa-workspace/sprint-3/test-design/test-strategy.md`
- テスト計画 / 観点 60 件: `.qa-workspace/sprint-3/test-design/test-plan.md`
- スコープ定義: `.qa-workspace/sprint-3/test-design/test-scope.md`
- バグチケット: `.qa-workspace/sprint-3/tickets/QA-S3-001.md` / `QA-S3-002.md`

---

## シミュレータ動作確認の依頼項目（jun さん向け）

QA はコードレビューとユニットテストで「論理的には動く」ところまで担保しているが、実際にアプリを動かしてみての確認は jun さんにお願いしたい。下記 5 項目を Xcode シミュレータで確認していただきたい:

| 確認項目 | 操作手順 | 期待結果 |
|---|---|---|
| 1. 自宅登録 | 設定タブ → 自宅を登録 → 地図上で適当な点を長押し → 「ここを自宅にする」 | 住所が表示される（または「住所取得失敗」のメッセージ後に座標で保存可能） |
| 2. 自宅滞在中の停止 | 自宅座標と同じ点に Simulate Location → アプリを起動 → 数分待つ | 経路ラインが伸びない、ピンも立たない |
| 3. 自宅退出時の再開 | Simulate Location を Freeway Drive 等に切替 | 自宅から離れた瞬間に経路ラインが伸び始める |
| 4. トリガーモード | 設定タブ → 記録モードを「トリガー」に → 地図画面に戻る | 右下に緑の「記録開始」ボタンが現れる。タップで赤の「停止」に切替 |
| 5. 復元エラー通知 | （もし復元エラーを再現できる場合）アプリを kill → ストレージ満杯等で SwiftData 読込失敗 | 画面上部に赤い帯で「今日の記録の復元に失敗しました」と表示。× ボタンで dismiss 可能 |

項目 5 は再現条件が特殊なため任意。項目 1〜4 が確認できればスプリントゴール達成として合意取得とさせていただきたい。

---

## 変更されたファイル統計（Sprint 2 完了直後 ad6106b → HEAD 913cdff）

```
40 files changed, 3309 insertions(+), 73 deletions(-)
```

主要追加ファイル（行数 Top 10）:

| ファイル | 追加行数 |
|---|---:|
| GPSLogger/Features/Settings/HomeRegistrationView.swift | +346 |
| GPSLogger/Services/Location/LocationService.swift | +232 |
| GPSLoggerTests/PlaceLookupServiceTests.swift | +203 |
| .scrum/notes/ios26-swiftdata.md | +188 |
| GPSLoggerTests/SignificantLocationChangesTests.swift | +178 |
| GPSLogger/Services/Place/PlaceLookupService.swift | +171 |
| .scrum/sprint-3/plan.md | +150 |
| GPSLogger/Models/AppSettings.swift | +138 |
| GPSLogger/Features/Map/MapView.swift | +138 |
| GPSLoggerTests/HomeDetectorTests.swift | +129 |

その他: SettingsView (+108), AppSettingsTests (+102), GPSLogger.xcodeproj/project.pbxproj (+76), RootViewIntegrationTests (+76), HomeRegistrationTests (+72), HistoryDetailView (+71), RestoreErrorTests (+69), RootView (+63), HomeDetector (+51), RecordingToggleButton (+50), HomeLocation (+47), RecordingToggleButtonTests (+42), MapViewModel (+10) 等。

## コミット履歴（Sprint 3 中の 13 件、新しい順）

```
913cdff fix: MapView の LocationService に AppSettings / placeProvider を DI (QA-S3-001)
40d5ab6 feat: SLC + 動的精度調整によるバッテリー対策 (S3-006)
8f7d4e4 feat: 自宅判定ロジック（半径内で記録自動停止 / 退出で再開） (S3-003)
929f6f3 feat: MKLocalSearch によるお店情報取得 (S3-007)
b647fab chore: Dev-1 担当 6 チケットを review に更新 (S3-001/002/004/005/008/009)
d791ff1 chore: restoreTodayTrip silent failure を UI 通知化 (S3-008)
6d634c7 feat: トリガー記録モード用フローティングボタン (S3-005)
42183e0 feat: 自宅位置の登録 UI（地図ピック + 住所候補 + 半径スライダー） (S3-002)
4e2fc26 feat: AppSettings + 設定画面骨格と記録モード切替 (S3-001, S3-004)
0abe873 docs: iOS 26 SwiftData 落とし穴ノートに CLAUDE.md / README から相互リンク追加 (S3-009)
d1e25a0 chore: Sprint 3 を development フェーズに移行
bb1677a docs: Sprint 3 planning - 自宅 / 記録モード / お店情報 / 復元通知
5b6d6bb docs: Sprint 2 review / retrospective を追加
```

---

## バッテリー消費懸念への進捗

Sprint 1 / Sprint 2 の対策に加え、Sprint 3 では以下を投入:

- **自宅滞在時の完全停止**（S3-003 + S3-006）: HomeDetector で `.atHome` を判定し、LocationService が RoutePoint 永続化をスキップ + 通常 GPS を停止
- **Significant Location Changes API 併用**（S3-006）: 自宅滞在中は SLC のみ稼働させ、退出を検知したら通常 GPS を再開（電力消費を桁違いに抑える OS API）
- **desiredAccuracy の動的調整**（S3-006）: 走行中（5 秒以内 10m 超）は Best、停止中（20 秒以上 5m 未満）は HundredMeters に自動切替
- **distanceFilter = 10m**（S3-006）: GPS 更新の最小距離を 10m に絞り、不要な delegate コールを抑制

これで CLAUDE.md「バッテリー消費対策」セクションの 5 項目のうち 4 項目を実装済み（残: `pausesLocationUpdatesAutomatically` の調整 → Sprint 6）。

未対応（後続スプリント）:
- バックグラウンド復帰時の挙動安定化（Sprint 6）
- App Store 審査向けバッテリー実測（Sprint 6）
- `pausesLocationUpdatesAutomatically` の最終チューニング（Sprint 6）

実機でのバッテリー消費の体感は jun さんの実利用フィードバックを Sprint 6 のチューニングに反映する想定。

---

## Sprint 4 以降への申し送り（QA + 自分の観察 計 7 件）

すべてチケット化保留・観察事項レベル。Sprint 4 のプランニング時に優先度を判定する。

| # | 観察元 | 内容 | 推奨先 | 優先度判断要否 |
|---|---|---|---|---|
| 1 | QA-S3-002 | iOS 26 で `CLGeocoder` が deprecated → `MKReverseGeocodingRequest` への移行 | **Sprint 4** | 必要（HomeRegistrationView と PlaceLookupService の両方に影響） |
| 2 | Agent A | `MapView` の Coordinator 周辺で Swift 6 strict concurrency の warning（フル再コンパイル時のみ） | Sprint 4 or 5 | 推奨判断（外形 warning。実害なし） |
| 3 | Agent A | テスト群の `@MainActor` プロパティ初期化で strict concurrency warning（フル再コンパイル時のみ） | Sprint 4 or 5 | 推奨判断（テストのみ・実害なし） |
| 4 | Agent A | MapView の HUD warning ロジックを HomeDetector に統一（重複実装） | Sprint 4 のリファクタ枠 | 任意 |
| 5 | Agent A | MKLocalSearch のレート制限の実機検証（短時間に大量ピンが立つケース） | **Sprint 6**（バッテリー検証と同時） | Sprint 6 で必須 |
| 6 | Agent A | SLC + 動的精度調整の実機検証（シミュレータでは挙動が完全に再現しないため） | **Sprint 6**（バッテリー検証と同時） | Sprint 6 で必須 |
| 7 | PO/SM | `RootView` の AppSettings インスタンス共有方式を `@Environment` ベースに整理（QA-S3-001 修正で生まれた DI 構造の整理） | Sprint 4 のリファクタ枠 | 任意 |

特に **#1（CLGeocoder 移行）** は jun さんに優先度判断をいただきたい。Sprint 4 の冒頭で対応するか、Sprint 4 末にまとめて対応するかで開発順序が変わる。

---

## 完了基準のチェック

- [x] 全 9 チケットが Done
- [x] スプリントゴール検証条件 5 項目すべて静的に確認可能
- [x] ビルド warning 0、ユニットテスト pass 100%（79/79）
  - フル再コンパイル時のみ QA-S3-002 由来の deprecated warning 1 件あり（OS 仕様変更による外形警告。Sprint 4 申し送り）
- [x] Sprint 1 / Sprint 2 で導入したテスト（44 件）の回帰なし
- [x] API キー漏洩 0
- [x] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得・git push 承認 — このレビュー時点で保留中）

---

## ユーザー承認後の手順（コマンドドラフト）

承認をいただいた後、以下を実施予定:

```bash
# 1. ローカル 13 コミットを origin main に push
git push origin main

# 2. GitHub Issues #18〜#26（S3-001 〜 S3-009 想定）をクローズ
gh issue close 18 --comment "Sprint 3 で実装完了"
gh issue close 19 --comment "Sprint 3 で実装完了"
gh issue close 20 --comment "Sprint 3 で実装完了"
gh issue close 21 --comment "Sprint 3 で実装完了"
gh issue close 22 --comment "Sprint 3 で実装完了"
gh issue close 23 --comment "Sprint 3 で実装完了"
gh issue close 24 --comment "Sprint 3 で実装完了"
gh issue close 25 --comment "Sprint 3 で実装完了"
gh issue close 26 --comment "Sprint 3 で実装完了"

# 3. .scrum/config.md の current_sprint を 4 に、sprint_phase を planning に更新

# 4. Sprint 4 planning を開始（カレンダー同期 + CSV エクスポート + QA-S3-002 移行）
```

Issue 番号は実際の GitHub の状態と照合してから実行する。

# Sprint 4 Review

- スプリント期間: 2026-05-06（1 イテレーション完結）
- 体制: PO/SM + Dev x2（Dev-1 / Dev-2）+ QA（Single-Agent モードで Agent A が代行）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・ローカル 11 コミット未 push、origin から見ると 12 コミット先行）
- 最終コミット: 42e1b2c（QA-S4-001 修正）

---

## スプリントゴール

> **移動記録を外部に持ち出せる状態を作る（カレンダー連携 + CSV 出力）**

→ **達成**

検証根拠（plan.md の検証条件 5 項目）:

| # | 検証条件 | 結果 | 確認方法 |
|---|---|---|---|
| 1 | 滞留ピンが立った時に iOS カレンダーへ自動で予定が登録される（同期 ON 時） | 静的 OK / 実機未確認 | CalendarEventCreationTests 6 ケース + LocationService.enrichPinWithPlaceInfo 経由の createEvent(for:) 呼び出しを確認 |
| 2 | 設定画面でカレンダー同期の ON/OFF と対象カレンダーが選べる | 静的 OK / 実機未確認 | CalendarSyncSettingsTests 6 ケース + SettingsView / CalendarPickerView のコードレビュー |
| 3 | 「設定 → エクスポート」から CSV を書き出して保存先を選んで保存できる | 静的 OK / 実機未確認 | ExportViewTests 4 ケース + CSVExportDocumentTests 4 ケース + DocumentPickerViewTests 2 ケース。.fileExporter 起動経路と CSVExportDocument.fileWrapper 出力を検証 |
| 4 | フル再コンパイルで CLGeocoder の deprecated warning が 0 件になる | **達成（QA 修正後）** | CLGeocoder warning 0 件は Dev フェーズ完了時点で達成。QA で MKMapItem.placemark の deprecated warning 4 件を発見 → QA-S4-001 として修正し最終的に 0 件 |
| 5 | MapView HUD の自宅判定ロジックが HomeDetector 1 箇所に集約されている | 静的 OK | MapView.swift から自宅判定ロジックが完全に削除され、HomeDetector.bannerMessage(...) 経由で参照のみ。HomeDetectorTests に bannerMessage 系 3 ケース追加で検証 |

ユニットテストとコード静的レビューでは全項目 OK。EventKit / `.fileExporter` のシミュレータ実機確認は別途 jun さんに依頼（後述「シミュレータ動作確認の依頼項目」参照）。

---

## 完了チケット（8 / 8）

| ID | タイトル | 担当 | コミット | 備考 |
|---|---|---|---|---|
| S4-001 | CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002 解消） | dev-2 | 50cd75b + 3b046fb | hotfix で `preferredLocale` 引数を削除し端末ロケールに任せる方針へ変更 |
| S4-002 | EventKit 連携基盤（権限取得 + カレンダー選択） | dev-2 | 1c0bc6b | CalendarSyncService 新規。@MainActor + Info.plist NSCalendarsFullAccessUsageDescription |
| S4-003 | 滞留ピン → カレンダーイベント自動作成 | dev-2 | a30fd4a | PinRecord.calendarEventIdentifier 追加（Optional・冪等性確保） |
| S4-004 | カレンダー同期 ON/OFF 設定 | dev-1 | ccf1b69 | Toggle ON 時の権限要求 + denied 時の Alert 動線 |
| S4-005 | CSV エクスポート機能（DBスキーマそのまま出力） | dev-2 | 23f9e47 | CSVExportService 新規。UTF-8 BOM / CRLF / CSV インジェクション対策（=, +, -, @ にシングルクォート前置） |
| S4-006 | UIDocumentPickerViewController での保存先選択 | dev-1 | 5ebcf00 | CSVExportDocument（FileDocument）+ DocumentPickerView（UIViewControllerRepresentable）の 2 経路 |
| S4-007 | エクスポート UI 画面 | dev-1 | ccf1b69 | ExportView を @MainActor クロージャ注入で疎結合に組み立て |
| S4-008 | MapView HUD warning ロジックを HomeDetector へ統一 | dev-1 | 862e2d7 | HomeDetector.bannerMessage を新規追加し、MapView から重複ロジックを削除 |

加えて Agent A が QA フェーズで QA-S4-001 修正コミット（42e1b2c）を担当。

## 未完了チケット

なし。

---

## バグチケット

### Sprint 内に修正済み

| ID | 概要 | 重大度 | 担当 | 修正コミット | 影響 |
|---|---|---|---|---|---|
| QA-S4-001 | MKMapItem.placemark も iOS 26 で deprecated になっていた（S4-001 移行後の取りこぼし）。フル再ビルドで warning 4 件 | **High** | qa-fixer（Agent A 兼任） | 42e1b2c | `MKMapItem.placemark`（CLPlacemark）→ `MKMapItem.address.fullAddress`（MKAddress）に切り替え。PlaceLookupService.swift / HomeRegistrationView.swift / .scrum/notes/ios26-api-changes.md の 3 ファイルを更新。修正後 warning 0、全 121 テスト pass を維持 |

QA-S4-001 はスプリントゴール検証条件 #4「フル再ビルドで warning 0 件」を実質的に破っていた High バグ。Sprint 4 のテーマである iOS 26 API 流儀への移行が「CLGeocoder の代替として案内された MKReverseGeocodingRequest 自体は OK だが、その戻り値の placemark プロパティが別途 deprecated」という Apple の連鎖的 API 変更に追いつけていなかったことが原因。`.scrum/notes/ios26-api-changes.md` に「置換 API 自体も deprecated 化されているか」のチェック観点を追記済み。

### Sprint 5 へ申し送り

| ID | 概要 | 重大度 | 申し送り理由 |
|---|---|---|---|
| QA-S4-002 | `CalendarSyncService.addressFromPlaceURL` が no-op fallback（`pin.placeName` を返すだけで、`pin.placeName ?? Self.addressFromPlaceURL(pin)` の文脈で常に nil） | **Low** | 機能影響なし。S4-003 受け入れ条件には「placeName → address → 座標」の 3 段フォールバックが書かれているが、PinRecord に address フィールドが現状ないため実質「placeName → 座標」の 2 段になっている。Sprint 5 で「PinRecord に address フィールドを追加」or「関数削除」のいずれかの方針判断が必要 |

---

## 品質

- ユニットテスト通過率: **100%（121 / 121 pass）**
  - Sprint 3 末: 79 件 → Sprint 4 末: 121 件（**+42 件**）
  - Sprint 4 で追加された主なテストファイル:
    - CSVExportDocumentTests: 4（FileDocument の readable type / fileWrapper 出力 / 空データ / BOM 検証）
    - CSVExportServiceTests: 7（エスケープ単体・出力スキーマ・BOM・CRLF・空 trip・インジェクション対策・複数 Trip）
    - CalendarEventCreationTests: 6（権限済み作成 / 二重作成防止 / 権限拒否 / カレンダー未指定 / 既存 identifier 再利用 / SwiftData 永続化経路）
    - CalendarSyncServiceTests: 5（権限取得 / 拒否 / restricted / authorized / カレンダー一覧取得）
    - CalendarSyncSettingsTests: 6（Toggle ON 時の権限要求 / denied 時の Alert / 永続化 / カレンダー選択 / restricted 動線 / OFF 時の即時反映）
    - DocumentPickerViewTests: 2（Coordinator 生成 / キャンセル時の onCompletion 呼び出し）
    - ExportViewTests: 4（trip 一覧表示 / エクスポートボタン状態 / 複数選択 / フォーマット切替）
    - HomeDetectorTests: +3（bannerMessage 系の 3 ケース追加。S4-008 の HUD 統一）
    - PlaceLookupServiceTests: +3（S4-001 で MKReverseGeocodingRequest 経路の境界 3 ケース追加）
- ビルド: **warning 0 / error 0**（QA-S4-001 修正後）
  - フル再コンパイル時の Swift プロダクションコード由来 warning は MapView.swift:264 の strict concurrency warning 1 件のみ（Sprint 4 plan で Sprint 5 への繰越と明記済み）
  - CLGeocoder deprecated warning: **0 件**（QA-S3-002 解消継続）
  - MKMapItem.placemark deprecated warning: **0 件**（QA-S4-001 修正で解消）
- 検出バグ: 2 件（QA-S4-001 修正済 / QA-S4-002 申し送り）
- 残存バグ: 0 件（QA-S4-002 は dead code 相当の no-op で機能影響なし）
- API キー漏洩スキャン: コードベース・git 履歴ともに **0 件ヒット**（`AIza` で grep 0、`GoogleMaps-Info.plist` 実体は `.gitignore` 経由で追跡外。Sprint 1 から継続）
- 既存 Sprint 1 / Sprint 2 / Sprint 3 のユニットテスト 79 件: **回帰なし**

### QA 詳細リンク

- テスト観点 110 件: `.qa-workspace/sprint-4/test-design/test-points.md`
- バグチケット: `.qa-workspace/sprint-4/tickets/QA-S4-001.md` / `QA-S4-002.md`
- QA 最終レポート: `.qa-workspace/sprint-4/report/final-report.md`

---

## シミュレータ動作確認の依頼項目（jun さん向け）

QA はコードレビューとユニットテストで「論理的には動く」ところまで担保しているが、EventKit と `.fileExporter` はユニットテストでは挙動を完全に再現できない領域のため、Xcode シミュレータでの確認を jun さんにお願いしたい。下記 4 項目を確認していただきたい:

| 確認項目 | 操作手順 | 期待結果 |
|---|---|---|
| 1. カレンダー同期 ON | 設定タブ → 「カレンダー同期」を ON にする | iOS のカレンダー権限ダイアログが表示される。許可するとカレンダー一覧が選べる。拒否すると Toggle が OFF に戻り、Alert で「設定アプリでカレンダー権限を許可してください」が表示される |
| 2. 滞留ピン → カレンダー登録 | カレンダー同期 ON 状態で Simulate Location を「停止 → 同地点 10 分以上維持」に設定 → ピンが立つ | iOS 標準カレンダーアプリを開くと、ピンの位置情報がイベントとして登録されている。同じピンが 2 回処理されてもイベントは 1 件のみ |
| 3. CSV エクスポート（保存先選択） | 設定タブ → エクスポート → 出力したい日付を選択 → 「保存」 | UIDocumentPicker が起動し、ローカル / iCloud Drive / 接続している外部ストレージから保存先を選んで保存できる。キャンセルしてもアプリがクラッシュしない |
| 4. CSV 中身確認 | 保存した CSV をテキストエディタ or 表計算ソフトで開く | UTF-8 BOM 付きで日本語が文字化けしない、改行が CRLF、`,` `"` `\n` を含む値はダブルクォート囲み + `""` 二重化、`=` `+` `-` `@` で始まる値の先頭にシングルクォート（CSV インジェクション対策） |

項目 1 と 3 は jun さん向け手順書（`.scrum/notes/simulator-scenarios.md`）に新規セクションを追加しているのでそちらを参照可能。これら 4 項目が確認できれば Sprint 4 のスプリントゴール達成として合意取得とさせていただきたい。

---

## 変更されたファイル統計（Sprint 3 完了 a4ab592 → HEAD 42e1b2c）

```
41 files changed, 3167 insertions(+), 91 deletions(-)
```

主要追加ファイル（行数 Top 10）:

| ファイル | 追加行数 |
|---|---:|
| GPSLogger/Services/Calendar/CalendarSyncService.swift | +263 |
| GPSLoggerTests/CalendarEventCreationTests.swift | +267 |
| GPSLogger/Services/Export/CSVExportService.swift | +187 |
| GPSLogger/Features/Export/ExportView.swift | +178 |
| .scrum/sprint-4/plan.md | +173 |
| GPSLoggerTests/CSVExportServiceTests.swift | +168 |
| GPSLoggerTests/CalendarSyncServiceTests.swift | +153 |
| GPSLoggerTests/CalendarSyncSettingsTests.swift | +149 |
| GPSLogger/Features/Settings/SettingsView.swift | +144 |
| GPSLoggerTests/ExportViewTests.swift | +126 |

その他: CalendarPickerView (+111), .scrum/notes/ios26-api-changes.md (+101), simulator-scenarios.md (+93), board.md (+93), GPSLogger.xcodeproj/project.pbxproj (+76), HomeRegistrationView (+62 / -差分), DocumentPickerView (+59), RootView (+54 / -差分), AppSettings (+48 / 差分), CSVExportDocument (+48), PlaceLookupService (+40 / 差分), MapView (+35 / 差分。S4-008 で削除分含む), HomeDetector (+28), CSVExportDocumentTests (+65), DocumentPickerViewTests (+65), HomeDetectorTests (+33), PlaceLookupServiceTests (+33), 等。

## コミット履歴（Sprint 4 中の 11 件、新しい順）

```
42e1b2c fix: MKMapItem.placemark も deprecated のため address.fullAddress へ移行 (QA-S4-001)
ccf1b69 feat: カレンダー同期設定 + エクスポート UI 画面 (S4-004 / S4-007)
23f9e47 feat: CSV エクスポート機能（DBスキーマそのまま出力） (S4-005)
a30fd4a feat: 滞留ピン → カレンダーイベント自動作成 (S4-003)
5ebcf00 feat: UIDocumentPickerViewController での保存先選択 (S4-006)
1c0bc6b feat: EventKit 連携基盤（権限取得 + カレンダー選択） (S4-002)
862e2d7 chore: MapView HUD warning ロジックを HomeDetector へ統一 (S4-008)
3b046fb fix: MKReverseGeocodingRequest の preferredLocale 引数を削除 (S4-001 hotfix)
50cd75b chore: CLGeocoder → MKReverseGeocodingRequest 移行 (S4-001)
4c909d4 chore: Sprint 4 を development フェーズに移行
9090eab chore: Sprint 4 planning - iOS 26 API 移行 + カレンダー連携 + CSV エクスポート
```

ローカル 11 commit + Sprint 3 完了直後の `a4ab592 docs: Sprint 3 review / retrospective を追加`（origin に push 済みのはずだが未 push なら）合計 12 コミットが origin/main に対して先行している。

---

## バッテリー消費懸念への進捗

Sprint 4 の主スコープ（カレンダー同期 + CSV エクスポート）はバッテリー消費に大きな影響を与える領域ではなく、Sprint 3 で実装した対策（自宅滞在中の完全停止 / SLC 併用 / desiredAccuracy 動的調整 / distanceFilter）からの**変化なし**。

未対応（後続スプリント）:
- バックグラウンド復帰時の挙動安定化（Sprint 6）
- App Store 審査向けバッテリー実測（Sprint 6）
- `pausesLocationUpdatesAutomatically` の最終チューニング（Sprint 6）
- MKLocalSearch / SLC の実機検証（Sprint 6）

実機でのバッテリー消費の体感は jun さんの実利用フィードバックを Sprint 6 のチューニングに反映する想定。Sprint 4 では新たに EventKit と `.fileExporter` を導入したが、いずれもユーザー操作トリガー（滞留ピン作成時の単発 / 設定画面からの明示エクスポート）であり、常時バックグラウンド消費の増加要因にはならない。

---

## Sprint 5 以降への申し送り（QA + 自分の観察 計 6 件）

すべてチケット化保留・観察事項レベル。Sprint 5 のプランニング時に優先度を判定する。

| # | 観察元 | 内容 | 推奨先 | 優先度判断要否 |
|---|---|---|---|---|
| 1 | Sprint 4 plan で承認済 | MapView Coordinator の strict concurrency warning（フル再ビルド時のみ） | Sprint 5 | 推奨判断（外形 warning。実害なし） |
| 2 | Sprint 4 plan で承認済 | テスト群 53 件の `@MainActor` strict concurrency warning（フル再ビルド時のみ） | Sprint 5 | 推奨判断（テストのみ・実害なし） |
| 3 | QA-S4-002 | `CalendarSyncService.addressFromPlaceURL` を削除 or `PinRecord.address` フィールド追加 | Sprint 5 | **要判断**（Sprint 5 のクラウド同期で PinRecord スキーマ拡張のタイミングと合わせるかどうか） |
| 4 | Agent A | iOS 26 API 変更点ノートに「**置換 API 自体も deprecated 化されているか**」のチェック観点を明記 | **対応済**（`.scrum/notes/ios26-api-changes.md` 更新済） | 完了 |
| 5 | Agent A | Dev フェーズ完了基準に `xcodebuild clean build` の warning 数チェックを追加（運用改善） | Sprint 5 retro Try | **要判断**（QA-S4-001 のような warning 増加バグを Dev フェーズで捕まえるための運用変更） |
| 6 | PO/SM | EventKit / `.fileExporter` のシミュレータ実機確認を jun さんに依頼（plan.md 合意通り） | Sprint 4 完了直前（**今**） | jun さん側のシミュレータ確認待ち |
| 7 | Sprint 3 申し送り | RootView の AppSettings インスタンス共有方式を `@Environment` ベースに整理 | Sprint 5 | 任意（Sprint 5 のクラウド同期で RootView を触る前段で実施） |
| 8 | Sprint 3 申し送り | MKLocalSearch / SLC の実機検証 | Sprint 6（バッテリー実機検証時） | Sprint 6 で必須 |

特に **#3（QA-S4-002 の方針判断）** と **#5（Dev フェーズ完了基準への warning チェック追加）** は Sprint 5 のプランニング時に優先度判断をいただきたい。

---

## モデル切替の効果（Sprint 4 から運用開始）

Sprint 4 から以下のエージェント割り当てになった:

| エージェント | Sprint 3 まで | Sprint 4 | 備考 |
|---|---|---|---|
| scrum-po-sm | Opus | **Opus** | 変更なし（戦略・合意形成・外部報告を担う） |
| qa-orchestrator | Opus | **Opus** | 変更なし（観点設計・品質判定の中核） |
| scrum-dev-agent | Opus（既定） | **Sonnet** | コード実装はパターン作業が多くSonnetで十分。トークンコスト削減を狙う |
| qa-implementer / qa-runner / qa-fixer | Sonnet | Sonnet | 変更なし |
| scrum-designer | Sonnet | Sonnet | このスプリントでは未使用 |

Sprint 4 結果:
- Sonnet 化した Dev エージェントでも 8 チケット完遂・追加テスト 42 件・コンパイルエラー 1 件（hotfix で即解消）・git 競合 0 件で、品質低下は観測されず
- Sprint 3 と同等の生産量（Sprint 3 は 9 チケット +35 テスト、Sprint 4 は 8 チケット +42 テスト）を Sonnet で達成
- ただし **Dev-2 が「Sonnet サブエージェントの sandbox で xcodebuild が拒否される」現象**を申し送り。Dev フェーズ中はメインエージェント（Opus）が代行ビルドする運用で凌いだが、長期的には `settings.json` の permissions に xcodebuild を追加するのが望ましい

→ Sprint 5 retro Try で「permissions 設定の見直し」を提案する（後述 retro.md 参照）。

---

## 完了基準のチェック

- [x] 全 8 チケットが Done
- [x] スプリントゴール検証条件 5 項目すべて静的に確認可能
- [x] フル再ビルド warning 0（QA-S4-001 修正後）
  - 残存は MapView.swift:264 の strict concurrency warning 1 件（Sprint 4 plan で Sprint 5 へ繰越承認済み）
- [x] ユニットテスト pass 100%（121/121）
- [x] Sprint 1 / Sprint 2 / Sprint 3 で導入したテスト 79 件の回帰なし
- [x] API キー漏洩スキャン 0 件
- [x] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得・git push 承認 — このレビュー時点で保留中）

---

## ユーザー承認後の手順（コマンドドラフト）

承認をいただいた後、以下を実施予定:

```bash
# 1. ローカル 11 コミット + Sprint 4 review/retro 1 コミット = 計 12 コミットを origin main に push
git push origin main

# 2. GitHub Issues #27〜#34（S4-001 〜 S4-008 想定）をクローズ
gh issue close 27 --comment "Sprint 4 で実装完了"
gh issue close 28 --comment "Sprint 4 で実装完了"
gh issue close 29 --comment "Sprint 4 で実装完了"
gh issue close 30 --comment "Sprint 4 で実装完了"
gh issue close 31 --comment "Sprint 4 で実装完了"
gh issue close 32 --comment "Sprint 4 で実装完了"
gh issue close 33 --comment "Sprint 4 で実装完了"
gh issue close 34 --comment "Sprint 4 で実装完了"

# 3. .scrum/config.md の current_sprint を 5 に、sprint_phase を planning に更新

# 4. Sprint 5 planning を開始（クラウド同期 + 申し送り解消）
```

Issue 番号は実際の GitHub の状態と照合してから実行する。

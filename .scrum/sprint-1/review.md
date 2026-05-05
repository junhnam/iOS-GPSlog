# Sprint 1 Review

- スプリント期間: 2026-05-05（1イテレーション完結）
- 体制: PO/SM + Dev x2 + Designer + QA（Single-Agent モードで Agent A が代行）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・ローカル 14 コミット未 push）

---

## スプリントゴール

> iOS シミュレータ上で、現在地を地図に表示し、移動経路を青いラインで描画できる状態を作る。

→ **達成**

検証根拠:
- `xcodebuild` で `** BUILD SUCCEEDED **`（warning 0 / error 0）。GoogleMaps SDK の SPM 解決も成功。
- ユニットテスト 14/14 pass（既存 5 + Sprint 1 QA で追加した 9）。
- 静的レビューで MapView / LocationService / Polyline 描画ロジックがチケット要件をすべて満たすことを確認。
- 残課題は jun さん側での「実機シミュレータでの目視確認（Freeway Drive で青ライン描画）」のみ。

---

## 完了チケット（9 / 9）

| ID | タイトル | 担当 | コミット | 備考 |
|---|---|---|---|---|
| S1-001 | Xcode プロジェクト雛形作成 (SwiftUI / iOS 26+) | dev-1 | 3922c81 | XcodeGen 採用で .pbxproj 競合を回避 |
| S1-002 | Swift Package Manager 設定 + Google Maps SDK 導入 | dev-1 | 3948feb | API キーは env / plist の二段読みで安全化 |
| S1-003 | Info.plist に位置情報・バックグラウンド権限を設定 | dev-1 | 5992d54 | `WhenInUse` / `Always` 両方の日本語説明文を整備 |
| S1-004 | アプリエントリポイント + ナビゲーション骨格 | dev-1 | f0db7ec | TabView（地図 / 履歴 / 設定）+ アクセシビリティラベル |
| S1-005 | LocationManager サービス実装 | dev-2 | 6f5ea2e | `@MainActor` + DI 設計、Swift 6 strict concurrency 対応 |
| S1-006 | Google Maps ビュー（現在地表示） | dev-2 | 4b121b0 | `UIViewRepresentable` で SwiftUI に統合、myLocationButton/compass 有効 |
| S1-007 | 移動経路ライン描画（Polyline） | dev-2 | 4b121b0 | #1E88E5 / 5pt、差分 append 描画で再描画コスト削減 |
| S1-008 | メイン画面 UI モック作成 | designer | 52240de | Light/Dark プレビュー、トークン化（色・余白・角丸）済 |
| S1-009 | README にビルド・実行手順を追記 | dev-1 | 592c764 | 初回セットアップ / API キー取得 / Freeway Drive 手順網羅 |

## 未完了チケット

なし。

## 持ち越し（Sprint 2 以降への申し送り）

| 項目 | 内容 | 重要度 | 提案先スプリント |
|---|---|---|---|
| MainScreenMock の PNG エクスポート | Designer が当環境で Xcode Canvas を実行できなかったため、Light/Dark の PNG 画像 2 枚が `Design/Mockups/` に未添付。手順は S1-008 のチケットコメントに記載済 | Low | jun さん側で実施（タイミングは任意） |
| Coordinator.applyRoute の単体テスト | `GMSMutablePath` が UIKit 依存でユニットテスト化が難しく、静的レビューで担保した | Low | Sprint 2（経路の DB 永続化と合わせて UI テスト戦略を再検討） |
| `.qa-workspace/` の `.gitignore` 追加 | QA 中の発見 (TICKET_001, Low)。Agent F が `.gitignore` に追記済（コミット未実施） | Low | Sprint 1 の git push 直前に同梱コミットを作るか、Sprint 2 冒頭に処理 |

---

## 品質

- ユニットテスト通過率: **100%（14 / 14 pass）**
  - 既存 5 件: `LocationServiceTests` 4 件 + プレースホルダ 1 件
  - 追加 9 件: `QASprint1AdditionalTests`（API キー読み込み 3 件 + LocationService 冪等性 3 件 + 経路間引きパターン 2 件 + alternating 1 件）
- ビルド: warning 0 / error 0
- 検出バグ: 1 件（TICKET_001 Low — `.qa-workspace/` の `.gitignore` 漏れ）
- 残存バグ: 0 件（TICKET_001 は修正済、コミット未実施）
- API キー漏洩スキャン: コードベース・git 履歴ともに 0 件ヒット

### QA 詳細リンク
- 実行ログ: `.qa-workspace/test-results/build-output.log` / `test-output.log` / `test-output-additional.log`
- Runner C 結果（基盤・ビルド・セキュリティ）: `.qa-workspace/test-results/runner_C_results.md`（9 観点 PASS）
- Runner D 結果（位置情報・地図）: `.qa-workspace/test-results/runner_D_results.md`（13 観点 PASS）
- Runner E 結果（モック・ドキュメント）: `.qa-workspace/test-results/runner_E_results.md`（8 観点 PASS）
- バグチケット: `.qa-workspace/tickets/TICKET_001_low.md`

---

## 変更されたファイル統計（初期コミット → HEAD）

```
24 files changed, 1392 insertions(+), 58 deletions(-)
```

主要追加ファイル（行数 Top）:
| ファイル | 追加行数 |
|---|---:|
| GPSLogger/Design/Mockups/MainScreenMock.swift | +449 |
| README.md | +171 |
| GPSLogger/Tests/QASprint1AdditionalTests.swift | +149 |
| GPSLogger/Features/Map/MapView.swift | +132 |
| GPSLogger/Services/Location/LocationService.swift | +130 |
| RootView.swift | +98（書き換え含む） |
| GPSLogger.xcodeproj/project.pbxproj | +60 |
| GPSLoggerTests/LocationServiceTests.swift | +56 |
| project.yml | 修正 32 行 |

その他: `.gitignore` / `Info.plist` / `GoogleMaps-Info.plist.example` / `GoogleMapsConfiguration.swift` を新規追加。

## コミット履歴（Sprint 1 中の 14 件）

```
4bb670d chore: advance sprint phase to review after QA pass
25cf8bc test: add Sprint 1 QA additional unit tests
b7612e8 docs: mark S1-009 as Done in sprint-1 board
fc3978b docs: fill in S1-005/006/007 commit hashes in sprint-1 board
592c764 docs: expand README with full setup, build, and simulator GPS test guide (S1-009)
4b121b0 feat: add Google Maps view with route polyline (S1-006, S1-007)
6f5ea2e feat: add LocationService wrapping CLLocationManager (S1-005)
f0db7ec feat: replace RootView with TabView navigation skeleton (S1-004)
3dc142a docs: fill in S1-008 commit hash in sprint-1 board
52240de design: メイン画面UIモック追加 (S1-008)
c1bbd2d docs: fill in S1-003 commit hash in sprint-1 board
5992d54 feat: add location and background mode permissions to Info.plist (S1-003)
3948feb feat: integrate Google Maps SDK via Swift Package Manager (S1-002)
3922c81 chore: initialize project skeleton with XcodeGen (S1-001)
```

---

## バッテリー消費懸念への進捗

CLAUDE.md で挙がっていた「常時記録時のバッテリー懸念」に対し、Sprint 1 で以下まで実装済:

- `desiredAccuracy = kCLLocationAccuracyBest` + `distanceFilter = 10m`
- `activityType = .automotiveNavigation`（車移動向け、iOS が省電力チューニング）
- `pausesLocationUpdatesAutomatically = true`（停止検出時に自動 pause）
- `allowsBackgroundLocationUpdates = true` + `showsBackgroundLocationIndicator = true`

未対応（後続スプリント）:
- 自宅滞在時の完全停止（自宅登録機能と合わせて Sprint 3 想定）
- Significant Location Changes API の併用（Sprint 2 末〜3）
- 走行中・停車中で desiredAccuracy を動的調整（Sprint 3）

---

## 次スプリント候補（Sprint 2: ローカル DB + 滞留検出 + ピン記録）

PO/SM 案として、Sprint 2 のテーマを以下のように提案します:

1. **ローカル DB 設計と SwiftData 導入**（日付 PK / 移動ルート / ピン / 開始終了時刻）
2. **滞留検出ロジック**（10 分以上 GPS 変化なしで「滞留中」と判定）
3. **滞留地点へのピン記録**（その時点の座標を DB に保存。お店情報紐付けは Sprint 3）
4. **アプリ再起動後の経路復元**（DB から最新日付の route を読み込み Polyline 再描画）
5. **履歴タブの最低限の実装**（日付一覧と当日 route の表示）

Sprint 2 は Sprint 1 と同等以上の規模になるため、jun さんに方針合意いただいたうえで PO/SM が再度プランニングを実施します。

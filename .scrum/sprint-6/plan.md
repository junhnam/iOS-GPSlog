# Sprint 6 Plan（正式版 / A 案採用）

- スプリント期間: 2026-05-07 開始（1 イテレーション完結 = **最終スプリント**）
- 体制: PO/SM (Opus) + Dev x2 (Dev-1 / Dev-2 / Sonnet) + Designer (Sonnet / アイコン担当) + メイン代行 (Opus)
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・Sprint 5 末で origin 同期済 = `9802c00`）
- 現在のフェーズ: **development**（jun さん 5 項目回答取得済 2026-05-06）
- このスプリントの位置づけ: **個人利用版リリース** = jun さん自身の iPhone 16 Pro (iOS 26.1) に Xcode から Free Provisioning で署名インストールできる状態に到達する

---

## jun さん 5 項目回答結果（2026-05-06）

| # | 質問 | 回答 | Sprint 6 への影響 |
|---|---|---|---|
| 1 | 配布タイミング目標 | 個人利用のみ。継続使用後に商用化判断、商用化時は別ツール再設計 | **App Store 申請関連を全削除** |
| 2 | Apple Developer Program | 未加入 | **TestFlight / プライバシーマニフェストを削除**（Free Provisioning + Xcode 直インストールで完結） |
| 3 | 実機 iPhone | あり (iPhone 16 Pro / iOS 26.1) | **実機検証チケットを Sprint 6 末に組込**（Sprint 7 不要） |
| 4 | アプリアイコン | Designer エージェントに一任 | **scrum-designer を development 開始後にメインから起動**（アイコン + ローンチスクリーン） |
| 5 | Dropbox 実装 | 今回 omit、商用化時に再検討 | **S5-002 完全削除**。`CloudStorageProvider` プロトコルの抽象化のみ維持 |

技術用語の補足:
- **Free Provisioning（フリープロビジョニング）**: Apple Developer Program に加入していなくても、Xcode から自分の iPhone にビルドを直接インストールできる仕組み。7 日間で署名が切れるが個人利用では再ビルドで対応可能
- **DI（Dependency Injection、依存注入）**: 部品を組み立てる場所を一箇所に集めて、組み立て漏れがないか機械的にチェックできるようにする設計技法
- **SLC (Significant Location Changes)**: iOS が「大きく場所が変わった時だけ」アプリを起こす省電力モード。バッテリー対策の柱

---

## スプリントゴール

> **個人利用版として jun さんの iPhone 16 Pro に Xcode から実機インストールでき、CLAUDE.md 記載の全機能（DB クリア / DB 自動消去 / バッテリー最適化を含む）が実機で動作する状態に到達する**

達成判定（検証条件 7 項目 / 個人利用版リリース可能の定義）:

| # | 判定基準 | 確認方法 |
|---|---|---|
| 1 | DI 経路カバレッジテストが定型化され、新規サービス追加時の必須チェック項目に組込まれている | `dev-completion-checklist.md` 改訂 + `RootViewIntegrationTests.swift` の雛形コメント |
| 2 | `AppDependencyContainer` 経由で RootView が初期化され、依存組立漏れがコンパイル時に検出可能 | S6-002 のテスト + メイン代行ビルド確認 |
| 3 | 設定画面から指定日付の DB レコードを削除できる | S6-003 のテスト + 実機タップ動作確認 |
| 4 | DB が 1GB 超で古い順に自動削除される（設定 ON/OFF 可） | S6-004 のテスト + シミュレータでのモック容量検証 |
| 5 | バッテリー最適化（精度動的調整 / distanceFilter / `pausesLocationUpdatesAutomatically`）が実機で動作し、停車中は低精度に切り替わる | S6-005 のテスト + **実機バッテリー実測**（S6-008） |
| 6 | バックグラウンド復帰時に SLC からの再開経路が破綻なく動く | S6-006 のテスト + 実機バックグラウンド復帰テスト（S6-008） |
| 7 | アプリアイコン全サイズ + ローンチスクリーンが揃い、ビルド時に missing icon warning が出ない | S6-007 + `xcodebuild clean build` 出力 |

加えて Sprint 5 から継続:
- フル再ビルドで warning 0 / error 0
- ユニットテスト 100% pass（173 件 + 想定 +25〜35 件 = 約 200 件）
- API キー漏洩スキャン 0 件
- QA-S5-003（Google Drive 限定の Info.plist 運用整理）/ QA-S5-004（CSV 出力失敗時 retryCount 加算）解消

---

## スプリントバックログ（9 チケット）

| ID | タイトル | type | 見積 | 担当 | 優先度 | 備考 |
|---|---|---|---|---|---|---|
| S6-001 | DI 経路カバレッジテストの定型化（`dev-completion-checklist.md` 改訂 + 雛形コメント追加） | chore | S | po-sm | must | retro 最優先 Try。Phase 0 で実施 |
| S6-002 | `AppDependencyContainer` 導入（`RootView.init` の DI 集約） | refactor | M | dev-1 | must | retro 最優先 Try の構造的対策 |
| S6-003 | DB クリア機能（指定日付のデータ削除 + 設定画面 UI） | feature | M | dev-1 | must | CLAUDE.md 要件 |
| S6-004 | DB 自動消去（1GB 超で古い順削除 + 設定 ON/OFF Toggle） | feature | M | dev-2 | must | CLAUDE.md 要件 |
| S6-005 | バッテリー最適化（`desiredAccuracy` 動的 / `distanceFilter` チューニング / `pausesLocationUpdatesAutomatically` 検証） | feature | L→分割可 | dev-2 | must | CLAUDE.md「注意事項」必須対応 |
| S6-006 | バックグラウンド復帰時の挙動安定化（SLC 復帰時の状態整合 / `applicationDidBecomeActive` 経路の再開処理） | feature | M | dev-2 | must | S6-005 と一体検証 |
| S6-007 | アプリアイコン（全サイズ）+ ローンチスクリーン（Designer 主導 + dev-1 が `Assets.xcassets` 反映） | design | M | designer / dev-1 | must | jun さん指示で Designer 一任 |
| S6-008 | 実機検証総合チェック（MKLocalSearch / SLC / バッテリー実測 / バックグラウンド復帰 / アイコン実機表示） | qa-task | M | po-sm | must | jun さん iPhone 16 Pro / iOS 26.1 で検証 |
| S6-009 | QA-S5-004 CSV 出力失敗時 retryCount 方針判断 + 実装 + Info.plist 運用整理（QA-S5-003 / Google Drive 限定） | chore | S | dev-2 | should | Sprint 5 残課題まとめて解消 |

合計: **9 チケット**（Must 7 / Should 2 / Could 0）。Sprint 5 と同等規模。

技術用語の補足:
- **`@Model` (SwiftData)**: iOS 17+ 標準のローカル DB の「テーブル定義」相当。Sprint 2 で `DailyRecord` / `PinRecord` を導入済
- **`distanceFilter`**: 「これだけ移動するまで GPS の更新通知を出さない」というしきい値設定。値を上げるほどバッテリー消費が減る
- **`pausesLocationUpdatesAutomatically`**: iOS が「動いていない」と判断したら GPS 更新を自動停止する機能

---

## 担当分割の方針（ファイル競合ゼロを継続）

### Dev-1（UI / 設定 / View 系 / DI 集約）

- 新規ファイル:
  - `App/AppDependencyContainer.swift`（S6-002）
  - `Features/Settings/DBClearView.swift`（S6-003）
- 既存ファイル拡張:
  - `App/RootView.swift`（S6-002 で `AppDependencyContainer` 経由に切替）
  - `Features/Settings/SettingsView.swift`（S6-003 / S6-004 で「データ管理」セクション追加）
  - `Resources/Assets.xcassets/AppIcon.appiconset/*`（S6-007 で Designer から受領した PNG セットを反映）
  - `Resources/LaunchScreen.storyboard` または `App/LaunchView.swift`（S6-007）
- 担当チケット: **S6-002 / S6-003 / S6-007（Assets 反映部分）**

### Dev-2（サービス / モデル / ロジック / バッテリー系）

- 新規ファイル:
  - `Services/Storage/DatabaseAutoCleanupService.swift`（S6-004）
  - `Services/Location/BatteryAdaptiveLocationPolicy.swift`（S6-005）
- 既存ファイル拡張:
  - `Models/AppSettings.swift`（S6-004 で `dbAutoCleanupEnabled` / `dbAutoCleanupThresholdGB` 追加）
  - `Services/Storage/DatabaseService.swift` 相当（S6-003 で日付指定削除メソッド追加 / S6-004 で容量計測メソッド追加）
  - `Services/Location/LocationService.swift`（S6-005 / S6-006: 動的精度切替 / バックグラウンド復帰経路）
  - `Services/Cloud/CloudUploadRetryQueue.swift`（S6-009 で retryCount 加算ロジック修正）
  - `Resources/GoogleDriveOAuth-Info.plist.example`（S6-009 で Google Drive 限定の `.example` パターン整備）
  - `.gitignore`（S6-009 で実 plist を除外）
- 担当チケット: **S6-004 / S6-005 / S6-006 / S6-009**

### Designer（development 開始後にメインから起動）

- S6-007 のアイコンマスター画像 1024x1024 を生成 + 全サイズ展開 + ローンチスクリーンの落ち着いた配色決定
- 出力先: PNG セット一式を Dev-1 に渡す（コミットは Dev-1）

### PO/SM（メイン代行）

- 担当チケット: **S6-001 / S6-008**
- S6-001 は Phase 0（Dev-1 / Dev-2 着手前）に完了
- S6-008 は Sprint 6 末（全 Dev チケット完了 + メイン代行ビルド確認後）に jun さん iPhone で実施

### 共有ファイル（事前合意）

- `App/RootView.swift`: Dev-1 が S6-002 で書き換え（Dev-2 は触らない。S6-002 完了後に Dev-2 が S6-005 / S6-006 で `LocationService` の依存を `AppDependencyContainer` 経由に書き換え）
- `Models/AppSettings.swift`: Dev-2 が S6-004 着手時にプロパティ追加 → Dev-1 が S6-003 / S6-004 で UI バインドのみ参照
- `Features/Settings/SettingsView.swift`: Dev-1 が S6-003 / S6-004 で「データ管理」セクション 2 行を追加（Dev-2 は触らない）
- `Services/Location/LocationService.swift`: Dev-2 が S6-005 / S6-006 を順次担当（Dev-1 は触らない）
- `.scrum/process/dev-completion-checklist.md`: PO/SM が S6-001 で改訂（Dev は読むだけ）

git 競合 0 件を Sprint 3 / 4 / 5 から継続する。

---

## 着手順序の推奨

### Phase 0（PO/SM 主導 / Dev 着手前）

1. **S6-001** DI 経路カバレッジテスト定型化 (po-sm)
   - `.scrum/process/dev-completion-checklist.md` に「新規サービス追加時は RootView 統合テストで DI 経路を検証する」を追加
   - `RootViewIntegrationTests.swift` に「新規サービス追加時はここに DI 検証ケースを追加すること」の雛形コメント挿入
   - **目的**: Sprint 4 / 5 で連続発生した DI 漏れの再々発防止ガードを Sprint 6 開始時に整備

### Phase 1（Dev-1 主導 / 構造改善 + 構造改善前提のリファクタ）

1. **S6-002** `AppDependencyContainer` 導入 (dev-1)
   - `RootView.init` の DI 組立を `AppDependencyContainer` に集約
   - 統合テストを更新（既存 `RootViewIntegrationTests.swift` 全件 pass + S6-001 雛形に沿った新規ケース）
   - **理由**: S6-005 / S6-006 で Dev-2 が `LocationService` を触る前に DI 集約を完了しておけば、Dev-2 の作業が楽になる

### Phase 2（Dev-2 並行開始 / プロダクト機能）

1. **S6-009** QA-S5-003/004 解消（依存なし軽量・ウォームアップ）
2. **S6-004** DB 自動消去（`AppSettings` 拡張 → DB サービス容量計測 → 自動消去サービス）
3. **S6-005** バッテリー最適化（`LocationService` の動的精度切替 + ユニットテスト）

### Phase 3（Dev-1 / Dev-2 並行）

- Dev-1: **S6-003** DB クリア機能（S6-002 完了後 / S6-004 の AppSettings 拡張コミット後に着手）
- Dev-2: **S6-006** バックグラウンド復帰（S6-005 完了後）

### Phase 4（デザイン取り込み）

1. メインから **scrum-designer** を起動 → アイコンマスター + ローンチスクリーン素材生成
2. **S6-007** Dev-1 が Designer 成果物を `Assets.xcassets` に反映 + ローンチスクリーン実装

### Phase 5（実機検証 / Sprint 6 末）

1. メイン代行が `xcodebuild clean build` で warning 0 / error 0 確認
2. `xcodebuild clean test` で全ユニットテスト pass 確認
3. **S6-008** PO/SM が jun さんに iPhone 16 Pro 実機検証を依頼（チェックリスト方式）
   - Xcode から Free Provisioning で署名 → 実機にインストール
   - MKLocalSearch（ピン名前付け）/ SLC（バックグラウンド移動検知）/ バッテリー実測（1 日持ち歩いて消費率測定）/ バックグラウンド復帰 / アイコン実機表示
4. 実機で問題が出た場合は Sprint 内で修正 or Sprint 6 完了後の追加コミットで対応

---

## Designer の関与タイミング（jun さん指示で一任）

| タイミング | アクション | 担当 |
|---|---|---|
| Phase 4 着手時 | メインから `scrum-designer` を起動。「個人利用版なので落ち着いた配色」「GPS / 移動 / 地図を連想させる図像」を依頼 | メイン |
| Designer 起動後 | 1024x1024 マスター画像 + 全サイズ展開 + ローンチスクリーン配色決定 | Designer (Sonnet) |
| 受領後 | Dev-1 が `Assets.xcassets/AppIcon.appiconset/*` に反映 + `LaunchScreen.storyboard` または SwiftUI 実装 | Dev-1 |

注意:
- **Designer はメイン側から起動する**（PO/SM エージェントからは起動しない、メイン代行運用ルール継続）
- アイコンの最終承認は jun さんが S6-008 実機検証時に「実機ホーム画面でしっくり来るか」で行う
- しっくり来ない場合は Sprint 6 完了後の追加コミットで差し替え可能（個人利用なのでリリース後の手戻りリスクはない）

---

## 実機検証チケット（S6-008）の配置と内容

### Sprint 6 末配置の理由

- 実機検証はシミュレータで再現できない項目が中心（MKLocalSearch のお店名検索精度 / SLC のバックグラウンド起動 / バッテリー実測 / アイコンの実機表示）
- 全 Dev チケット完了 + メイン代行ビルド確認後に実施しないと「修正したい時にどこを直せばいいか」が分散する
- jun さん iPhone 16 Pro / iOS 26.1 が前提（回答 3）

### S6-008 のチェックリスト（PO/SM が事前準備 → jun さんが実施）

| # | 観点 | 期待動作 | 失敗時の対応 |
|---|---|---|---|
| 1 | Xcode → 実機インストール | Free Provisioning で署名 → ホーム画面にアプリ表示 | プロビジョニング設定確認 |
| 2 | MKLocalSearch | ピン留めしたお店の名前と住所が表示される | Sprint 内修正 or 商用化時 Google Places 差替え検討 |
| 3 | SLC バックグラウンド | アプリを背景に回した状態で 500m 以上移動 → アプリが起こされて記録継続 | LocationService の SLC 経路調査 |
| 4 | バッテリー実測 | 1 時間運転で消費 5% 以下（jun さん実測値で判定） | S6-005 の動的精度しきい値再調整 |
| 5 | バックグラウンド復帰 | アプリを背景化 → 数分後に戻す → 記録が破綻なく続いている | S6-006 の `applicationDidBecomeActive` 経路調査 |
| 6 | アイコン実機表示 | ホーム画面のアイコンが想定通り | Designer に再依頼 |
| 7 | ローンチスクリーン | アプリ起動時の表示が想定通り | LaunchScreen.storyboard / LaunchView 修正 |

S6-008 完了 = Sprint 6 完了 = **個人利用版リリース可能**。

---

## リスクと許容範囲

| リスク | 内容 | 許容範囲 / 対処 |
|---|---|---|
| R1 | QA で Critical/High が出たときの吸収余地が小さい | Should 1 件（S6-009）を落とすことを許容。最悪は Sprint 内で潰せず追加コミットで対応 |
| R2 | バッテリー実測で「1 時間運転で 10% 以上消費」など実用に耐えない数字が出る | S6-005 の動的精度しきい値を再調整して再ビルド → jun さんに再実測依頼。Sprint 内で 2 周まで対応 |
| R3 | MKLocalSearch のお店名検索精度が日本国内で低い | 個人利用版なので「住所のみ表示」にフォールバックして許容。商用化時に Google Places 差替えを検討（CLAUDE.md 別ツール再設計方針と整合） |
| R4 | Designer が想定とずれたアイコンを生成 | 個人利用なので jun さんが S6-008 実機確認後に追加差し替えで対応 |
| R5 | Free Provisioning の 7 日署名切れで実機テスト中に落ちる | 個人利用なので再ビルドで対応。商用化時に Apple Developer Program 加入を再検討 |
| R6 | DB 自動消去で「消えてほしくないデータ」が消える | デフォルト OFF + 1GB しきい値とする（明示的に ON にしない限り発動しない設計）|

---

## Sprint 5 retro Try の Sprint 6 への反映状況

| # | retro Try | Sprint 6 plan での反映 |
|---|---|---|
| 1 | DI 経路カバレッジテストを `dev-completion-checklist.md` に組み込む（最優先） | **S6-001 として Must 化（Phase 0 で PO/SM が実施）** |
| 2 | `AppDependencyContainer` 導入で `RootView.init` 整理 | **S6-002 として Must 化（Phase 1 で Dev-1 が実施）** |
| 3 | Info.plist の OAuth 設定を gitignore + `.example` パターン化 | **S6-009 に統合（Google Drive 限定で運用整理。Dropbox 部分は商用化時 DEFER）** |
| 4 | CloudUploadRetryQueue の CSV 出力失敗時挙動整理（QA-S5-004） | **S6-009 に統合（retryCount 加算実装）** |
| 5 | シミュレータ動作確認シナリオを `simulator-scenarios.md` に集約 | **Sprint 6 中に PO/SM が継続更新（チケット化せず運用）** |
| 6 | Sprint 6 開始時に Task ツール可否を再確認 | **planning_review 冒頭で確認済（従来通り Single-Agent / メイン代行運用継続）** |
| 7 | 節目ハンドオーバー更新の順序テンプレ化 | **`.claude-handover.md` の冒頭テンプレに反映（チケット化せず運用）** |
| 8 | Dev フェーズ完了直後に push 候補を提示する運用 | **運用継続（チケット化せず PO/SM が遵守）** |
| 9 | Sonnet 化の効果検証を継続 | **Sprint 6 review に「Sprint 4 / 5 / 6 のメトリクス比較」テーブル追加** |

---

## モデル切替（Sprint 5 から継続）

| エージェント | Sprint 6 | 備考 |
|---|---|---|
| scrum-po-sm | Opus | 戦略 / 合意形成 / 外部報告 |
| qa-orchestrator | Opus | 観点設計 / 品質判定（必要時のみ） |
| scrum-dev-agent | Sonnet | コード実装。**xcodebuild はメイン代行（jun さん指示継続）** |
| scrum-designer | **Sonnet（Sprint 6 で初起動）** | アプリアイコン + ローンチスクリーン |
| qa-implementer / runner / fixer | Sonnet | 必要時のみ起動（Sprint 5 同様 Single-Agent モード見込み） |

---

## Dev フェーズ完了基準（Sprint 5 から継続）

`.scrum/process/dev-completion-checklist.md` を遵守する。要点:

1. ユニットテスト pass
2. 静的解析 warning 0
3. **`xcodebuild clean build` で warning 0**（Sprint 5 から必須運用継続）
4. ビルドエラー 0
5. iOS 26 API 変更点ノートとの整合
6. **DI 経路カバレッジテスト追加チェック**（**Sprint 6 から S6-001 で必須化**）
7. board.md 状態更新
8. git commit

### Dev エージェントへのプロンプト雛形

各 Dev サブエージェント起動時に以下を必ずプロンプトに含める:

```
- ビルド (xcodebuild) はメインエージェント (Opus) が代行する。あなた (Dev エージェント, Sonnet) は試みないこと
- ユニットテスト追加・xcodegen・コード編集は自分で行う
- 自チケット完了前にメインエージェントへ「ビルド確認をお願いします」と要請する
- メインがビルド結果（warning 数・error 数）を返したら、warning 0 / error 0 を確認のうえ Done に更新する
- iOS 26 API 変更点は .scrum/notes/ios26-api-changes.md を必ず参照する
- 新規 API 採用時は「置換 API 自体も deprecated 化されているか」を 2 段先まで確認する
- 新規サービス / 新規 @Model 追加時は RootView 統合テストに DI 検証ケースを追加すること（S6-001 雛形コメント参照）
- Dev 完了基準は .scrum/process/dev-completion-checklist.md を必ず参照
```

---

## 完了基準（Sprint 6 全体 = 個人利用版リリース）

- [ ] 全 9 チケット（Must 7 / Should 2 / Could 0）が Done
- [ ] スプリントゴール検証条件 7 項目すべて静的に確認可能
- [ ] フル再ビルド warning 0 / error 0
- [ ] ユニットテスト pass 100%（173 件 + 想定 +25〜35 件 = 約 200 件）
- [ ] Sprint 1〜5 のテスト 173 件の回帰なし
- [ ] API キー漏洩スキャン 0 件
- [ ] DI 検証テストが新規サービスに対して必須化されている（S6-001 効果確認）
- [ ] **S6-008 実機検証 7 観点すべて jun さん側で OK 判定**
- [ ] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得 + git push 承認）

---

## 「Sprint 6 完了 = 個人利用版リリース可能」の定義

以下がすべて満たされた状態を「個人利用版リリース可能」と定義する:

1. **CLAUDE.md 全要件** が実機で動作（地図 / 経路 / 滞留ピン / カレンダー同期 / DB / CSV / Google Drive / 設定全項目 / DB クリア / DB 自動消去 / 自宅設定 / バッテリー対策）
2. **jun さん iPhone 16 Pro / iOS 26.1** に Xcode から Free Provisioning でインストールでき、署名期限内（7 日）でアプリが動作する
3. **バッテリー実測** で個人利用に耐える数字が出ている（jun さん実測判定）
4. **アプリアイコン + ローンチスクリーン** が揃い、ホーム画面でしっくり来る
5. **未解消バグなし**（Critical / High / Medium 全 0、Low は許容）

App Store 申請関連（メタデータ / プライバシーマニフェスト / TestFlight / アイコンの App Store 用 1024x1024）は **商用化判断時に別途対応**（Sprint 7 以降は現時点で予定なし、CLAUDE.md「別ツール再設計」方針と整合）。

---

## planning_review で取得済の判断（再掲）

| # | 判断項目 | jun さん回答 |
|---|---|---|
| 1 | A 案 / B 案 | A 案（1-sprint 完結 / 個人利用版リリース）|
| 2 | 配布タイミング | 個人利用のみ。商用化時に別ツール再設計 |
| 3 | Apple Developer Program | 未加入 |
| 4 | 実機 iPhone | あり (iPhone 16 Pro / iOS 26.1) |
| 5 | アプリアイコン | Designer エージェント一任 |
| 6 | Dropbox 実装 | omit。`CloudStorageProvider` の入口のみ維持 |

すべて取得済のため、planning_review は完了。development フェーズに即移行。

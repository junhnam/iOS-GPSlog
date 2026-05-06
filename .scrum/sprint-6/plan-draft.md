# Sprint 6 Plan（ドラフト）

> **これはドラフトです。** jun さん承認後に正式 `plan.md` に昇格 + GitHub Issue 起票 + `.scrum/config.md` の `current_sprint` / `sprint_phase` 更新がメインセッションで実施されます。本ファイルだけが先行コミットされます。

- 作成日: 2026-05-06（Sprint 5 review/retro 完了直後）
- 想定スプリント期間: 2026-05-07 開始（A 案 / B 案で長さが変わる）
- 体制: PO/SM (Opus) + Dev x2 (Dev-1 / Dev-2 / Sonnet) + QA (qa-multi-agent / Single-Agent モード見込み) + メイン代行 (Opus)
- リポジトリ: `junhnam/iOS-GPSlog`（main ブランチ・Sprint 5 末で origin 同期済 = `9802c00`）
- 現在のフェーズ: **planning_review**（jun さん承認待ち。承認後 development へ）
- このドラフトの目的: **Sprint 6 を 1 sprint で締めるか、Sprint 7 に分割するかを jun さんに判断してもらうための材料を提示する**こと

---

## 0. なぜドラフト 2 案を出すか（前提整理）

`.scrum/config.md` の `estimated_sprints: 6` に従えば、Sprint 6 が**最終スプリント**であり、終了時には App Store 申請可能な品質に到達している想定でした。

ところが Sprint 5 review / retro / バックログを集約すると、Sprint 6 候補スコープが Sprint 5（8 チケット完了）と同等以上の規模感に膨らんでいます。具体的には:

- 必須繰越: **3 件**（S5-002 Dropbox / QA-S5-003 Info.plist 運用 / QA-S5-004 retryCount）
- プロセス改善 (retro 最優先 Try): **2 件**（DI 経路カバレッジテストの定型化 / `AppDependencyContainer` 導入）
- プロダクト機能 (CLAUDE.md 残): **4 件**（DB クリア / DB 自動消去 / バッテリー最適化 / バックグラウンド復帰）
- リリース準備: **4 件**（アプリアイコン / ローンチスクリーン / プライバシーマニフェスト / App Store 申請メタデータ）
- 実機検証 (jun さん依存): **1 件**（MKLocalSearch / SLC の実機検証）

**合計 14 件**で、Sprint 5 の 8 件を 75% 上回ります。1 sprint に詰め込むと QA フェーズで Critical/High バグが出た時に吸収余地がなくなり、Sprint 5 で起きた「QA-S5-001 をスプリント内で潰せたのは余裕枠があったから」という幸運の再現が難しくなります。

そこで A 案（1-sprint 完結）と B 案（2-sprint 分割）を併記し、jun さんに判断材料を提示します。

技術用語の補足:
- **DI（Dependency Injection、依存注入）**: 部品を組み立てる場所を一箇所に集めて、組み立て漏れがないか機械的にチェックできるようにする設計技法
- **OAuth（オーオース）**: Google Drive や Dropbox に「このアプリにあなたのデータへの一時的な許可をください」とお願いするための業界標準の認証手順
- **プライバシーマニフェスト**: App Store がアプリに「あなたは何のデータをどう使うか」を機械可読な形で要求する宣言ファイル。2024 年春から事実上必須

---

## 1. スコープ振り分け（Must / Should / Could / Won't）

「最終スプリントとしてリリース可能な状態」を達成するために必要な観点で振り分け:

### Must（リリース MVP に必須。これが無いと App Store 申請できない、または Sprint 5 ゴール未達のまま終わる）

| # | 項目 | 理由 |
|---|---|---|
| M1 | S5-002 Dropbox SDK 導入 + OAuth 認証（Issue #36 繰越） | Sprint 5 で「次スプリントで対応」と合意済み。CLAUDE.md でも Google Drive と並列で要件化されている |
| M2 | QA-S5-003 Info.plist の OAuth ClientID 運用整理（gitignore + .example パターン化） | jun さん側で実 OAuth テストするために必須。値が埋まらないと検証条件 #1〜#6 が回らない。コード自体の機密値ではないがリポジトリ管理運用の整理が必須 |
| M3 | DI 経路カバレッジテストの定型化（`dev-completion-checklist.md` への組み込み） | Sprint 4→5 で連続して同型 Critical/High が再発した。Sprint 6 で新規サービスを追加する以上、再々発防止のガードは必須。retro 最優先 Try |
| M4 | プライバシーマニフェスト作成（`PrivacyInfo.xcprivacy`） | **App Store 審査で 2024 春から事実上必須**。これが無いと申請できない |
| M5 | アプリアイコン（全 iOS 必要サイズ） | App Store 申請とビルド時の警告解消に必須 |
| M6 | App Store 申請メタデータ準備（説明文 / スクリーンショット / カテゴリ / 年齢制限 / プライバシー回答） | 申請に必須。実機ビルドが無くてもメタデータ準備は前倒しできる |
| M7 | バッテリー最適化（精度動的調整 / distanceFilter / `pausesLocationUpdatesAutomatically`） | CLAUDE.md「注意事項」で明示された懸念。常時記録モードがバッテリーで実用に耐えないと「自分用」さえ成立しない |
| M8 | バックグラウンド復帰時の挙動安定化 | Sprint 3 の SLC 併用設計の動作確認が未済。バッテリー最適化と一体で検証する必要がある |

### Should（重要だが、リリース後パッチ対応も可能）

| # | 項目 | 理由 |
|---|---|---|
| S1 | DB クリア機能（指定日付のデータ削除） | CLAUDE.md 要件。設定画面に追加。プライバシー観点（特定日のログを消したい時）で重要だが、リリース後 v1.1 で追加でも可 |
| S2 | DB 自動消去（1GB 超で古い順削除） | CLAUDE.md 要件。1GB に達するまでの実利用日数は数ヶ月想定のため、リリース直後の必須性は低い |
| S3 | `AppDependencyContainer` 導入（`RootView.init` の DI 集約） | retro 最優先 Try の構造的対策。M3 のテスト定型化と組み合わせると効果が最大化するが、テスト定型化単体でも再発防止は可能 |
| S4 | QA-S5-004 CSV 出力失敗時 retryCount 加算 | Sprint 5 retro で「実害は小さい」と判定済み。3 案から方針判断 → 軽微な実装 |
| S5 | ローンチスクリーン（`LaunchScreen.storyboard` または SwiftUI 実装） | iOS 14+ では大きな影響なし。ベタ単色起動で申請通る。アイコンが先 |

### Could（余裕があれば）

| # | 項目 | 理由 |
|---|---|---|
| C1 | MKLocalSearch / SLC の実機検証（jun さん側） | シミュレータでは再現不可。iPhone 実機 + Apple Developer Program が必要。レビュー / 申請とは独立でいつでも実施可能。Sprint 6 の Dev タスクとは別軸 |
| C2 | バッテリー実機実測（実機を 1 日持ち歩いて消費率を測定） | M7 のシミュレータレベル検証では限界がある。実機で初めて意味のある数字が出る。jun さんの実機運用が前提 |
| C3 | Sonnet サブエージェントの sandbox 設定見直し（settings.json） | retro 継続未達課題。Sprint 6 でも jun さん意向次第で据え置き |

### Won't（今回スコープ外 → Sprint 8 以降 / v2.0 候補）

| # | 項目 | 理由 |
|---|---|---|
| W1 | iCloud バックアップ対応（Could 既存） | CLAUDE.md 範囲外。リリース後の機能追加 |
| W2 | 月次サマリ画面 / ピン手動編集 / 経路色分け（Could 既存） | CLAUDE.md 範囲外 |
| W3 | Apple Watch / Android / 共有機能 | バックログ Won't のまま継続 |

---

## 2. A 案: 1-sprint 完結（Sprint 6 で締める）

### 2-1. 設計思想

**Must 8 件のうち、Sprint 6 で確実に潰す優先度を厳選**し、Should 5 件のうち最小限を取り込む構成。S1〜S5 の Should は「リリース後パッチ可能」と割り切り、初回リリース後の v1.1（Sprint 7 相当）に振り分ける前提。

### 2-2. スプリントゴール（1 文）

> **App Store 申請可能な品質に到達し、Dropbox 同期 + バッテリー実用性 + プライバシーマニフェスト + アイコン + 申請メタデータを揃える**

技術用語の補足: 「App Store 申請可能」とは、Apple Developer Program に登録した状態で `xcodebuild archive` を作って提出できる状態を指す（実際の提出操作は jun さんが実機 + Developer Program 加入後に行う）。

### 2-3. スプリントバックログ（10 チケット）

| ID | タイトル | type | 見積 | 担当 | 優先度 | 備考 |
|---|---|---|---|---|---|---|
| S6-001 | Dropbox SDK 軽量実装 + OAuth PKCE（Apple 純正のみで Sprint 5 パターン継承） | feature | M | dev-2 | must | Issue #36 繰越 |
| S6-002 | Info.plist の OAuth 設定を gitignore + `.example` パターン化（Google Drive / Dropbox 両対応） | chore | S | dev-2 | must | QA-S5-003 解消 |
| S6-003 | DI 経路カバレッジテストの定型化（`dev-completion-checklist.md` 改訂 + 雛形コメント追加） | chore | S | po-sm | must | retro 最優先 Try |
| S6-004 | プライバシーマニフェスト (`PrivacyInfo.xcprivacy`) 作成 + Required Reasons API の宣言 | chore | M | dev-2 | must | App Store 必須 |
| S6-005 | アプリアイコン（全サイズ）+ ローンチスクリーン | design | M | designer / dev-1 | must | アイコンは 1024x1024 のマスター画像から自動生成。SwiftUI で簡易デザイン or jun さん画像差し込み |
| S6-006 | バッテリー最適化（`desiredAccuracy` 動的 / `distanceFilter` チューニング / `pausesLocationUpdatesAutomatically` 検証） | feature | L→分割 | dev-2 | must | Sprint 3 で枠組みは作成済。動的調整の閾値見直し + ユニットテスト追加 |
| S6-007 | バックグラウンド復帰時の挙動安定化（SLC 復帰時の状態整合 / `applicationDidBecomeActive` 経路の再開処理） | feature | M | dev-2 | must | S6-006 と一体で検証 |
| S6-008 | App Store 申請メタデータ準備（説明文 / スクリーンショット / カテゴリ / 年齢制限 / プライバシー質問回答） | docs | M | po-sm | must | コード変更なし。`.scrum/notes/app-store-submission.md` に集約 |
| S6-009 | クラウド保存先選択 UI に Dropbox を追加（既存 `CloudStoragePickerView` 拡張） | feature | S | dev-1 | must | S6-001 完了後 |
| S6-010 | QA-S5-004 CSV 出力失敗時の retryCount 方針判断 + 実装 | chore | S | dev-2 | should | 3 案から方針判断 → 軽微な実装 |

合計: **10 チケット**（Must 9 / Should 1 / Could 0）。Sprint 5 の 8 件 + 25%。
Should 5 件のうち 4 件（DB クリア / DB 自動消去 / `AppDependencyContainer` 導入 / ローンチスクリーン）はリリース後 v1.1（Sprint 7 相当）へ送る前提。

### 2-4. 担当分割（ファイル競合ゼロを継続）

#### Dev-1（UI / 設定 / View 系）
- 既存ファイル拡張: `CloudStoragePickerView.swift`（S6-009 で Dropbox 追加）
- 新規 / 既存ファイル: `Resources/Assets.xcassets/AppIcon.appiconset/*`（S6-005 アイコン差し込み）
- 担当チケット: **S6-005（dev-1 部分）/ S6-009**

#### Dev-2（サービス / ロジック / モデル / クラウド I/O 系）
- 新規ファイル:
  - `Services/Cloud/DropboxSyncService.swift`（S6-001）
  - `Resources/PrivacyInfo.xcprivacy`（S6-004）
  - `Resources/GoogleDriveOAuth-Info.plist.example` / `Resources/DropboxOAuth-Info.plist.example`（S6-002）
- 既存ファイル拡張:
  - `Services/Location/LocationService.swift`（S6-006 / S6-007: 動的精度 / 復帰経路）
  - `.gitignore`（S6-002: 実 plist を追跡対象から除外）
- 担当チケット: **S6-001 / S6-002 / S6-004 / S6-006 / S6-007 / S6-010**

#### Designer（任意起動）
- S6-005 のアイコンマスター画像 1024x1024 を SwiftUI プロトタイプ or jun さん提供画像から作成

#### PO/SM（メイン代行）
- 担当チケット: **S6-003 / S6-008**（コード変更なしのドキュメント整備）

#### 共有ファイル（事前合意）
- `Features/Settings/CloudStoragePickerView.swift`: Dev-1 が S6-009 で Dropbox 行を 1 つ追加（Dev-2 は触らない）
- `.scrum/process/dev-completion-checklist.md`: PO/SM が S6-003 で改訂（Dev は読むだけ）

### 2-5. 検証条件（jun さん向け 7 項目）

| # | 判定基準 | 確認方法 |
|---|---|---|
| 1 | クラウド保存先で Dropbox を選び、OAuth 認証ができる | S6-001 のテスト + jun さん側シミュレータ確認 |
| 2 | 自動同期 ON 時、Dropbox にも `GPSログ/{日付}/data.csv` 階層でアップロードされる | S6-001 / S6-009 のテスト + jun さん側シミュレータ確認 |
| 3 | `GoogleDriveOAuth-Info.plist` / `DropboxOAuth-Info.plist` が `.gitignore` に入り、`.example` がリポジトリにある | `git status` / `git ls-files` で確認 |
| 4 | プライバシーマニフェストが正しく宣言されている（位置情報 / Keychain / UserDefaults の Required Reasons API） | `xcodebuild archive` で警告なし + Apple のチェッカーをパスする |
| 5 | 全 iOS 必要サイズのアプリアイコンが揃っており、ビルド時に missing icon warning が出ない | `xcodebuild clean build` の出力 |
| 6 | バッテリー最適化のユニットテスト（精度動的調整 / distanceFilter チューニング）が pass する | S6-006 のテスト |
| 7 | バックグラウンド復帰時の状態整合テストが pass する | S6-007 のテスト |

加えて Sprint 5 から継続:
- フル再ビルドで warning 0 / error 0
- ユニットテスト 100% pass（173 件 + 想定 +30〜40 件 = 約 210 件）
- API キー漏洩スキャン 0 件

### 2-6. リスクと許容範囲（A 案を選んだ場合）

| リスク | 内容 | 許容範囲 / 対処 |
|---|---|---|
| R1 | QA で Critical/High が出たときの吸収余地が小さい | Should 1 件（S6-010）が落ちることを許容。最悪は Sprint 内で潰せず Sprint 7 への繰越判断を jun さんに緊急相談 |
| R2 | DB クリア / DB 自動消去が初回リリースに入らない | リリース後 v1.1 で追加（数週間後の Sprint 7 相当で対応）。CLAUDE.md 要件は満たさない状態で初回リリースする判断を jun さんに明示確認 |
| R3 | `AppDependencyContainer` 導入が見送られる | retro 最優先 Try の構造的対策（S3）を見送り、テスト定型化（M3）のみで再発防止に頼る。テスト追加が遵守されれば実用上は問題ないが、`RootView.init` の肥大化は継続する |
| R4 | バッテリー / バックグラウンド復帰のシミュレータ検証では実利用感が掴めない | C2（バッテリー実機実測）は jun さん側で実機運用後に別途確認。Sprint 6 内ではユニットテストレベルの担保にとどまる |
| R5 | アプリアイコンのデザイン品質が低い | jun さんが自分で 1024x1024 の画像を提供できる場合は Designer 不要。提供できない場合は SwiftUI プロトタイプの簡易デザインで初回リリース → リリース後に差し替え |

### 2-7. A 案のキャパシティ評価

- Sprint 5 実績: 8 チケット完了 + QA-S5-001/002 の Sprint 内修正
- A 案: 10 チケット（+25%）+ プライバシーマニフェスト / App Store メタデータという「Dev チームが慣れていない種類」の作業を含む
- 評価: **タイトだが完了不可能ではない**。ただし QA フェーズで Critical/High が出ると吸収余地が薄い

---

## 3. B 案: 2-sprint 分割（Sprint 6 + Sprint 7）

### 3-1. 設計思想

**Sprint 6 を「機能完成 + 同期完成」フェーズ、Sprint 7 を「リリース仕上げ」フェーズ**に分け、両 sprint で QA 余裕を確保する構成。Must 8 件 + Should 5 件のうち、コード変更を伴う重い項目を Sprint 6 に、申請ドキュメント / アイコン / 微調整 / 実機検証連動を Sprint 7 に振る。

### 3-2. Sprint 6（機能完成）

#### スプリントゴール
> **Dropbox 同期と DB 機能と DI 構造改善を完成させ、コード面でリリース候補状態にする**

#### スプリントバックログ（9 チケット）

| ID | タイトル | type | 見積 | 担当 | 優先度 |
|---|---|---|---|---|---|
| S6-001 | Dropbox SDK 軽量実装 + OAuth PKCE | feature | M | dev-2 | must |
| S6-002 | Info.plist の OAuth 設定を gitignore + `.example` パターン化 | chore | S | dev-2 | must |
| S6-003 | DI 経路カバレッジテストの定型化（`dev-completion-checklist.md` 改訂） | chore | S | po-sm | must |
| S6-004 | `AppDependencyContainer` 導入（`RootView.init` の DI 集約） | refactor | M | dev-1 | must |
| S6-005 | クラウド保存先選択 UI に Dropbox を追加 | feature | S | dev-1 | must |
| S6-006 | DB クリア機能（指定日付のデータ削除 + 設定画面 UI） | feature | M | dev-1 | must |
| S6-007 | DB 自動消去（1GB 超で古い順削除 + 設定 ON/OFF） | feature | M | dev-2 | must |
| S6-008 | バッテリー最適化（`desiredAccuracy` 動的 / `distanceFilter` チューニング） | feature | L→分割 | dev-2 | must |
| S6-009 | QA-S5-004 CSV 出力失敗時の retryCount 方針判断 + 実装 | chore | S | dev-2 | should |

合計: **9 チケット**（Must 8 / Should 1 / Could 0）。Sprint 5 と同等規模。

#### 検証条件（5 項目）
1. Dropbox 認証 + 自動同期が静的に動く（S6-001 / S6-005）
2. OAuth Info.plist の運用整理が完了（S6-002）
3. DI 検証テストが新規サービス追加で必須化されており、雛形コメントも入っている（S6-003）
4. `AppDependencyContainer` を経由した RootView 初期化テストが pass（S6-004）
5. DB クリア / 自動消去 / バッテリー最適化のユニットテストが pass（S6-006 / S6-007 / S6-008）

#### Sprint 6 の特徴
- リリース系（プライバシーマニフェスト / アイコン / 申請メタデータ）は触らない
- バックグラウンド復帰は Sprint 7 で（バッテリー最適化と一体検証）
- QA 余裕を確保しつつ DI 構造改善 + DB 機能 + バッテリー最適化を完成させる

### 3-3. Sprint 7（リリース仕上げ）

#### スプリントゴール
> **App Store 申請可能な状態に到達し、jun さん側で archive + 申請オペレーションを実行できる状態にする**

#### スプリントバックログ（7 チケット）

| ID | タイトル | type | 見積 | 担当 | 優先度 |
|---|---|---|---|---|---|
| S7-001 | プライバシーマニフェスト (`PrivacyInfo.xcprivacy`) 作成 + Required Reasons API 宣言 | chore | M | dev-2 | must |
| S7-002 | アプリアイコン（全サイズ）+ ローンチスクリーン | design | M | designer / dev-1 | must |
| S7-003 | バックグラウンド復帰時の挙動安定化（SLC 復帰時の状態整合） | feature | M | dev-2 | must |
| S7-004 | App Store 申請メタデータ準備（説明文 / スクリーンショット / カテゴリ / プライバシー回答） | docs | M | po-sm | must |
| S7-005 | TestFlight 配布チェック（`distribution-checker` スキル併用） | chore | S | po-sm | must |
| S7-006 | バッテリー実機実測の手順書整備（`.scrum/notes/battery-measurement.md`） | docs | S | po-sm | should |
| S7-007 | MKLocalSearch / SLC の実機検証手順整備（`.scrum/notes/realdevice-checks.md`） | docs | S | po-sm | should |

合計: **7 チケット**（Must 5 / Should 2 / Could 0）。Sprint 5 / 6 より軽め。

#### 検証条件（5 項目）
1. プライバシーマニフェストが正しく宣言され、`xcodebuild archive` でチェッカーをパスする
2. 全 iOS 必要サイズのアプリアイコンが揃っており、missing icon warning が出ない
3. バックグラウンド復帰の状態整合テストが pass する
4. App Store 申請メタデータが揃っており、Apple のフォーム入力で詰まる項目がない
5. 配布前チェッカー（`distribution-checker` スキル）の警告が許容範囲内

### 3-4. 分割理由（なぜ 1 sprint に収まらないか）

| 観点 | 理由 |
|---|---|
| 1. 規模 | Must 8 + Should 5 で 13 件は Sprint 5 の 8 件を 60% 上回る。Dev チケットの平均サイズが M 寄りで、L 級（バッテリー最適化）も含む |
| 2. 種類 | Sprint 6 候補にはコード変更（Dropbox / DB 機能 / バッテリー）と非コード変更（プライバシーマニフェスト / アイコン / 申請メタデータ）が混在。**性質が違う作業を同 sprint に詰めると QA 観点が散る** |
| 3. QA 余裕 | Sprint 4 / 5 で連続して Critical/High が出た事実があり、Sprint 6 で新規 Dropbox 同期 + DB 機能 + バッテリー最適化 + DI 構造改善という大規模変更を入れると、**QA 余裕がゼロでリリース直前にバグ未修正で踏み外すリスクが高い** |
| 4. 申請依存 | プライバシーマニフェスト / 申請メタデータは jun さん側の Apple Developer Program 加入状態 / 実機保有状態に左右されるため、機能完成後に独立して整備するほうが手戻りが少ない |
| 5. 実機連動 | バックグラウンド復帰 / バッテリー実測は実機運用が前提のため、Sprint 7 で「Sprint 6 の機能を jun さん側で実機運用してもらった結果」をフィードバックして仕上げると品質が上がる |

### 3-5. B 案のキャパシティ評価

- Sprint 6: 9 チケット（Sprint 5 同等）
- Sprint 7: 7 チケット（Sprint 5 比 12% 減）
- 評価: **両 sprint とも余裕あり**。QA フェーズで Critical/High が出ても吸収可能

---

## 4. 推奨案の表明

### PO/SM 推奨: **B 案（2-sprint 分割）**

### 根拠（3 点）

1. **Sprint 4 / 5 で連続発生した Critical/High が、Sprint 6 でも同型再発する確率は依然として高い**
   - Sprint 5 retro 最優先 Try「DI 経路カバレッジテストの定型化」は Sprint 6 で初めて運用に乗る。仕組みが効くかは「やってみないと分からない」フェーズ。Sprint 6 で新規サービス（Dropbox / DB クリア / DB 自動消去）を 3 つ同時投入すると、テスト定型化が効く前に同型バグが出るリスクがある
   - B 案なら Sprint 6 で 1 回試行 → Sprint 7 で運用補正という 2 段階の品質ガードが効く

2. **「機能完成」と「リリース仕上げ」は性質が違うので、QA 観点の集中が利く**
   - Sprint 6（機能完成）は「コードが想定通り動くか」が観点 → ユニットテスト中心
   - Sprint 7（リリース仕上げ）は「申請プロセスが詰まらないか」が観点 → ドキュメント整備 + 実機連動 + 配布前チェック中心
   - 性質が違うので 1 sprint に詰めると QA 観点が散り、観点 1 つあたりの掘り下げが浅くなる

3. **jun さん側の Apple Developer Program 加入 / 実機保有状況に依存する作業を Sprint 7 に集約できる**
   - プライバシーマニフェストの最終チェック、アプリアイコンの実機表示確認、App Store 申請メタデータのスクリーンショット取得は実機 / archive ビルドが必要
   - jun さん側の準備状況次第で Sprint 7 のキックオフタイミングを調整できる
   - Sprint 6 はその間にコード面の完成を進められる

### B 案にあたって考慮した jun さん側の制約

| 制約 | B 案での扱い |
|---|---|
| 1. Apple Developer Program 加入状態 | 未加入なら Sprint 7 着手前に加入が必要（年間 99 USD）。加入済なら Sprint 7 を即着手可能 |
| 2. 実機 (iPhone) の有無 | 実機があると Sprint 7 の S7-002（アイコン実機確認）/ S7-003（バックグラウンド復帰）/ TestFlight 配布が現実的になる。実機が無い場合は Sprint 7 でシミュレータレベルの担保にとどまる |
| 3. 配布タイミング目標 | jun さんが「いつまでに App Store に出したいか」によって判断が変わる。**急ぐ場合は A 案、品質優先なら B 案** |
| 4. 個人利用優先度 vs 公開優先度 | CLAUDE.md は「基本自分専用、有効であれば販売や広告月で無料配布」と記載。公開を急がないなら B 案で品質を取るのが合理的 |
| 5. Sonnet 化 + メイン代行運用 | Sprint 5 までと同じ。Sprint 6 / 7 ともに変更なし |

### A 案を採用するべきケース

- jun さんに「Sprint 6 末で App Store 申請を急ぐ」明確な意思がある
- 多少のリスクを許容して 1 sprint で押し切る合意がある
- Should 系（DB クリア / DB 自動消去 / `AppDependencyContainer` / ローンチスクリーン）は v1.1 で追加して構わない判断がある

---

## 5. jun さんに確認したい事項（承認時に回答いただきたい）

承認時に以下を回答いただけると、A/B どちらを採用するかが確定します:

### 5-1. 配布タイミング目標
- A: 急ぎたい（Sprint 6 末で App Store 申請したい）
- B: 急がない（品質を優先して Sprint 7 まで使いたい）
- C: そもそも自分用のみで App Store 公開しない（その場合 M4〜M6 の優先度を下げて A 案を更に縮小可能）

### 5-2. Apple Developer Program 加入状態
- A: 加入済み
- B: 未加入（年間 99 USD で加入予定）
- C: 加入予定なし（自分用のみ・TestFlight も使わない）

### 5-3. 実機 (iPhone) の有無
- A: あり、テスト用に使える
- B: 普段使い iPhone はあるが、テスト用にビルドを入れるのは抵抗あり
- C: なし（シミュレータのみで完結する範囲で進める）

### 5-4. アプリアイコンのデザイン
- A: jun さんが画像を用意する
- B: SwiftUI で簡易プロトタイプを作って初回リリース、後で差し替え
- C: Designer エージェントに依頼（生成方針は別途相談）

### 5-5. Should 系の取り扱い（A 案を選んだ場合のみ）
- A: DB クリア / DB 自動消去を初回リリースに入れない（v1.1 で追加）= 推奨
- B: A 案でも DB クリア / DB 自動消去を入れたい（その場合チケット 12 件、QA 余裕ゼロ）

---

## 6. ドラフト承認後のフロー

### A 案承認の場合
1. このドラフトを `plan.md` にリネーム → 「ドラフト」表記を削除して整形
2. `.scrum/config.md` の `current_sprint: 6` / `sprint_phase: development` に更新
3. `.scrum/sprint-6/board.md` を作成（10 チケット）
4. `.scrum/tickets/S6-001.md` 〜 `S6-010.md` を作成
5. GitHub Issues 起票（10 件、ラベル `sprint-6`）
6. Dev-1 / Dev-2 のサブエージェント起動 → 着手順序に従って development フェーズ開始

### B 案承認の場合
1. このドラフトを `plan.md` にリネーム → Sprint 6 部分のみ抽出して整形（Sprint 7 部分は別途 `sprint-7/plan-draft.md` を Sprint 6 完了時に作成）
2. `.scrum/config.md` の `current_sprint: 6` / `sprint_phase: development` / `estimated_sprints: 7` に更新（**6 → 7 への変更が必要**）
3. `.scrum/sprint-6/board.md` を作成（9 チケット）
4. `.scrum/tickets/S6-001.md` 〜 `S6-009.md` を作成
5. GitHub Issues 起票（9 件、ラベル `sprint-6`）。Sprint 7 分は Sprint 6 完了時に起票
6. Dev-1 / Dev-2 のサブエージェント起動 → development フェーズ開始

---

## 7. 着手順序の推奨（A 案 / B 案 共通の Sprint 6 部分）

### Phase 0: 承認取得 + 着手準備
1. jun さんから A/B 案の判断 + 5-1〜5-5 の回答を取得
2. PO/SM が `dev-completion-checklist.md` を改訂（**M3 / S6-003**: DI 検証テスト追加チェック項目）
3. PO/SM が `RootViewIntegrationTests.swift` の DI 検証テスト 1 件を「雛形コメント」化

### Phase 1: 必須繰越 + プロセス改善（Dev-2 主導）
1. **S6-002** Info.plist gitignore + `.example` パターン化（軽量で依存なし、Dev-2 ウォームアップ）
2. **S6-003** DI 経路カバレッジテスト定型化（PO/SM が並行で完了）
3. **S6-001** Dropbox SDK 軽量実装 + OAuth PKCE（Sprint 5 Google Drive 実装パターン継承）

### Phase 2: 機能 / UI（Dev-1 / Dev-2 並行）
1. Dev-1: **S6-005**（A 案）or **S6-005 + S6-006**（B 案）クラウド UI / DB クリア
2. Dev-2: **S6-006 / S6-007**（A 案 = バッテリー / 復帰）or **S6-007 / S6-008**（B 案 = DB 自動消去 / バッテリー）

### Phase 3: リリース系（A 案のみ）/ DI 構造改善（B 案のみ）
- A 案: Dev-2 が **S6-004** プライバシーマニフェスト / Dev-1 が **S6-005** アイコン
- B 案: Dev-1 が **S6-004** `AppDependencyContainer` 導入

### Phase 4: 余裕枠
- A 案: **S6-010** retryCount 方針判断（Should）
- B 案: **S6-009** retryCount 方針判断（Should）

---

## 8. Sprint 5 retro Try の Sprint 6 への反映状況

| # | retro Try | Sprint 6 ドラフトでの反映 |
|---|---|---|
| 1 | DI 経路カバレッジテストを `dev-completion-checklist.md` に組み込む（最優先） | **A 案 M3 / B 案 S6-003 として Must 化** |
| 2 | `AppDependencyContainer` 導入で `RootView.init` 整理 | **A 案では Should（見送り推奨）/ B 案では S6-004 として Must** |
| 3 | Info.plist の OAuth 設定を gitignore + `.example` パターン化 | **A 案 M2 / B 案 S6-002 として Must** |
| 4 | CloudUploadRetryQueue の CSV 出力失敗時挙動整理（QA-S5-004） | **A 案 S6-010 / B 案 S6-009 として Should** |
| 5 | シミュレータ動作確認シナリオを `simulator-scenarios.md` に集約 | **両案で Sprint 6 中に PO/SM が継続更新（チケット化せず運用）** |
| 6 | Sprint 6 開始時に Task ツール可否を再確認 | **両案で planning_review 冒頭に試行（実施済 = 本ドラフト作成時に確認したが、scrum-dev / qa-multi-agent ともに従来通り Single-Agent / メイン代行運用で進行する想定）** |
| 7 | 節目ハンドオーバー更新の順序テンプレ化 | **両案で `.claude-handover.md` の冒頭テンプレに反映（チケット化せず運用）** |
| 8 | Dev フェーズ完了直後に push 候補を提示する運用 | **両案で運用継続（チケット化せず PO/SM が遵守）** |
| 9 | Sonnet 化の効果検証を継続 | **両案で sprint review に「Sprint 4 / 5 / 6 (/ 7) のメトリクス比較」テーブル追加** |

---

## 9. パッケージ追加の事前承認（Sprint 5 と同パターン）

`autonomous-rules.md` の「パッケージの追加・削除は要承認」に従い、Dropbox SDK の取り扱いを確認:

### Dropbox 連携の実装方針

| 案 | 内容 | 評価 |
|---|---|---|
| α | 公式 Dropbox SDK（Swift Package）を追加 | バイナリ +5〜10 MB。OAuth が安定 |
| β | **Apple 純正のみで自前実装**（Sprint 5 Google Drive と同パターン） | バイナリ増ゼロ。OAuth PKCE / トークンリフレッシュ / Keychain は Sprint 5 で確立済 |

**PO/SM 推奨: β 案**。理由:
1. Sprint 5 で Google Drive を Apple 純正のみで動かし切った実績がある
2. `CloudStorageProvider` プロトコルを Sprint 5 で抽象化済みのため、Dropbox は同パターンで実装可能
3. SPM 依存追加ゼロを継続できる（保守性 / バイナリサイズ / 審査リスク）

jun さんが「Dropbox は公式 SDK で安定運用したい」と判断する場合は α 案を採用するが、その場合の追加リスク（Dropbox 側の API 変更で SDK 更新待ちが発生する可能性）を共有のうえ判断いただきたい。

---

## 10. 完了基準（Sprint 6 全体 / A 案・B 案共通）

- [ ] 全チケットが Done（A 案 = 10 件 / B 案 = 9 件）
- [ ] スプリントゴール検証条件が静的に確認可能（A 案 = 7 項目 / B 案 = 5 項目）
- [ ] フル再ビルド warning 0 / error 0
- [ ] ユニットテスト pass 100%
- [ ] Sprint 1〜5 のテスト 173 件の回帰なし
- [ ] API キー漏洩スキャン 0 件
- [ ] DI 検証テストが新規サービスに対して必須化されている（M3 / S6-003 効果確認）
- [ ] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得 + git push 承認）

---

## 11. このドラフトの位置づけ（再掲）

- **このドラフトはまだ正式 plan ではない**
- jun さんが A / B / 修正案 / リジェクトの判断をするための材料
- 承認後、PO/SM がメインセッションで以下を実施:
  - `plan.md` への昇格 + 整形
  - GitHub Issue 起票
  - `.scrum/config.md` の `current_sprint` / `sprint_phase` / `estimated_sprints` 更新
  - `.scrum/sprint-6/board.md` 作成
  - `.scrum/tickets/S6-XXX.md` 作成

承認時の回答テンプレ（コピペ用）:

```
A/B 案の判断: ___（A or B）
配布タイミング目標: ___（5-1 の選択肢）
Apple Developer Program 加入状態: ___（5-2 の選択肢）
実機 (iPhone) の有無: ___（5-3 の選択肢）
アプリアイコンのデザイン方針: ___（5-4 の選択肢）
A 案を選んだ場合の Should 系: ___（5-5 の選択肢、A 案を選んだ場合のみ）
Dropbox の実装方針: ___（α or β、PO/SM 推奨は β）
その他コメント: ___
```

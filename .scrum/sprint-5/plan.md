# Sprint 5 Plan

- スプリント期間: 2026-05-06 開始（1 イテレーション完結予定）
- 体制: PO/SM (Opus) + Dev x2 (Dev-1 / Dev-2 / Sonnet) + QA（qa-multi-agent / Single-Agent モード見込み）
- リポジトリ: junhnam/iOS-GPSlog（main ブランチ・Sprint 4 まで origin と同期済 = 892e195）
- 現在のフェーズ: **planning_review**（jun さん承認待ち）

---

## スプリントゴール

> **移動記録をクラウドストレージに自動同期し、機器を変えても残せる状態にする**

達成判定:

| # | 判定基準 | 確認方法 |
|---|---|---|
| 1 | クラウド保存先（Google Drive / Dropbox）を選び、OAuth 認証ができる | S5-001 / S5-002 / S5-003 のテスト + シミュレータ実機確認 |
| 2 | 自動同期 ON 時、記録停止のたびに「GPSログ/{日付}/data.csv」階層へ CSV がアップロードされる | S5-004 / S5-005 のテスト + 実 OAuth 環境でのアップロード確認（jun さん側） |
| 3 | アップロード失敗時にリトライキューが動き、5 回失敗で通知が出る | S5-006 のテスト |
| 4 | PinRecord に address フィールドが追加され、CalendarSyncService の 3 段フォールバック（placeName → address → 座標）が文言通りに動く | S5-007 のテスト + コード静的レビュー |
| 5 | フル再コンパイルで warning 0 件（既存の MapView Coordinator warning 1 件解消含む） | `xcodebuild clean build` の警告ゼロ確認 + S5-008 のテスト |

ユニットテスト + 静的レビューで 1〜5 を担保し、jun さん側のシミュレータ確認（特に実 OAuth 認証）は別途依頼する。

---

## スプリントバックログ

| ID | タイトル | type | 見積 | 担当 | 優先度 | 備考 |
|---|---|---|---|---|---|---|
| S5-001 | Google Drive SDK 導入 + OAuth 認証 | feature | L→分割可 | dev-2 | must | **要 jun さん事前承認（パッケージ追加）** |
| S5-002 | Dropbox SDK 導入 + OAuth 認証 | feature | L→分割可 | dev-2 | should | **要 jun さん事前承認（パッケージ追加）。Sprint 6 へ繰越も選択肢** |
| S5-003 | クラウド保存先選択 UI | feature | M | dev-1 | must | S5-001（必要なら S5-002）依存 |
| S5-004 | 自動同期 ON/OFF 設定 | feature | S | dev-1 | must | S5-003 依存 |
| S5-005 | 「GPSログ/{日付}/data.csv」階層での自動アップロード | feature | M | dev-2 | must | S5-001 / S5-003 / S5-004 / S4-005 依存 |
| S5-006 | 同期失敗時のリトライ + 通知 | feature | M | dev-2 | must | S5-005 依存 |
| S5-007 | PinRecord.address 追加 + addressFromPlaceURL 実体化（QA-S4-002 解消） | chore | M | dev-2 | must | **jun さん指示で取り込み確定** |
| S5-008 | MapView Coordinator strict concurrency warning 解消 | chore | S | dev-1 | should | Sprint 4 申し送り #1 |
| S5-009 | テスト群の @MainActor strict concurrency warning 解消 | chore | M | dev-1 | could | Sprint 4 申し送り #2。余裕枠で吸収 |

合計: **9 チケット**（Must 6 / Should 2 / Could 1）。
- Sprint 5 で **Dropbox を入れない** 場合: S5-002 を Sprint 6 へ落とし **8 チケット**（Must 5 / Should 2 / Could 1）
- Sprint 4 と同等のキャパシティ（8 チケット）を Must 中心で組んだうえで、Could 1 件を余裕枠として配置

---

## 担当分割の方針（ファイル競合ゼロ）

### Dev-1（UI / 設定 / View 系）

- 新規ファイル: `Features/Settings/CloudStoragePickerView.swift`
- 既存ファイル拡張: `Features/Settings/SettingsView.swift`（「データ」セクションに「クラウド同期先」「自動同期」追加）
- 既存ファイル拡張: `Features/Map/MapView.swift`（S5-008 の Coordinator warning 解消のみ）
- テスト群: `GPSLoggerTests/*.swift` の `@MainActor` 修飾整理（S5-009、Could）
- 担当チケット: **S5-003 / S5-004 / S5-008 / S5-009**

### Dev-2（サービス / ロジック / モデル / クラウド I/O 系）

- 新規ファイル:
  - `Services/Cloud/CloudStorageProvider.swift`（共通プロトコル）
  - `Services/Cloud/GoogleDriveSyncService.swift`
  - `Services/Cloud/DropboxSyncService.swift`（S5-002 取り込み時のみ）
  - `Services/Cloud/CloudUploadCoordinator.swift`
  - `Services/Cloud/CloudUploadRetryQueue.swift`
  - `Models/PendingUpload.swift`（SwiftData @Model）
- 既存ファイル拡張:
  - `Models/PinRecord.swift`（`address: String?` 追加）
  - `Models/AppSettings.swift`（`cloudProviderKind` / `cloudAutoSyncEnabled` 追加）
  - `Services/Place/PlaceLookupService.swift`（address 書き戻し）
  - `Services/Calendar/CalendarSyncService.swift`（addressFromPlaceURL 削除）
  - `Services/Location/LocationService.swift`（記録停止時の CloudUploadCoordinator 呼び出し）
- 担当チケット: **S5-001 / S5-002 / S5-005 / S5-006 / S5-007**

### 共有ファイル（事前合意）

- `Models/AppSettings.swift`: Dev-2 が S5-003 着手前に `cloudProviderKind` / `cloudAutoSyncEnabled` を追加 → Dev-1 が S5-003 / S5-004 で UI バインドのみ参照
- `Features/Settings/SettingsView.swift`: Dev-1 が S5-003 / S5-004 で「データ」セクション 2 行を追加（Dev-2 は触らない）
- `Features/Map/MapView.swift`: Dev-1 が S5-008 のみ。Dev-2 は触らない
- `Services/Calendar/CalendarSyncService.swift` + `Services/Place/PlaceLookupService.swift` + `Models/PinRecord.swift`: Dev-2 が S5-007 で 3 ファイル横断編集（Dev-1 は触らない）

git 競合 0 件を Sprint 3 / 4 から継続する。

---

## 着手順序の推奨

### Phase 0（jun さん承認待ち、開発着手前）

1. **planning_review**: jun さんから以下を取得
   - パッケージ追加承認（Google Drive SDK / Dropbox SDK）
   - Dropbox を Sprint 5 で入れるか / Sprint 6 へ落とすか
   - Sprint 5 のスプリントゴール / バックログの最終承認

承認取得後、Dev-2 が Phase 1 に着手。

### Phase 1（Dev-2 主導 / クラウド基盤）

1. **S5-007（PinRecord.address 追加）**: 軽量で依存なし。Dev-2 が S5-001 着手前にウォームアップとして先に潰す（Sprint 4 申し送りクリア）
2. **S5-001（Google Drive SDK 導入 + OAuth）**: Dev-2 が SPM 依存追加 → Info.plist 設定 → GoogleDriveSyncService 実装
3. **S5-002（Dropbox SDK 導入 + OAuth）**: 取り込まれる場合のみ。S5-001 と同パターンで実装
4. **S5-005（自動アップロード）**: S5-003 / S5-004 完了後、CloudUploadCoordinator 実装
5. **S5-006（リトライ + 通知）**: S5-005 完了後

### Phase 2（Dev-1 並行 / UI 系）

1. **S5-003（クラウド保存先選択 UI）**: Dev-2 が S5-001 / S5-002 を完了させ AppSettings 拡張をコミットしたら Dev-1 着手
2. **S5-004（自動同期 ON/OFF 設定）**: S5-003 完了後
3. **S5-008（MapView Coordinator warning 解消）**: 並行可能（依存なし）。Dev-1 が S5-004 待ちの間に着手
4. **S5-009（テスト群 warning 解消）**: 余裕枠。S5-008 完了後

### Phase 3（QA フェーズ移行前）

- Dev-2 が S5-005 / S5-006 完了 → Dev-1 が S5-008 / S5-009 完了 → 全 board.md チケット Done
- メインエージェント（Opus）が `xcodebuild clean build` で warning 0 / error 0 を確認
- `.scrum/config.md` の `sprint_phase` を `qa` に更新

---

## Dev フェーズ完了基準（Sprint 5 から運用開始）

`.scrum/process/dev-completion-checklist.md` を遵守する。要点:

1. ユニットテスト pass
2. 静的解析 warning 0
3. **`xcodebuild clean build` で warning 0**（**Sprint 5 から必須**。Sprint 4 retro Try / jun さん指示）
4. ビルドエラー 0
5. iOS 26 API 変更点ノートとの整合
6. board.md 状態更新
7. git commit

### Sonnet サブエージェントの xcodebuild 代行運用（Sprint 5 限定）

jun さんの明示指示「グローバル設定を変えるのは怖いので、引き続き Opus で代行する形で対応してください」により以下を継続:

- Dev エージェント（Sonnet）は xcodebuild を試みない
- メインエージェント（Opus）が `xcodebuild clean build` を代行実行
- Dev エージェントは「ビルド確認をお願いします」とメインに要請

詳細は `.scrum/process/dev-completion-checklist.md` を参照。

### Dev エージェントへのプロンプト雛形

各 Dev サブエージェント起動時に以下を必ずプロンプトに含める:

```
- ビルド (xcodebuild) はメインエージェント (Opus) が代行する。あなた (Dev エージェント, Sonnet) は試みないこと
- ユニットテスト追加・xcodegen・コード編集は自分で行う
- 自チケット完了前にメインエージェントへ「ビルド確認をお願いします」と要請する
- メインがビルド結果（warning 数・error 数）を返したら、warning 0 / error 0 を確認のうえ Done に更新する
- iOS 26 API 変更点は .scrum/notes/ios26-api-changes.md を必ず参照する
- 新規 API 採用時は「置換 API 自体も deprecated 化されているか」を 2 段先まで確認する
- Dev 完了基準は .scrum/process/dev-completion-checklist.md を必ず参照
```

---

## パッケージ追加の事前承認（最重要）

`autonomous-rules.md` の「パッケージの追加・削除は要承認」に従い、Sprint 5 development フェーズ開始**前**に jun さんから以下のいずれかの承認を得る:

### 承認パターン

| 案 | 内容 | バイナリサイズ影響 | OAuth フロー実装負荷 | レビュー時確認事項 |
|---|---|---|---|---|
| A | Google Drive SDK のみ追加（公式 SDK） | +10〜15MB | 公式 SDK で安定 | OAuth クライアント ID の Info.plist 確認 / Keychain トークン保存確認 |
| B | Google Drive のみ + 自前 URLSession 実装 | 増えない | PKCE フロー自前実装が必要 | OAuth フローの単体テスト網羅 / トークンリフレッシュ実装の正しさ |
| C | Google Drive + Dropbox 両方の公式 SDK | +20〜30MB | 公式 SDK 2 つ分 | 両方の OAuth クライアント ID 確認 / Keychain プロバイダ別キー管理 |
| D | Google Drive + Dropbox 両方を自前 URLSession 実装 | 増えない | OAuth 自前実装 x 2 で工数大 | 自前実装の単体テスト網羅 |
| E | 一旦どちらも入れず、CSV を `.fileExporter` 共有経由でユーザー手動アップロード | 増えない | 不要 | Sprint 5 のゴールが「自動同期」から「手動共有経路の整備」に縮小 |

### PO/SM 推奨

**案 A（Google Drive 公式 SDK のみ）+ Dropbox は Sprint 6 へ繰越**を推奨。理由:

1. CLAUDE.md 記載の「Google Drive/Dropbox」は**並列ではなく順次**で問題なく、Google Drive が圧倒的メインユース
2. 公式 SDK は OAuth 周りが安定しており、Sprint 5 の中で 1 プロバイダを完璧に動かす方が品質的に優位
3. Sprint 5 のキャパシティ（Dev x 2 / 8〜9 チケット想定）に Must が 6 件入っているため、Dropbox 追加で Must が 7 件になるとキャパシティ過多
4. Dropbox は Sprint 6 で `CloudStorageProvider` プロトコル経由で追加できるよう、S5-001 / S5-002 / S5-003 の設計で抽象化を確保している

ただし、jun さんが「Dropbox も使いたい」と判断する場合は案 C（両方公式 SDK）を Must で取り込む。その場合 S5-009（テスト warning 解消・Could）は Sprint 6 へ落とす。

### レビュー時の確認事項（追加事項）

- SDK 追加に伴い `Package.resolved` が大きく変わるので diff を確認
- バイナリサイズ確認: Sprint 5 完了時に `xcodebuild` の archive ログから .ipa サイズを記録（Sprint 6 のリリース準備で App Store の最大サイズ制限と照らし合わせる）
- SDK 自体の保守性: 公式 SDK は Apple が iOS 27 で API 変更した場合に Google / Dropbox 側の対応待ちになるリスク。リリース後は SDK のバージョンアップを 6ヶ月に 1 度確認するルールを Sprint 6 retro で検討

---

## Sprint 4 申し送りの取り込み判断（PO/SM 判断）

| # | 観察元 | 内容 | Sprint 5 取込 | 判断理由 |
|---|---|---|---|---|
| 1 | Sprint 4 plan | MapView Coordinator strict concurrency warning | **取込（S5-008）** | クラウド連携と独立で Sprint 5 末尾余裕枠で吸収。Should |
| 2 | Sprint 4 plan | テスト群 53 件の @MainActor warning | **取込（S5-009 / Could）** | 余裕枠で吸収。足りなければ Sprint 6 へ繰越 |
| 3 | QA-S4-002 | PinRecord.address 追加 | **取込（S5-007 / Must）** | jun さん指示で取り込み確定 |
| 4 | Agent A | iOS 26 API 変更点ノートに「置換 API 自体も deprecated か」のチェック観点 | **plan.md / notes に明記**（チケット不要） | Sprint 4 retro で対応済み。Sprint 5 は Dev エージェントプロンプトに反映するのみ |
| 5 | Agent A | Dev フェーズ完了基準に warning チェック追加 | **取込（運用変更 / `dev-completion-checklist.md` 新規作成済）** | jun さん指示で取り込み確定 |
| 6 | PO/SM | EventKit / fileExporter シミュレータ実機確認 | **チケット化不要** | jun さん別途実施。完了報告を待つ |
| 7 | Sprint 3 申し送り | RootView の AppSettings 共有を @Environment へ | **見送り** | Sprint 5 のクラウド連携で RootView を触る必要が出た時に判断（任意） |
| 8 | Sprint 3 申し送り | MKLocalSearch / SLC 実機検証 | **Sprint 6 へ継続** | バッテリー実機検証時に併せて |

---

## バッテリー消費懸念への進捗

Sprint 5 の主スコープ（クラウド同期）は以下の点でバッテリー消費に影響:

- 自動アップロードはユーザー操作トリガー（記録停止）の単発のため、バックグラウンド常時消費の増加要因にはならない
- リトライキュー（S5-006）は `NWPathMonitor` でネットワーク回復時のみ動く。アプリがフォアグラウンド時 or バックグラウンド復帰時のみで、常時動作はしない
- OAuth トークンリフレッシュも記録停止時の単発のため影響なし

→ Sprint 3 で確立したバッテリー対策の枠組みを崩さない設計を維持。

---

## QA フェーズの想定

Sprint 5 の QA で観点として網羅すべき領域:

| 領域 | 想定観点数 |
|---|---|
| OAuth 認証フロー（成功 / 拒否 / トークン期限切れ / リフレッシュ） | 約 25 |
| アップロード成功・失敗（ネットワーク断 / API エラー / 認証期限切れ） | 約 30 |
| リトライキューの永続化と再開（アプリ kill 後 / ネットワーク回復時） | 約 20 |
| 設定画面の UI 状態（プロバイダ選択 / 認証状態 / Toggle disable 条件） | 約 15 |
| PinRecord.address の互換性（既存 DB マイグレーション / nil 動作） | 約 10 |
| CalendarSyncService の 3 段フォールバック（placeName / address / 座標） | 約 10 |
| Coordinator warning 回帰チェック | 約 5 |

→ **合計約 115 観点**（Sprint 4 の 110 と同程度）。Single-Agent QA モード継続見込みのため負荷感は維持。

実 OAuth 認証はユニットテストで再現できないため、**jun さん側のシミュレータ実 OAuth 確認**を依頼項目とする（Sprint 4 と同様）。

---

## モデル切替（Sprint 4 から継続）

| エージェント | Sprint 5 | 備考 |
|---|---|---|
| scrum-po-sm | Opus | 戦略 / 合意形成 / 外部報告 |
| qa-orchestrator | Opus | 観点設計 / 品質判定 |
| scrum-dev-agent | Sonnet | コード実装。**xcodebuild はメイン代行（jun さん指示）** |
| qa-implementer / runner / fixer | Sonnet | 観点実装 / 実行 / 修正 |
| scrum-designer | Sonnet | Sprint 5 では未使用想定 |

---

## 完了基準（Sprint 5 全体）

- [ ] 全 8〜9 チケット（Must 5〜6 / Should 2 / Could 1）が Done（Could が Sprint 6 繰越なら 7〜8 チケット）
- [ ] スプリントゴール検証条件 5 項目すべて静的に確認可能
- [ ] フル再ビルド warning 0（既存 1 件解消含む）
- [ ] ユニットテスト pass 100%（121 + 約 30〜40 件想定 = 約 150〜160 件）
- [ ] Sprint 1〜4 のテスト 121 件の回帰なし
- [ ] API キー漏洩スキャン 0 件（OAuth クライアント ID は機密ではないがアクセストークン / リフレッシュトークンが Keychain に正しく保存されていることを確認）
- [ ] レビュー / レトロ文書を作成
- [ ] **ユーザー承認**（jun さんからの合意取得・git push 承認）

---

## planning_review で jun さんから取得すべき判断

1. **パッケージ追加承認**:
   - 案 A〜E のいずれを採用するか（PO/SM 推奨は案 A: Google Drive 公式 SDK のみ）
2. **Dropbox の Sprint 5 取り込み有無**:
   - 取り込む = S5-002 を Must に / 取り込まない = Sprint 6 へ繰越
3. **Dev フェーズ完了基準の warning 0 チェック**:
   - **取り込み確定**（jun さん明示指示）。本 plan で `.scrum/process/dev-completion-checklist.md` 新規作成済みのため、最終文面の確認のみ
4. **Sonnet サブエージェントの xcodebuild 代行運用**:
   - **継続確定**（jun さん明示指示）。本 plan / `dev-completion-checklist.md` で文書化済みのため、運用合意のみ
5. **S5-007（PinRecord.address 追加）の取り込み**:
   - **取り込み確定**（jun さん明示指示）。受け入れ条件と CSV 出力スキーマへの影響（A 案: 列追加なし / B 案: 列追加）の判断のみ planning_review で確認

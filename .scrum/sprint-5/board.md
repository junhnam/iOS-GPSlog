# Sprint 5 Board

## Sprint Goal

> **移動記録をクラウドストレージに自動同期し、機器を変えても残せる状態にする**

期間: 2026-05-06 開始
フェーズ: **QA 完了 / review 移行直前**（jun さん承認取得済 / Google Drive のみ・Dropbox は Sprint 6 繰越）

QA 結果: **【条件付き合格】→ ビルド確認済で正式合格**（QA-S5-001/002 を Single-Agent モードで即時修正 → `0f17622` で commit、`xcodebuild clean test` で 173/173 pass / TEST SUCCEEDED）

---

## Todo

（なし）

## In Progress

（なし）

## Done

- [x] **S5-001**: Google Drive SDK 導入 + OAuth 認証 → **dev-2** / Must / L (コミット `8c43aaf` / warning 0 / テスト追加 4+)
- [x] **S5-003**: クラウド保存先選択 UI → **dev-1** / Must / M (コミット `3cc209e` / warning 0 / テスト追加 7)
- [x] **S5-004**: 自動同期 ON/OFF 設定 → **dev-1** / Must / S (コミット `3cc209e` / warning 0 / テスト追加 5)
- [x] **S5-005**: 「GPSログ/{日付}/data.csv」階層での自動アップロード → **dev-2** / Must / M (コミット `14f4936` / warning 0 / テスト追加 5+)
- [x] **S5-006**: 同期失敗時のリトライ + 通知 → **dev-2** / Must / M (コミット `14f4936` / warning 0 / テスト追加 4+)
- [x] **S5-007**: PinRecord.address 追加 + addressFromPlaceURL 実体化（QA-S4-002 解消） → **dev-2** / Must / M (コミット `d1d1476` / warning 0 / テスト追加 8)
- [x] **S5-008**: MapView Coordinator strict concurrency warning 解消 → **dev-1** / Should / S (コミット `8051930` / warning 0 / テスト追加 0)
- [x] **S5-009**: テスト群の @MainActor strict concurrency warning 解消 → **dev-1** / Could / M (コミット `1ae29e9` / warning 0 / 12 ファイルの setUp/tearDown を async 版に統一)

- ~~**S5-002**: Dropbox SDK 導入 + OAuth 認証~~ → **Sprint 6 へ繰越**（jun さん承認 / Issue #36 sprint-6 ラベル）

---

## メイン代行修正（Dev エージェントの sandbox 制約により Opus メインが代行）

| コミット | 内容 |
|---|---|
| `f2cc406` | Cloud 系コードを internal で統一 + iOS 26 deprecated 解消 + 復旧時バックオフ無視 |
| `a45a2f3` | テストの async-safe ロックと FakeHTTPClient 引数順序 |
| `1ae29e9` | テスト群 setUp/tearDown を async 版に統一（S5-009 として） |
| `0f17622` | **QA-S5-001/002 修正**: RootView で CloudUploadCoordinator/RetryQueue を生成・LocationService に注入。`.task` で起動時 RetryQueue 処理 + ネットワーク監視を発火。回帰テスト 1 件追加。Sprint 5 リリースブロッカー解消 |

---

## 着手順序メモ（履歴）

### Dev-2（クラウド I/O / モデル / ロジック）

1. S5-007（PinRecord.address。ウォームアップ・依存なし）→ Done
2. AppSettings 拡張（cloudProviderKind / cloudAutoSyncEnabled）→ Done (`a2d915f`)
3. S5-001（Google Drive SDK / jun さん承認後）→ Done
4. S5-005（自動アップロード）→ Done
5. S5-006（リトライ + 通知）→ Done

### Dev-1（UI / 設定）

1. S5-008（MapView warning 解消・依存なし）→ Done
2. S5-003（保存先選択 UI / S5-001 完了後）→ Done
3. S5-004（自動同期 Toggle / S5-003 完了後）→ Done
4. S5-009（テスト warning 解消 / 余裕枠・Could）→ Done

---

## ビルド状態スタンプ

`.scrum/process/dev-completion-checklist.md` の運用に従い、各チケット Done 時に以下を記入:

| チケット | 担当 | コミット | フル再ビルド warning | 追加テスト数 |
|---|---|---|---|---|
| S5-001 | dev-2 | 8c43aaf | 0 (メイン代行確認済) | 4+ |
| S5-002 | dev-2 | Sprint 6 繰越 | - | - |
| S5-003 | dev-1 | 3cc209e | 0 (メイン代行確認済) | 7 |
| S5-004 | dev-1 | 3cc209e | 0 (メイン代行確認済) | 5 |
| S5-005 | dev-2 | 14f4936 | 0 (メイン代行確認済) | 5+ |
| S5-006 | dev-2 | 14f4936 | 0 (メイン代行確認済) | 4+ |
| S5-007 | dev-2 | d1d1476 | 0 (メイン代行確認済) | 8 |
| S5-008 | dev-1 | 8051930 | 0 (メイン代行確認済) | 0 |
| S5-009 | dev-1 | 1ae29e9 | 0 (メイン代行確認済) | 0（既存 12 ファイルを async 版に統一） |

## ステータスサマリ

| 状態 | 件数 |
|---|---|
| Todo | 0 |
| In Progress | 0 |
| Done | 8 |
| Sprint 6 繰越 | 1 (S5-002) |
| **Sprint 5 完了** | **8/8** |

---

## 最終テスト結果

- ユニットテスト: **173/173 pass**（Sprint 4 末 121 → Sprint 5 末 172 → QA 修正で +1 → 173 件）
- ビルド: warning 0 / error 0（Swift コード由来）
- 既存 121 ユニットテストの回帰: なし
- QA Single-Agent モード: 130 観点 / Critical 4（実態 1 つの統合バグ）+ High 1 を検出 → **修正済 + ビルド確認済**
- 残存バグ: Critical/High 0、Medium 1（QA-S5-003: Info.plist プレースホルダー / jun さん側オペレーション）、Low 1（QA-S5-004: CSV 出力失敗時 retryCount / Sprint 6 改善候補）

# Sprint 5 Board

## Sprint Goal

> **移動記録をクラウドストレージに自動同期し、機器を変えても残せる状態にする**

期間: 2026-05-06 開始
フェーズ: **planning_review**（jun さん承認待ち）

---

## Todo

- [ ] **S5-007**: PinRecord.address 追加 + addressFromPlaceURL 実体化（QA-S4-002 解消） → **dev-2** / Must / M
- [ ] **S5-001**: Google Drive SDK 導入 + OAuth 認証 → **dev-2** / Must / L→分割可 / **要 jun さん事前承認**
- [ ] **S5-002**: Dropbox SDK 導入 + OAuth 認証 → **dev-2** / Should / L→分割可 / **要 jun さん事前承認・Sprint 6 繰越選択肢あり**
- [ ] **S5-003**: クラウド保存先選択 UI → **dev-1** / Must / M
- [ ] **S5-004**: 自動同期 ON/OFF 設定 → **dev-1** / Must / S
- [ ] **S5-005**: 「GPSログ/{日付}/data.csv」階層での自動アップロード → **dev-2** / Must / M
- [ ] **S5-006**: 同期失敗時のリトライ + 通知 → **dev-2** / Must / M
- [ ] **S5-008**: MapView Coordinator strict concurrency warning 解消 → **dev-1** / Should / S
- [ ] **S5-009**: テスト群の @MainActor strict concurrency warning 解消 → **dev-1** / Could / M

## In Progress

（なし）

## Done

（なし）

---

## 着手順序メモ

### Dev-2（クラウド I/O / モデル / ロジック）

1. S5-007（PinRecord.address。ウォームアップ・依存なし）
2. S5-001（Google Drive SDK / jun さん承認後）
3. S5-002（Dropbox SDK / 取り込まれた場合のみ）
4. S5-005（自動アップロード / S5-003 / S5-004 完了待ち）
5. S5-006（リトライ + 通知 / S5-005 完了待ち）

### Dev-1（UI / 設定）

1. S5-008（MapView warning 解消・依存なし）→ Dev-2 が S5-001 進行中の間に並行
2. S5-003（保存先選択 UI / S5-001 完了待ち）
3. S5-004（自動同期 Toggle / S5-003 完了待ち）
4. S5-009（テスト warning 解消 / 余裕枠・Could）

---

## Dev-1 ↔ Dev-2 申し送りメモ

### AppSettings 拡張

- Dev-2 が S5-001 着手前に `cloudProviderKind: CloudProviderKind?` と `cloudAutoSyncEnabled: Bool` を `Models/AppSettings.swift` に追加し commit
- 該当 commit がプッシュ（main にマージ）された時点で Dev-1 は S5-003 / S5-004 に着手可能

### CalendarSyncService の addressFromPlaceURL 削除

- Dev-2 が S5-007 で削除する。Dev-1 が CalendarSyncService を触る予定はないため競合なし

### MapView.swift

- Dev-1 が S5-008 で Coordinator のみ編集
- Dev-2 は MapView を触らない約束

---

## ビルド状態スタンプ（Dev フェーズ完了時に Dev が記入）

`.scrum/process/dev-completion-checklist.md` の運用に従い、各チケット Done 時に以下を記入:

| チケット | 担当 | コミット | フル再ビルド warning | 追加テスト数 |
|---|---|---|---|---|
| S5-001 | dev-2 | - | - | - |
| S5-002 | dev-2 | - | - | - |
| S5-003 | dev-1 | - | - | - |
| S5-004 | dev-1 | - | - | - |
| S5-005 | dev-2 | - | - | - |
| S5-006 | dev-2 | - | - | - |
| S5-007 | dev-2 | - | - | - |
| S5-008 | dev-1 | - | - | - |
| S5-009 | dev-1 | - | - | - |

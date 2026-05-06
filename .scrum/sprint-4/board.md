# Sprint 4 Board

最終更新: 2026-05-06（planning 完了時点）

## Sprint Goal

> **移動記録を外部に持ち出せる状態を作る（カレンダー連携 + CSV 出力）**

---

## Todo

- [ ] S4-003: 滞留ピン → カレンダーイベント自動作成 → dev-2
- [ ] S4-004: カレンダー同期 ON/OFF 設定 → dev-1
- [ ] S4-005: CSV エクスポート機能（DBスキーマそのまま出力） → dev-2
- [ ] S4-006: UIDocumentPickerViewController での保存先選択 → dev-1
- [ ] S4-007: エクスポート UI 画面 → dev-1

## In Progress

- [~] S4-002: EventKit 連携基盤（権限取得 + カレンダー選択） → dev-2

## Review

- [x] S4-001: CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002 解消） → dev-2（実装完了 / レビュー待ち）
- [x] S4-008: MapView HUD warning ロジックを HomeDetector へ統一 → dev-1（実装完了 / レビュー待ち）

## Done

（PO/SM 確認後に更新）

---

## メモ

- 着手順は plan.md「着手順序の推奨」を参照
- ファイル分割と共有ファイルの合意は plan.md「担当分割の方針」を参照
- Dev-2 は S4-001 を最優先で着手（jun さん指示）
- Dev-1 は S4-008（HUD 統一）から着手可能（依存なし）
- AppSettings に新規プロパティを追加する際は Dev-1 / Dev-2 双方で事前共有

## Dev-1 → Dev-2 申し送り（2026-05-06 12:00）

- S4-008（HUD 統一）と S4-006（CSVExportDocument / DocumentPickerView の先行実装）のソースは
  完了済。テスト 5 ケース新規追加（HomeDetector に bannerMessage 系 3 ケース、CSVExportDocument
  に 4 ケース、DocumentPickerView Coordinator に 2 ケース）。
- ただし `HomeRegistrationView.swift:198` で `MKReverseGeocodingRequest`(?) に対する
  `preferredLocale:` の引数で **コンパイルエラー** が残っている（`extra argument 'preferredLocale' in call`）。
- Dev-1 は S4-001 の領域に手を入れない約束のため修正できない。
  Dev-2 に修正をお願いし、修正後に Dev-1 側でテスト実行 → コミットを行う。

## Dev-2 → Dev-1 申し送り（2026-05-06 12:30）

- 上記コンパイルエラーを **修正コミット 3b046fb** で対応済（preferredLocale 引数を削除し
  端末ロケールに任せる方針へ変更）。Dev-1 側でテスト実行を続けて問題ありません。
- S4-002 着手にあたり `AppSettings.swift` に以下を追加予定（Dev-1 の S4-004 でこの値を UI バインドする想定）:
  - `var calendarSyncEnabled: Bool`（既定 false） / Keys: `gpslogger.settings.v1.calendarSyncEnabled`
  - `var calendarIdentifier: String?`（既定 nil） / Keys: `gpslogger.settings.v1.calendarIdentifier`
  - 後方互換: 既存テスト 8 ケースは破らない（読み込み時に値が無ければデフォルトに fallback）

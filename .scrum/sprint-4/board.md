# Sprint 4 Board

最終更新: 2026-05-06（planning 完了時点）

## Sprint Goal

> **移動記録を外部に持ち出せる状態を作る（カレンダー連携 + CSV 出力）**

---

## Todo

- [ ] S4-002: EventKit 連携基盤（権限取得 + カレンダー選択） → dev-2
- [ ] S4-003: 滞留ピン → カレンダーイベント自動作成 → dev-2
- [ ] S4-004: カレンダー同期 ON/OFF 設定 → dev-1
- [ ] S4-005: CSV エクスポート機能（DBスキーマそのまま出力） → dev-2
- [ ] S4-006: UIDocumentPickerViewController での保存先選択 → dev-1
- [ ] S4-007: エクスポート UI 画面 → dev-1

## In Progress

- [~] S4-008: MapView HUD warning ロジックを HomeDetector へ統一 → dev-1

## Review

- [x] S4-001: CLGeocoder → MKReverseGeocodingRequest 移行（QA-S3-002 解消） → dev-2（実装完了 / レビュー待ち）

## Done

（PO/SM 確認後に更新）

---

## メモ

- 着手順は plan.md「着手順序の推奨」を参照
- ファイル分割と共有ファイルの合意は plan.md「担当分割の方針」を参照
- Dev-2 は S4-001 を最優先で着手（jun さん指示）
- Dev-1 は S4-008（HUD 統一）から着手可能（依存なし）
- AppSettings に新規プロパティを追加する際は Dev-1 / Dev-2 双方で事前共有

# Sprint 2 Board

## Sprint Goal

> アプリを閉じても、経路・ピン・総移動距離が復元できる状態を作る。

---

## Todo

- [ ] S2-006: 滞留検出（10分・30m半径）と PinRecord 作成 → dev-2
- [ ] S2-008: 履歴タブ実装（日付一覧 + 詳細） → dev-2

## In Progress

- [~] S2-007: アプリ起動時の最新 TripRecord 復元 → dev-1

## Review

- [r] S2-001: SwiftData モデル定義（TripRecord / RoutePoint / PinRecord） → dev-1
- [r] S2-002: ModelContainer セットアップとアプリ統合 → dev-1
- [r] S2-003: TripRepository（取得・作成・更新・距離加算） → dev-1
- [r] S2-004: 総移動距離計算ロジック（CLLocation.distance ベース） → dev-2
- [r] S2-005: LocationService と DB の連携（永続化 + 距離加算） → dev-2

## Backlog（途中起票）

- [b] S2-101: TripDistanceCalculator の東京-新宿テストが期待値とずれて失敗（bug） → dev-2

## Done

（なし）

---

## メモ

- Dev-1 の依存チェーン: S2-001 → S2-002 → S2-003 → S2-007
- Dev-2 の依存チェーン: S2-004 → S2-005 → S2-006 → S2-008
- S2-005 は S2-003 完了後（Dev-1 と Dev-2 の合流点）
- S2-007 / S2-008 はそれぞれ前段が揃ってから着手

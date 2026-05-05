# Sprint 2 Board

## Sprint Goal

> アプリを閉じても、経路・ピン・総移動距離が復元できる状態を作る。

---

## Todo

（なし）

## In Progress

（なし）

## Review

（なし）

## Backlog（途中起票）

- [b] S2-101: TripDistanceCalculator の東京-新宿テストが期待値とずれて失敗（bug） → dev-2 (修正済 commit a4e9f3f)
- [b] S2-102: TripRecord SwiftData @Relationship クラッシュ（bug） → dev-1 (修正済 commit 35eb5f3)
- [b] S2-103: LocationServiceTests container 強参照漏れによる SIGTRAP（bug） → dev-2 (修正済 commit f85478a)

## Done

- [x] S2-001: SwiftData モデル定義（TripRecord / RoutePoint / PinRecord） → dev-1 (commit 85277b0)
- [x] S2-002: ModelContainer セットアップとアプリ統合 → dev-1 (commit ce206c1)
- [x] S2-003: TripRepository（取得・作成・更新・距離加算） → dev-1 (commit be6aeec)
- [x] S2-004: 総移動距離計算ロジック（CLLocation.distance ベース） → dev-2 (commit ab863a2)
- [x] S2-005: LocationService と DB の連携（永続化 + 距離加算） → dev-2 (commit c8f9d4d)
- [x] S2-006: 滞留検出（10分・30m半径）と PinRecord 作成 → dev-2 (commit a9f8ded)
- [x] S2-007: アプリ起動時の最新 TripRecord 復元 → dev-1 (commit 8dea581)
- [x] S2-008: 履歴タブ実装（日付一覧 + 詳細） → dev-2 (commit pending)

---

## メモ

- Dev-1 の依存チェーン: S2-001 → S2-002 → S2-003 → S2-007 すべて完了
- Dev-2 の依存チェーン: S2-004 → S2-005 → S2-006 → S2-008 すべて完了
- 検証: 全 44 ユニットテスト pass、xcodebuild test SUCCEEDED

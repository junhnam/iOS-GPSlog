# Sprint 1 Board

## Sprint Goal
iOS シミュレータ上で、現在地を地図に表示し、移動経路を青いラインで描画できる状態を作る。

## Todo
- [ ] S1-002: Swift Package Manager 設定 + Google Maps SDK 導入 → dev-1
- [ ] S1-003: Info.plist に位置情報・バックグラウンド権限を設定 → dev-1
- [ ] S1-004: アプリエントリポイント + ナビゲーション骨格 → dev-1
- [ ] S1-005: LocationManager サービス実装 (Core Location ラッパー) → dev-2
- [ ] S1-006: Google Maps ビュー（現在地表示） → dev-2
- [ ] S1-007: 移動経路ライン描画（Polyline） → dev-2
- [ ] S1-008: メイン画面 UI モック作成（SwiftUI プロトタイプ） → designer
- [ ] S1-009: README にビルド・実行手順を追記 → dev-1

## In Progress
（なし）

## Review
- [r] S1-001: Xcode プロジェクト雛形作成 (SwiftUI / iOS 26+) → dev-1

## Done
（なし）

---

## 担当別サマリ
| 担当 | チケット数 | 見積合計（SMサイズ） |
|---|---|---|
| dev-1 | 5 | M+M+S+S+S |
| dev-2 | 3 | M+M+M |
| designer | 1 | M |

## 状態更新ルール
- Dev / Designer が着手するときに `Todo → In Progress` に移動
- 完了したら `In Progress → Done` に移動
- バグ発見など差し戻し時は `Review → In Progress` に戻し、必要なら新規バグチケットを起票

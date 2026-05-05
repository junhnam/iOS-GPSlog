# Sprint 1 Board

## Sprint Goal
iOS シミュレータ上で、現在地を地図に表示し、移動経路を青いラインで描画できる状態を作る。

## Todo
（なし）

## In Progress
- [~] S1-009: README にビルド・実行手順を追記 → dev-1

## Review
（なし）

## Done
- [x] S1-001: Xcode プロジェクト雛形作成 (SwiftUI / iOS 26+) → dev-1 (commit 3922c81)
- [x] S1-002: Swift Package Manager 設定 + Google Maps SDK 導入 → dev-1 (commit 3948feb)
- [x] S1-003: Info.plist に位置情報・バックグラウンド権限を設定 → dev-1 (commit 5992d54)
- [x] S1-004: アプリエントリポイント + ナビゲーション骨格 → dev-1 (commit f0db7ec)
- [x] S1-008: メイン画面 UI モック作成（SwiftUI プロトタイプ） → designer (commit 52240de)
- [x] S1-005: LocationManager サービス実装 (Core Location ラッパー) → dev-2 (commit 6f5ea2e)
- [x] S1-006: Google Maps ビュー（現在地表示） → dev-2 (commit 4b121b0)
- [x] S1-007: 移動経路ライン描画（Polyline） → dev-2 (commit 4b121b0)

---

## Blocker / 申し送り
- [!] このセッション環境に Xcode 本体が未インストール（Command Line Tools のみ）
  - 影響: `xcodebuild` 不可、シミュレータ無し → S1-001/S1-002/S1-003 の「シミュレータで起動」「ビルドが通る」チェックが Dev-1 側で実施できなかった
  - 対応依頼: jun さん側で Xcode（26.0+）を App Store からインストール後、`xcodegen generate` → `open GPSLogger.xcodeproj` → ⌘R で確認をお願いします
  - GoogleMaps の SPM 解決は Xcode 起動時に自動実行されます

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

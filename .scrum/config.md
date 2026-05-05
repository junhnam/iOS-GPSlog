---
project: iOS GPSロガーアプリ
created: 2026-05-05
github_repo: junhnam/iOS-GPSlog
github_url: https://github.com/junhnam/iOS-GPSlog
design_needed: true
estimated_sprints: 6
current_sprint: 3
sprint_phase: planning
---

## プロダクト概要
車などで遠方に出かける際、GPSから自動的に位置情報を記録し、移動経路を可視化するiOSアプリ。
個人利用が主目的だが、品質次第で App Store 公開（販売 or 広告版無料配布）も視野。

## 主要機能
1. 地図上に移動経路を線で表示
2. 10分以上の滞留検出 → ピン記録（お店情報を紐付け）
3. iOSカレンダー同期（いつどこに行ったかを管理）
4. ローカルDBに日付ごとのデータ保持（日付PK / 移動ルート / ピン / 開始終了時刻）
5. CSV エクスポート（ローカル / Google Drive / Dropbox）
6. 設定: 自宅登録、常時/トリガー記録、自動同期、DBクリア、DB自動消去（1GB超）

## 技術スタック（確定事項）
- 言語/UI: Swift + SwiftUI
- 対応OS: iOS 26+
- 地図: Google Maps SDK for iOS（無料・無制限）
- お店情報: Apple MapKit MKLocalSearch（無料・A案）
- 位置情報: Core Location（バックグラウンド対応）
- DB: SwiftData（iOS 17+ 標準）
- カレンダー: EventKit
- クラウド連携: Google Drive SDK / Dropbox SDK（後続スプリント）
- ビルド: Xcode + Swift Package Manager
- テスト: XCTest + iOS シミュレーター（Simulate Location 機能で疑似GPSテスト）

## MVP定義
- Sprint 1〜2 までで「位置情報を取得して地図に経路表示し、滞留時にピンを記録、ローカルDBに保存」が動く状態
- ユーザーがシミュレーターで動作確認できることを目標とする

## 完了条件（プロダクト全体）
- CLAUDE.md に記載された全機能が動作する
- バッテリー消費の懸念が払拭されている（後述の対策が実装済み）
- iOS シミュレーター + 実機で動作確認済み
- App Store 申請可能な品質に達している

## バッテリー消費対策（要件）
常時記録モードでバッテリー消費を抑える方針:
- `CLLocationManager.allowsBackgroundLocationUpdates` + `pausesLocationUpdatesAutomatically`
- `desiredAccuracy` を状況に応じて動的調整（停車中は低精度、走行中は高精度）
- `distanceFilter` で不要な更新を間引く
- Significant Location Changes API（移動検知時のみ起動）の併用
- 自宅滞在時は完全に記録停止（要件通り）

## ブランチ戦略
- main: 本番
- feature/sprint-{N}-{ticket-id}: スプリント別の機能ブランチ
- 例: feature/sprint-1-S1-001

## チケット命名規則
- 形式: S{sprint}-{連番3桁}
- 例: S1-001, S1-002, S2-001

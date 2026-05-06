# Sprint 3 Plan

- 期間: 1 イテレーション（2026-05-06 〜 完了まで）
- 体制: PO/SM + Dev-1 / Dev-2 + QA（Single-Agent モード予定。Sprint 開始時に Task ツール可否を再確認、Sprint 1/2 retro Try）
- 前提: Sprint 2 完了済（origin/main 反映、Issues #1〜#17 クローズ済）

---

## スプリントゴール

> 自宅 / 外出を区別して記録モードを自動切替し、滞留地点に店舗情報を紐付ける。

検証可能な達成条件（Sprint レビュー時に確認するもの）:

1. シミュレータで自宅座標を登録 → 自宅半径内に入ると RoutePoint が記録されない（ログで確認）
2. 自宅から退出 → 通常 GPS が再開し、青い経路ラインが伸びる
3. トリガーモードに切替 → 地図右下に「記録開始」ボタンが現れる
4. 滞留地点でピンが立った時、ピン詳細にお店名（または住所）が表示される
5. アプリ起動時の復元失敗をシミュレートすると、画面に赤い通知が表示される

---

## スプリントバックログ（9 チケット）

| ID | タイトル | 見積 | 担当 | 種別 |
|---|---|---|---|---|
| S3-001 | 設定画面の骨格（List + UserDefaults + AppSettings） | M | dev-1 | feature |
| S3-002 | 自宅位置の登録 UI（地図ピック + 住所 + 候補選択） | M | dev-1 | feature |
| S3-003 | 自宅判定ロジック（半径内で記録自動停止） | M | dev-2 | feature |
| S3-004 | 常時 / トリガー記録モード切替 | S | dev-1 | feature |
| S3-005 | トリガー記録用フローティングボタン | M | dev-1 | feature |
| S3-006 | Significant Location Changes + 動的精度調整 | M | dev-2 | feature |
| S3-007 | MKLocalSearch によるお店情報取得 | M | dev-2 | feature |
| S3-008 | restoreTodayTrip の silent failure を通知化 | S | dev-1 | chore |
| S3-009 | iOS 26 SwiftData 落とし穴ノート作成 | S | dev-1 | chore |

合計サイズ目安: M x 6 + S x 3。Sprint 2 と同等規模。

---

## 担当割り当て方針（ファイル競合回避）

### Dev-1（UI / 設定 / 永続化拡張）
- `GPSLogger/Features/Settings/SettingsView.swift`（新規）
- `GPSLogger/Features/Settings/HomeRegistrationView.swift`（新規）
- `GPSLogger/Features/Map/RecordingToggleButton.swift`（新規）
- `GPSLogger/Models/AppSettings.swift`（新規）
- `GPSLogger/Models/HomeLocation.swift`（新規）
- `GPSLogger/Features/Map/MapViewModel.swift`（既存。restoreError 追加）
- `GPSLogger/Features/Map/MapView.swift`（既存。HUD 追加 + フローティングボタン overlay）
- `.scrum/notes/ios26-swiftdata.md`（新規）

### Dev-2（ロジック / GPS / 外部連携）
- `GPSLogger/Services/Home/HomeDetector.swift`（新規）
- `GPSLogger/Services/Place/PlaceLookupService.swift`（新規）
- `GPSLogger/Services/Location/LocationService.swift`（既存。SLC・精度切替・自宅連携追加）
- `GPSLogger/Services/Trip/StayDetector.swift`（既存。PlaceLookup 呼び出し追加）
- `GPSLogger/Models/PinRecord.swift`（既存。placeName/placeURL 追加）
- `GPSLogger/Features/History/HistoryDetailView.swift`（既存。placeName 表示追加）

### 共有ファイルの取り扱い
- `MapView.swift` は Dev-1 が `RecordingToggleButton` の overlay を、`HUD` の restoreError を追加
- `LocationService.swift` は Dev-2 のみが触る（自宅判定・SLC・精度切替）。Dev-1 は AppSettings 経由で挙動を変える間接 IF を使う
- `PinRecord.swift` は Dev-2 のみ（プロパティ追加）。Dev-1 は HomeLocation など別モデルを担当

---

## 着手順序（依存関係）

```
1. S3-009 (notes)               <- 並列で着手可能（短い）
1. S3-001 (AppSettings 基盤)    <- Dev-1 最初
2. S3-002 (自宅登録 UI)         <- S3-001 後
2. S3-004 (記録モード切替)      <- S3-001 後
3. S3-003 (自宅判定)            <- S3-002 後（Dev-2）
3. S3-005 (トリガーボタン)      <- S3-004 後（Dev-1）
3. S3-007 (お店情報)            <- 並列可（Dev-2）
4. S3-006 (SLC)                 <- S3-003 後（Dev-2）
5. S3-008 (復元通知)            <- 並列可（Dev-1）
```

---

## 品質ゲート

- ビルド warning 0 / error 0（Sprint 2 と同水準）
- ユニットテスト pass 100%
- 各チケットの受け入れ条件を全て満たす
- Sprint 1 / Sprint 2 で導入したテスト（44 件）の回帰なし
- API キー漏洩 0（git 履歴スキャン継続）

---

## バッテリー消費懸念への対応（プロダクト要件）

Sprint 3 で投入する対策:

- 自宅滞在時の完全停止（S3-003 + S3-006）
- Significant Location Changes API 併用（S3-006）
- desiredAccuracy の動的調整（S3-006）
- distanceFilter 10m への切替（S3-006）

Sprint 2 で投入済み（継続）:
- 5m 未満の点間引き（DB 書き込み削減）
- 滞留中の RoutePoint 間引き

Sprint 6 で残予定:
- バックグラウンド復帰時の挙動安定化
- App Store 審査向けバッテリー検証
- pausesLocationUpdatesAutomatically の調整

---

## リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| MKLocalSearch のレート制限 | お店情報取得が止まる | 実装時にエラーハンドリング + フォールバック（住所のみ） |
| Significant Location Changes が実機でしか確認できない | テストカバー不足 | LocationProviderProtocol 抽象化 + ユニットテスト + 実機検証チェックリスト |
| iOS 26 SwiftData の追加落とし穴 | クラッシュ再発 | S3-009 のノートを Sprint 開始前に作成し、新モデル追加時に必ず参照 |
| 自宅登録の住所取得失敗 | UX 劣化 | 住所欠落でも座標保存は可能にする（受け入れ条件で明記） |
| Dev フェーズ完了直後の push 確認漏れ | Sprint 1/2 retro の継続課題 | Dev フェーズ終了後に PO/SM が push 候補をユーザーに提示 |

---

## ユニットテスト計画（最低件数）

| チケット | 最低テスト数 |
|---|---|
| S3-001 AppSettings | 3 |
| S3-002 HomeRegistration | 2 |
| S3-003 HomeDetector | 5 |
| S3-004 記録モード | 1 |
| S3-005 トリガーボタン | 1 |
| S3-006 SLC + 精度 | 4 |
| S3-007 PlaceLookup | 4 |
| S3-008 restoreError | 2 |
| S3-009 notes | 0（ドキュメント） |

合計目安: 22 件（Sprint 2 末で 44 件 → Sprint 3 末で 66 件想定）

---

## 完了基準

- [ ] 全 9 チケットが Done
- [ ] スプリントゴール検証条件 5 項目すべて確認
- [ ] ビルド warning 0、ユニットテスト pass 100%
- [ ] Sprint レビュー / レトロ文書を作成
- [ ] ユーザー（jun さん）の承認取得

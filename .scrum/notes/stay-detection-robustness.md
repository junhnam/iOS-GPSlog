# 滞留検知の堅牢化メモ（S6-010）

最終更新: 2026-05-09（Sprint 6 実機検証 1 回目フィードバック反映）
背景: jun さんの iPhone 16 Pro 実機検証で、喫茶店 1 時間滞在 → ピン履歴に 0 件のままという致命バグを検出。
本ノートは S6-010 の実装担当（dev-2 / Sonnet）が参照する設計指針として作成。

---

## 1. 何が起きていたか（再現シナリオ）

1. jun さんが iPhone 16 Pro でアプリを起動・常時記録 ON
2. 自動車で移動して喫茶店に到着
3. アプリをバックグラウンドに → おそらく数十分後に iOS / OS によりタスクキル
4. 喫茶店に **約 1 時間滞在**
5. 帰宅運転 → アプリ自動再開（SLC 起床経路 / S6-006 の resumeTrackingAfterRelaunch）
6. 帰宅後にピン履歴を確認 → **0 件のまま**

期待動作（CLAUDE.md 要件）: 「10 分以上同じ位置に立ち止まれば、その箇所に自動でピンを差す」。
実際の動作: ピン作成されず。移動軌跡（polyline）のみ正常記録。

---

## 2. 根本原因（2 つの複合）

### 原因 A: iOS の自動停止で位置イベントが来ない

- `LocationService.configureManager()`（`GPSLogger/Services/Location/LocationService.swift` の 178 行目付近）で `pausesLocationUpdatesAutomatically = true`
- ユーザーが静止すると iOS が CLLocationManager の更新を一時停止する
- → 滞留中に `didUpdateLocations` デリゲートが呼ばれない
- → `LocationService.handleNewLocations` → `stayDetector.ingest()` のチェーンが発火しない
- → StayDetector は anchor 設定後、半径外への離脱イベントを永久に受け取れない
- → `.stayEnded` を返す経路に到達できない → PinRecord 作成 0 件

### 原因 B: StayDetector のメモリ状態がタスクキルで蒸発

- `StayDetector` クラス（`GPSLogger/Services/Trip/StayDetector.swift` の 66-72 行目）
  - `anchorLocation: CLLocation?`
  - `stayStartedAt: Date?`
  - `lastInsideAt: Date?`
- 上記はすべてメモリ上の private プロパティ
- アプリが OS にタスクキルされた時点で全消失
- SLC 起床（S6-006）で `LocationService` が再生成されると `StayDetector` も新規 init される
- → 「1 時間前にここに居た」という記憶がない → 帰宅運転で半径外へ出ても「滞留終了」と判定できない

### バッテリー対策との両立制約

C 案として「`pausesLocationUpdatesAutomatically = false`」にすれば原因 A は解消するが、CLAUDE.md「注意事項」のバッテリー懸念に直接反するため不採用（jun さん 2026-05-09 判断）。

---

## 3. 修正方針（B 案 + A 案 / jun さん承認済）

### B 案（本命 / 後追い検知）

**思想**: iOS が止めようがアプリが kill されようが、**記録された RoutePoint の DB ログを後から走査すれば滞留は検出できる**。

- 記録された連続点 `t1, t2` について、`distance(t1, t2) <= 30m` かつ `t2.timestamp - t1.timestamp >= 600s` なら、その間に滞留していたと推定
- iOS の自動停止で間隔が空いた点列はむしろ「静止していた証拠」になる（移動中なら点が密に取れるはずなので、点間隔が大きい = 静止していた可能性が高い）
- タスクキル後に SLC で起床して数点だけ取れた場合も、同じロジックで判定可能

**実装の最小単位**:

```swift
// GPSLogger/Services/Trip/RetroactiveStayDetector.swift（新規）
@MainActor
struct RetroactiveStayDetector {
    let config: StayDetectionConfig

    /// 時系列ソート済みの RoutePoint 配列を受け取り、滞留候補を PinRecord として返す。
    /// trip 紐付けは呼び出し側で行う。冪等性も呼び出し側で確保する。
    func detectStays(from points: [RoutePoint]) -> [PinRecord] {
        // 受け入れ条件 B-1 〜 B-3 を満たす実装
    }
}
```

**発火タイミング**:

1. `LocationService.resumeTrackingAfterRelaunch()` の最後（S6-006 で整備済の経路の中）
2. アプリ手動起動時（`RootView.task` または `AppDependencyContainer` 初期化直後）

### A 案（併用 / StayDetector 状態永続化）

**思想**: B 案だけでも「数分後にピンが立つ」体験は実現できる（移動再開時の SLC 起床で発火）。が、「移動再開直後すぐに前回滞留が確定する」体験を実現するには、StayDetector 自身の状態を再起動間で引き継ぐ必要がある。

- `anchorLocation` の緯度・経度・`stayStartedAt`・`lastInsideAt` を UserDefaults に永続化
- `StayDetector.init` で復元
- `ingest(location:)` で状態が変わるたびに UserDefaults へ書き込み（毎回書き込みでもパフォーマンスは問題にならない / 数十秒〜数分に 1 回程度）
- 古い状態の引きずり防止: `minDuration * 2`（20 分）以上経過した状態は init で破棄

**SwiftData ではなく UserDefaults を選ぶ理由**:

- 単一インスタンスの状態のみ（配列クエリ不要）
- `.scrum/notes/ios26-swiftdata.md` の `@Relationship = []` 落とし穴を避けられる
- 既存 `AppSettings.wasTracking`（S6-006）と同じ思想・同じ場所に集約

### B / A の役割分担

| 検証シナリオ | B 案 | A 案 |
|---|---|---|
| バックグラウンド + iOS 自動停止のみ（タスクキルなし） | 移動再開後数分でピン化 | 移動再開直後にピン化 |
| バックグラウンド + iOS 自動停止 + タスクキル（今回の事例） | 帰宅運転中に SLC 起床 → ピン化 | A 単体では救えない（メモリ蒸発のため） → B が必須 |
| 手動でアプリ kill → 翌朝起動 | アプリ起動時のフルスキャンでピン化 | 状態が古すぎて失効 → B が救う |
| 通常の運転中の店舗滞在 | 既存 StayDetector が発火する想定だが、保険として動作 | 既存 StayDetector が発火 |

**結論: B 案がプライマリ防御線、A 案がセカンダリ（即時性向上）。両方入れる。**

---

## 4. 受け入れ条件（実装担当向け要約）

詳細は `.scrum/tickets/S6-010.md` 参照。要点のみ:

- **B 案ファイル**: `GPSLogger/Services/Trip/RetroactiveStayDetector.swift` 新規
- **B 案発火点**: `LocationService.resumeTrackingAfterRelaunch()` 末尾 + アプリ起動時
- **A 案変更**: `StayDetector` の init / `ingest(location:)` / `_resetForTesting()` を UserDefaults 連携に
- **冪等性**: 既存 PinRecord と座標 +時刻が近接（半径内 + `minDuration / 2 = 300s` 以内）なら新規追加しない
- **DI**: `AppDependencyContainer` で `RetroactiveStayDetector` を生成 → `LocationService` に注入
- **ユニットテスト**: 8 ケース以上（B-1〜B-5 + A-1〜A-3）
- **DI カバレッジテスト**: `RootViewIntegrationTests.swift` に 1 件追加（S6-001 雛形）
- **ビルド**: `xcodebuild clean test` warning 0 / error 0 / 全 pass

---

## 5. ユニットテスト観点（追加検討）

実装担当は最低限以下の観点を網羅すること。

### 後追い検知の決定論性（B 案）

- 同じ入力 RoutePoint 配列に対して **何度実行しても同じ PinRecord 配列を返す**こと
- ランダム要素・現在時刻依存・並行性依存を排除する（純粋関数として実装）
- → これがあれば「実機で 1 回失敗してもログから後追いで救える」運用が確立できる

### 境界値（B 案）

- `minDuration` ちょうど（600.0 秒）→ 滞留として検出されること（`>=` 比較）
- `minDuration - 0.5` → 検出されないこと
- `radius` ちょうど（30.0m）→ 同一アンカーとして扱う
- `radius + 0.5` → 別アンカー扱い

### タスクキルからの復帰（A 案）

- StayDetector に anchor 設定 → 内部状態を取得 → 別インスタンスを同じ UserDefaults で init → 同じ anchor で動作継続することを確認
- 失効: 最終 `lastInsideAt` から 21 分後（`minDuration * 2` 超）の現在時刻で init → 状態が破棄されることを確認

### iOS 自動停止後の復帰

- StayDetector に `t=0` で anchor → `t=1200`（20 分後）に半径外の点を ingest → `.stayEnded` で 1200 秒の滞留として PinRecord 生成（B 案がなくても今の StayDetector で動くはずだが、実機で動いていなかったので回帰テストとして追加）

### 冪等性（共通）

- 既存 PinRecord（座標 X, 時刻 T）が DB に 1 件あるとき、`RetroactiveStayDetector` が同じ X, T 近傍の候補を返しても TripRepository への二重 insert にならないこと
- TripRepository に新規追加する `existingPins(near:around:within:withinSeconds:)` に対するユニットテストも別途追加

### 日付またぎ（B 案）

- 23:50 から翌 01:30 まで同じ場所に滞留（深夜営業の店）→ 当日 + 前日 2 つの TripRecord に分かれて RoutePoint が記録されているケースで、滞留が分断されず 1 件の PinRecord にまとまる（または「前日分」「当日分」の 2 件に分かれても OK だが、決まり事として明示する）
- → 仕様判断: 各日の TripRecord に別々のピンを作る（日跨ぎマージはしない）。理由は CLAUDE.md「DBのテーブルには[日付(主キー)、移動ルート、ピン留めした位置...]」で日付 1 単位を明示しているため

---

## 6. 関連コード位置（dev エージェント向け）

| 項目 | パス | 行 |
|---|---|---|
| 既存 StayDetector | `GPSLogger/Services/Trip/StayDetector.swift` | 全体 |
| pausesLocationUpdatesAutomatically | `GPSLogger/Services/Location/LocationService.swift` | 183 |
| handleNewLocations（StayDetector 呼び出し点） | `GPSLogger/Services/Location/LocationService.swift` | 376-447 |
| resumeTrackingAfterRelaunch | `GPSLogger/Services/Location/LocationService.swift` | 327-361 |
| RoutePoint モデル | `GPSLogger/Models/RoutePoint.swift` | 全体 |
| PinRecord モデル | `GPSLogger/Models/PinRecord.swift` | - |
| TripRepository.appendPin | `GPSLogger/Services/Persistence/TripRepository.swift` | 121-129 |
| TripRepository.recentTrips | `GPSLogger/Services/Persistence/TripRepository.swift` | 89-99 |
| AppSettings.wasTracking（参考: 同じ UserDefaults 永続化思想） | `GPSLogger/Models/AppSettings.swift` | 198-209 |

---

## 7. やってはいけないこと

- `pausesLocationUpdatesAutomatically = false` にする（CLAUDE.md バッテリー懸念違反 / jun さん 2026-05-09 不採用判断）
- StayDetector の状態を SwiftData の `@Model` で永続化する（`ios26-swiftdata.md` の `@Relationship = []` 落とし穴を新規に作る）
- 既存 PinRecord を生成し直して上書きする実装（既存 placeName / placeURL / calendarEventIdentifier を消す可能性）
- バックグラウンドで重い fetch を回す（`recentTrips(limit: 2)` 程度に絞る / アプリ起動時のフルスキャンも 7 日分など制限を入れる）

---

## 8. 関連ドキュメント

- `.scrum/tickets/S6-010.md` 本チケットの正式定義
- `.scrum/sprint-6/board.md` Phase 6 着手順序
- `.scrum/sprint-6/real-device-checklist.md` S6-008 観点 2（MKLocalSearch / ピン化）
- `.scrum/notes/ios26-swiftdata.md` SwiftData 落とし穴（A 案で UserDefaults を選ぶ根拠）
- `CLAUDE.md` 「10 分以上同じ位置に立ち止まれば...」要件 / 「注意事項」バッテリー懸念

---

## 改訂履歴

| 日付 | 内容 |
|---|---|
| 2026-05-09 | 初版（Sprint 6 実機検証 1 回目フィードバックを受けて作成） |

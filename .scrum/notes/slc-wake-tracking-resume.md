# SLC 起床経路で記録を確実に再開するための設計メモ

> 初出: Sprint 6 / S6-015（チケット起票時 / dev-2 並行実装中）
> 適用範囲: iOS 18+ / Swift 6 strict concurrency / `LocationService`（actor）
> 関連: `GPSLogger/Services/Location/LocationService.swift`、`.scrum/tickets/S6-015.md`、`.scrum/tickets/S6-006.md`

---

## TL;DR（先に結論）

1. **SLC（Significant Location Changes）でアプリが起床する経路では、SwiftUI の `scenePhase` は `.active` にならない**。`scenePhase` の変化を発火点にした保険ロジック（`resumeTrackingAfterRelaunch()` 等）は SLC 起床を救えない
2. **`LocationService` のメモリ上プロパティ（`lastHomeState` 等）は、タスクキル / OS による kill / SLC 起床のたびに `.unknown` にリセットされる**。`previous == .atHome` のような「メモリ上の前回状態」を信じる遷移判定は、起床直後には成立しないことを前提にする
3. SLC 起床直後の `didUpdateLocations` 冒頭で「起床経路の検出 + 必要に応じた `resumeTrackingAfterRelaunch()` 呼び出し」を行うのが、scenePhase 非依存の保険ロジックの正解

---

## 何が起きるのか（症状）

S6-015 / 2026-05-11 jun さん実機検証で発覚:

1. 朝、自宅 → 外出（記録 OK / 朝の経路は履歴に残る）
2. 帰宅 → 自宅で停滞（記録停止 / 既存仕様通り）
3. **アプリをタスクキル**（スワイプアップで明示的に終了）
4. その日のうちに自宅から再度外出（**約 40km 移動**）
5. → 期待: SLC 起床 → 通常 GPS 再開 → 経路が記録される
6. → 実際: **完全に拾われなかった**（履歴にゼロ件）

ユーザー視点では「常時記録 ON にしているのに、知らないうちに記録が止まっている」という、本アプリのコア価値を毀損する致命的体験。

---

## 何が起きていたのか（原因）

### 原因 1: `handleHomeStateTransition` の条件不足

`LocationService.swift` の `handleHomeStateTransition`（line 514-527 付近）は以下のような形だった:

```swift
private func handleHomeStateTransition(
    previous: HomeState,
    next: HomeState
) {
    if next == .atHome {
        // 自宅に入った → 通常 GPS を止めて SLC のみに切替
        if isUpdating { manager.stopUpdatingLocation() }
        startSignificantChanges()
    } else if previous == .atHome {  // ← ここが問題
        // 自宅を出た → SLC を止めて通常 GPS を再開
        stopSignificantChanges()
        if !isUpdating { manager.startUpdatingLocation() }
    }
}
```

**通常の使用パターン**（朝の出発など）では、アプリは起動したまま自宅で停滞 → 出発、と遷移するため `previous == .atHome` が成立し、通常 GPS が再開される。

**タスクキル後の SLC 起床**では:
- `lastHomeState`（インスタンスのメモリ上プロパティ）が **`.unknown` にリセットされている**
- SLC で起床して現在位置を取得 → 自宅外と判定 → `next == .away`
- しかし `previous == .atHome` は false（実際は `previous == .unknown`）
- → どちらの分岐にも入らず、通常 GPS が再開されない

### 原因 2: SLC 起床経路で `resumeTrackingAfterRelaunch()` が呼ばれない

S6-006 で導入した保険ロジック `resumeTrackingAfterRelaunch()` は、`UserDefaults` に永続化された `wasTracking` フラグを参照して「前回追跡中だったら復帰」する設計。

しかし発火点が `RootView.onChange(of: scenePhase) { ... if newPhase == .active { ... } }` の 1 箇所のみ。

**バックグラウンド SLC 起床では `scenePhase` が `.active` にならない**ため:
- バックグラウンドで `LocationService` インスタンスが生成される
- `didUpdateLocations` が呼ばれる
- しかし `resumeTrackingAfterRelaunch()` は走らない（scenePhase が変化しないので onChange 発火なし）
- → 保険ロジックが効かないまま、原因 1 の条件不足によって通常 GPS も起動しない

---

## どう書くべきか（修正方針）

### 修正 A: `handleHomeStateTransition` の条件緩和

```swift
private func handleHomeStateTransition(
    previous: HomeState,
    next: HomeState
) {
    if next == .atHome {
        if isUpdating { manager.stopUpdatingLocation() }
        startSignificantChanges()
    } else if next == .away && (previous == .atHome || previous == .unknown) {
        // S6-015: previous == .unknown も含める。
        // タスクキル後の SLC 起床で lastHomeState がメモリから消えた経路を救済する。
        stopSignificantChanges()
        if !isUpdating { manager.startUpdatingLocation() }
    }
}
```

ポイント:
- `previous == .atHome` の既存パスは維持（朝の通常出発）
- `previous == .unknown && next == .away` を追加（タスクキル後の起床）
- `previous == .away && next == .away` はノーオペ（連続的な移動中の冗長呼び出しを防ぐ）

### 修正 B: `didUpdateLocations` 冒頭で SLC 起床経路を検出

```swift
nonisolated func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
) {
    Task { @MainActor in
        await self.handleLocationUpdates(locations)
    }
}

@MainActor
private func handleLocationUpdates(_ locations: [CLLocation]) async {
    // S6-015: SLC 起床経路の検出と保険復帰
    // wasTracking == true（前回追跡中）かつ通常 GPS が止まっている状態は、
    // バックグラウンド SLC 起床の典型パターン。
    // scenePhase に依存せず、ここで resumeTrackingAfterRelaunch() を発火する。
    if appSettings.wasTracking && !isUpdating && !didResumeAfterWake {
        didResumeAfterWake = true
        await resumeTrackingAfterRelaunch()
    }

    // 既存の位置更新処理
    ...
}
```

ポイント:
- `didResumeAfterWake` フラグで「同一プロセス内で 1 回だけ」発火する
- `appSettings.wasTracking` は `UserDefaults` 永続化されているので、タスクキル後も読める
- scenePhase に依存しないので、バックグラウンド SLC 起床でも確実に走る

### 修正 C: ユニットテスト 2 件以上

- `.unknown → .away` 遷移で `startUpdatingLocation` が呼ばれることの検証（修正 A の回帰防止）
- `didUpdateLocations` 経路で `resumeTrackingAfterRelaunch` が呼ばれることの検証（修正 B の回帰防止）

---

## なぜ `lastHomeState` を永続化しないのか（設計判断）

選択肢として「`lastHomeState` も `UserDefaults` に永続化する」案もあった。が、**採用しない**。

理由:

1. **古い状態を信じるリスク**: 長時間アプリ未起動の間に、jun さんが物理的に自宅から離れた場所に移動している可能性がある。`UserDefaults` に書かれた `lastHomeState == .atHome` を信じてしまうと、起床直後に「今も自宅にいる」と誤判定して通常 GPS を起動しない事故が起きる
2. **現在位置から都度判定する方が堅牢**: SLC 起床時は必ず `didUpdateLocations` で現在位置が来る。それを使って `homeJudgement(coordinate: current)` を都度評価し、`.away` なら通常 GPS を起動、`.atHome` なら起動しない、という自明な分岐の方が安全
3. **永続化対象を最小に保つ運用ポリシー**: S6-006 で永続化したのは `wasTracking`（ユーザーの意図フラグ）と `StayDetector` の anchor / 開始時刻（S6-010）だけ。「現在状態」系のプロパティはメモリ上に留めて起床時に再計算する方針で統一する

---

## 早期発見のチェックリスト（コードレビュー時）

`LocationService` 周辺を触る際、以下をチェック:

- [ ] 「前回状態」を信じる遷移判定（`previous == .xxx`）は、タスクキル後 / SLC 起床後にも成立するか？
- [ ] 起床経路の発火点が `scenePhase.active` だけになっていないか？（SLC 起床で素通りしないか）
- [ ] バックグラウンド経路で呼ばれる関数が `@MainActor` 越しに actor を呼んでいる場合、Task 切替のタイミングで状態が変わる可能性を考慮しているか？
- [ ] 永続化フラグ（`wasTracking` 等）と非永続フラグ（`lastHomeState` 等）を意図的に区別しているか？

---

## 関連する iOS 26 / Swift 6 の落とし穴（再発防止）

### 1. SwiftUI `scenePhase` とバックグラウンド起床

`@Environment(\.scenePhase)` はあくまで「アプリの UI ライフサイクル」の状態。SLC / region monitoring / silent push などの **バックグラウンドのみの起床経路** では `.active` に遷移しない（`.background` のまま）。

UI ロジックではなく **データ復元 / バックグラウンド処理の発火** には、scenePhase ではなく該当のデリゲート（`CLLocationManagerDelegate.didUpdateLocations` など）を発火点に使うのが正解。

### 2. actor の状態は init 後にゼロから始まる

`LocationService` を `actor` として宣言している場合、メモリ上のプロパティ（`lastHomeState` / `currentDailyRecord` 等）はアプリプロセスごとに毎回初期化される。OS がプロセスを kill して SLC 起床で再生成した場合、それらは「前回の状態」を保持していない。

「前回の状態を継続する必要がある」プロパティは、明示的に `UserDefaults` / Keychain / SwiftData に永続化する必要がある。

### 3. `nonisolated func locationManager(...)` から actor メソッドを呼ぶ際の Task 切替

`CLLocationManagerDelegate` のメソッドは `nonisolated` なので、`LocationService`（actor）のメソッドを呼ぶには `Task { await ... }` で切り替える必要がある。この Task が走る前に別のイベントが入ると順序が前後するので、冪等性（同じ操作を複数回呼んでも壊れない設計）が重要。

特に「保険復帰」系のロジックは、`didResumeAfterWake` のようなフラグで多重発火を防ぐ。

---

## Sprint 7 以降での注意ポイント（po-sm 視点）

`LocationService` の SLC / バックグラウンド経路を触る際は、以下を満たすこと:

- [ ] 新規の状態プロパティを追加する場合、「永続化が必要か」を明示的に判断し、その理由をコードコメントに残す
- [ ] 起床経路の発火点を増やす場合、scenePhase 依存と非依存の両方をカバーする
- [ ] 遷移判定（`previous == ...`）を追加する場合、タスクキル後の `.unknown` 経路を必ず救うか、明示的に「救わない理由」をコメントに残す
- [ ] PR レビューで本ファイルへのリンクをチェック観点に含める

特に Sprint 7 で予定されている可能性のある「省電力モード時の挙動最適化」「複数日跨ぎ復帰の整合性」「region monitoring 併用」等の改修では、本ファイルの設計判断を必ず確認すること。

---

## 参考

- 本プロジェクト履歴:
  - `.scrum/tickets/S6-006.md`（バックグラウンド復帰経路の初版整備）
  - `.scrum/tickets/S6-015.md`（SLC 起床経路の救済 / 本メモの起点）
  - `GPSLogger/Services/Location/LocationService.swift`（line 514-527 周辺の `handleHomeStateTransition`）
- Apple Developer Documentation:
  - "Handling location events in the background" / `CLLocationManager.startMonitoringSignificantLocationChanges()`
  - "Responding to scene-based life-cycle events"（scenePhase は UI ライフサイクル限定の説明）

# SwiftUI `.onDisappear` の落とし穴 — 長寿命サービス制御に使うな

> 初出: Sprint 6 / S6-016（コミット TBD）
> 適用範囲: SwiftUI（iOS 18+ / Xcode 16+ / Swift 6 strict concurrency）
> 関連: `GPSLogger/Features/Map/MapView.swift` / `GPSLogger/Services/Location/LocationService.swift`
> 関連ノート: [`swiftui-state-init-pitfall.md`](./swiftui-state-init-pitfall.md)（S6-014）/ [`slc-wake-tracking-resume.md`](./slc-wake-tracking-resume.md)（S6-015）

---

## TL;DR（先に結論）

- `.onDisappear` は **画面を閉じる時だけでなく、タブ切替やシート遷移など「一時的に View が画面から消える」時にも発火する**
- 位置情報サービス・カレンダー同期・録音などの **長寿命サービス（プロセス全体で 1 つしか存在しないもの）の開始 / 停止制御を `.onDisappear` に書いてはいけない**
- 「画面を表示している間だけ動かす」のは `.onAppear` / `.onDisappear` のペアで正しいが、それは **その View に閉じた副作用** に限る話
- アプリ全体の状態（GPS 記録中 / 録音中 / 同期中 …）は **アプリ全体のライフサイクル**（`scenePhase` / `applicationDidEnterBackground` / 明示的なユーザー操作）で制御する

---

## 何が起きるのか（症状）

S6-016 の jun さん実機検証（2026-05-12）で発覚した挙動:

1. アプリを起動 → 地図タブが表示される → 常時同期 ON のため自動で GPS 記録開始（`wasTracking=true`）
2. 設定タブ or 履歴タブに切り替え → **地図タブの `.onDisappear` が発火**
3. `.onDisappear` 内の `locationService.stopUpdatingLocation()` が走る
4. `stopUpdatingLocation()` の内部で `wasTracking=false` にリセットされ、UserDefaults に永続化される
5. その状態でタスクキル → **`wasTracking=false` のまま永続化が残る**
6. 翌日、アプリ未起動のまま運転 → SLC で起床しても、S6-015 で実装した「`wasTracking=true` なら復帰」ガードが false で発火せず、記録が再開されない
7. **10km 運転しても何も記録されない**

ユーザー視点では「常時同期 ON にしているのに、知らないうちに記録が止まっている」最悪の体験。jun さんは Console.app の実機ログで「iOS 側は GPSLogger に位置情報を正常送信していた」ことを確認しており、アプリ内の経路バグであることが切り分けで確定していた。

---

## 何が起きていたのか（原因）

修正前の `MapView.swift` は以下の形だった:

```swift
.onAppear {
    viewModel.restoreTodayTrip()
    locationService.requestWhenInUseAuthorization()
    locationService.requestAlwaysAuthorization()
    if settings.recordingMode == .continuous {
        locationService.startUpdatingLocation()  // wasTracking=true
    }
}
.onDisappear {
    locationService.stopUpdatingLocation()       // wasTracking=false  ← これがバグの源
}
```

一見すると「画面が表示されている間だけ GPS を動かす」という素直な実装に見える。**しかし `locationService` はアプリ全体で 1 つの長寿命サービスであり、地図タブの可視性とは独立して動くべき存在だった**。

### SwiftUI `.onDisappear` の発火タイミング（実装者の盲点）

SwiftUI の `.onDisappear` は以下のいずれでも発火する:

| シナリオ | `.onDisappear` 発火？ | 開発者の典型的な認識 |
|---|---|---|
| 画面を閉じる（戻る / dismiss） | はい | はい |
| **タブを切り替える（TabView）** | **はい** | **見落としがち** |
| シートやポップオーバーで一時的に覆われる | 条件次第（iOS バージョンで挙動差） | 見落としがち |
| アプリがバックグラウンドに移行 | いいえ（`scenePhase` で扱う） | はい |
| 親 View の再構築（identity 切替） | はい | 見落としがち |

「画面を閉じる時に発火する」と思い込んでいるが、実際は「View がレンダリング対象から外れる時」に発火する。タブ切替もこれに該当する。

### 結果として何が壊れていたか

S6-006 / S6-015 で実装した、タスクキル後の SLC 起床経路（`wasTracking=true` を頼りに記録を再開する保険ロジック群）は、**`wasTracking` が常に正しく維持されている前提** で組まれていた。

しかし `.onDisappear` がタブ切替で発火し `wasTracking=false` を永続化していたため、保険ロジックの入力前提が現実と乖離し、**保険が事実上ゼロ機能** していた。

---

## 何が正解か（修正）

### 1. `.onDisappear` から `stopUpdatingLocation` を削除する

修正後の `MapView.swift`:

```swift
.onAppear {
    viewModel.restoreTodayTrip()
    locationService.requestWhenInUseAuthorization()
    locationService.requestAlwaysAuthorization()
    if settings.recordingMode == .continuous {
        locationService.startUpdatingLocation()
    }
}
// .onDisappear は削除する
```

### 2. 「停止」は別経路で明示する

- **トリガーモード**: `RecordingToggleButton`（floating button）でユーザーが明示的に停止する → `handleRecordingToggle` 経由で `stopUpdatingLocation` が呼ばれる
- **常時同期 + 自宅滞在**: `handleHomeStateTransition` の `.atHome` 経路で `manager.stopUpdatingLocation()` を呼ぶ（`wasTracking` は触らない）
- **常時同期 + 自宅外**: 止まらない（CLAUDE.md 仕様通り）

### 3. バッテリー懸念は S6-005 の `BatteryAdaptiveLocationPolicy` で吸収

- 停車中は低精度 + 大きい `distanceFilter`
- 走行中は高精度に切り替え
- `pausesLocationUpdatesAutomatically = true` を有効化

→ 「タブ切替で止まらない = 常に GPS」という前提でも、バッテリー消費は許容範囲に収まる。

---

## 一般原則 — どこに何を書くべきか

### View ローカルな副作用 → `.onAppear` / `.onDisappear` で OK

例:
- リスト表示時のアナリティクス送信（表示ログ）
- 画面遷移アニメーションのトリガー
- View ローカルなタイマー（その View だけが使う）
- リスト先頭へのスクロールリセット

これらは **その View に閉じている** ため、`.onDisappear` で止めても他に影響しない。

### アプリ全体の状態 → 長寿命オブジェクト + アプリライフサイクルで制御

例:
- 位置情報サービス（`CLLocationManager`）
- カレンダー同期サービス
- 録音サービス
- バックグラウンドアップロードキュー
- クラウド同期サービス

これらは **特定の View の可視性とは独立した寿命** を持つ。制御は以下のいずれかで行う:

| 制御方法 | 用途 |
|---|---|
| `scenePhase` の `.active` / `.background` / `.inactive` の遷移 | アプリ全体のフォアグラウンド / バックグラウンド対応 |
| `UIApplication.applicationDidEnterBackground` 等の通知 | UIKit ライフサイクルが必要な低レベル対応 |
| 明示的なユーザー操作（ボタンなど） | ユーザーが意図して開始 / 停止する場合 |
| サービス自身の状態機械（自宅判定など） | サービス内部の業務ロジックで制御 |
| `UserDefaults` で永続化したフラグ + 起動時に復元 | プロセス再起動を跨いで状態を維持 |

### 紛らわしいケース

- **モーダルシート上で動画再生**: 動画再生は View ローカル → `.onDisappear` で止めて OK
- **設定画面上で BLE スキャン**: スキャンは View ローカル → `.onDisappear` で止めて OK
- **地図タブ表示中だけ通常 GPS**: アプリ全体の中核機能 → **`.onDisappear` で止めるな**（S6-016 の罠）

---

## Sprint 7 以降のチェックリスト（再発防止）

新規 / 既存の View に `.onDisappear` を書く / 残す場合、以下を必ず確認する:

- [ ] その `.onDisappear` で操作している対象は **View ローカルな副作用** か？
- [ ] それとも **アプリ全体の長寿命サービス**（GPS / カレンダー / クラウド同期 / 録音 / 通知 / バックグラウンドキュー …）か？
- [ ] 後者の場合、以下のいずれかに置き換えること:
  - `scenePhase` の `.background` 遷移
  - サービス自身の状態機械
  - 明示的なユーザー操作（ボタン）
  - そもそも止めない（CLAUDE.md の仕様確認）
- [ ] その View は **TabView 配下** か？（YES なら `.onDisappear` はタブ切替でも発火することを意識する）
- [ ] **タブ切替を 5 回繰り返した後の状態** が、初期状態と同じになるか？（特に永続化されるフラグ周り）
- [ ] 関連する `UserDefaults` フラグ（`wasTracking` のような外部から見える状態）が、ユーザーの明示操作以外で変化しないか？

---

## ペアで覚えるべき S6 の罠

S6-014 と S6-016 は両方とも **SwiftUI の「View 再生成 / View 再描画」を理解していない** ことに起因する罠だった:

| チケット | 罠 | 教訓 |
|---|---|---|
| S6-014 | `@State` を `init` で外部値から初期化 → 親の再描画で初期値が再適用される | `@State` はリテラルで初期化し、外部値は `.onAppear` で取り込む |
| S6-016 | `.onDisappear` で長寿命サービスを停止 → タブ切替でも発火し、永続化された状態を壊す | 長寿命サービスは View ライフサイクルではなくアプリライフサイクル / サービス状態機械で制御する |

両方とも「SwiftUI の View ライフサイクルを、UIKit の `viewDidLoad` / `viewDidAppear` / `viewWillDisappear` と同じ感覚で扱った」ことが共通の遠因。SwiftUI では **View は値型で何度でも生成・破棄される** ため、UIKit の感覚で副作用を書くと、特定タイミングで「初期化が走る / クリーンアップが走る」ことに気付かないバグを生む。

---

## 関連コード

- `GPSLogger/Features/Map/MapView.swift:80-110`（S6-016 の修正対象）
- `GPSLogger/Services/Location/LocationService.swift:214-228`（`startUpdatingLocation` / `stopUpdatingLocation` の `wasTracking` 操作）
- `GPSLogger/Services/Location/LocationService.swift:336-368`（`resumeTrackingAfterRelaunch` / `wasTracking=true` ガード / S6-006）
- `GPSLogger/Services/Location/LocationService.swift:520-534`（`handleHomeStateTransition` / `current != .atHome` ＋ `wasTracking=true` ガード / S6-015）
- `GPSLogger/Services/Location/LocationService.swift:791-795`（`didUpdateLocations` 冒頭の `needsResume` 保険経路 / S6-015）

---

## 関連 Sprint 振り返り

- **Sprint 6** で 5 回連続で実機検証フィードバックバグを起票（S6-010 / S6-011 / S6-012 / S6-013 / S6-014 / S6-015 / S6-016）
- バックグラウンド / SLC / 自宅判定 / SwiftUI ライフサイクルといった **シミュレーターで再現困難な領域** に集中している
- 教訓: **個人利用版リリース前の実機検証は必須 / シミュレーターだけでは不十分**
- Sprint 7 以降は、新規 View / サービスの設計レビュー段階で「View ライフサイクルに紐づく副作用」を必ず洗い出すフェーズを入れる

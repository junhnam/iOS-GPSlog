# SLC vs 低精度通常 GPS（自宅滞在中の省電力経路の選択）

> 初出: Sprint 6 / S6-017（2026-05-12〜13 jun さん実機検証で発覚した「SLC 空白ウィンドウ」）
> 適用範囲: iOS 18+ / Swift 6 strict concurrency / `LocationService`（actor）
> 関連: `GPSLogger/Services/Location/LocationService.swift`、`.scrum/tickets/S6-017.md`、`.scrum/tickets/S3-006.md`、`.scrum/notes/slc-wake-tracking-resume.md`

---

## TL;DR（先に結論）

1. **SLC（Significant Location Changes）は「500m〜1km 以上動かないと配信されない」OS 標準仕様**。自宅滞在中の省電力経路として SLC のみに切替えると、**自宅判定半径（例: 70m）と SLC 配信距離（500m〜1km）の差分が「SLC 空白ウィンドウ」になり、その範囲の移動はまったく検出できない**
2. 「省電力 × 自宅出発時の即時検出」を両立する正解は、**通常 GPS を `kCLLocationAccuracyHundredMeters` + `distanceFilter=100m` で稼働させ続ける**こと。家の中で動かない時は `distanceFilter` が配信を抑制するため実質バッテリー消費ゼロ、家を出た瞬間に `didUpdateLocations` が発火する
3. SLC は「**タスクキル後の OS による起床トリガー**」としてのみ価値が高い（S6-015 / S6-006 の経路）。通常起動中の省電力経路として使うべきではない

---

## 何が起きるのか（症状）

S6-017 / 2026-05-12〜13 jun さん実機検証で発覚:

### 事象 1（徒歩）

- 自宅から **直線距離 300m のショッピングモールに歩いて行った**
- 結果: **まったく記録されなかった**

### 事象 2（車）

- 車で出かけた
- 結果: **家を出てから 500m 分くらいは記録されない**（その後は記録される）

### 設定

- 自宅判定半径: **70m**（デフォルト 100m より狭い）

---

## 何が起きていたのか（原因）

`LocationService.swift:274-285` の `startSignificantChangesIfHome`（S3-006）が、自宅滞在中に通常 GPS を **完全停止** し SLC のみに切替えていた:

```swift
func startSignificantChangesIfHome() {
    if isUpdating {
        manager.stopUpdatingLocation()  // ← 通常 GPS を完全停止
        isUpdating = false
    }
    manager.startMonitoringSignificantLocationChanges()  // ← SLC のみ
    isMonitoringSignificantChanges = true
}
```

Apple の SLC 仕様:

> Significant location changes are useful when you want to keep your app informed of the user's location when battery life is a concern. **Apps must move at least 500 meters before a notification is sent.** Notifications come in batches, and the API is most useful for apps that want to keep track of the user's location over long periods.
>
> 出典: Apple CLLocationManager `startMonitoringSignificantLocationChanges` ドキュメント

つまり SLC は **500m〜1km 以上動かないと配信されない**。

### SLC 空白ウィンドウの発生メカニズム

| 状況 | `lastHomeState` | SLC 配信 | 通常 GPS | `handleHomeStateTransition` | 記録 |
|------|----------------|----------|----------|----------------------------|------|
| 自宅 70m 圏内（atHome） | `.atHome` | - | **停止** | - | 停止中（正常） |
| **自宅を出て 70m 〜 500m** | **`.atHome` のまま** | **配信なし** | **停止のまま** | **発火せず** | **欠落（致命）** |
| 自宅 500m〜1km（SLC 配信距離） | `.atHome` → `.away` | 配信 | 再開 | 発火 | 再開 |

70m〜500m の **「空白ウィンドウ」では位置情報がそもそも得られないため、`HomeState` の評価もできず、通常 GPS も再開されない**。

これで jun さんの 2 件の症状が完全に説明できる:
- 徒歩 300m のショッピングモール（**SLC 配信距離 500m 未満**）→ そもそも `.away` 遷移が発火しないため、まったく記録されない
- 車で出発 → 最初の 500m〜1km が SLC 待ちで記録されない

---

## どう書くべきか（選択肢比較）

### 選択肢 A（採用 / S6-017）: atHome 中も低精度通常 GPS を維持

```swift
func startSignificantChangesIfHome() {
    guard let settings = appSettings, settings.homeLocation != nil else { return }
    // SLC は使わない。低精度・大 distanceFilter で通常 GPS を維持。
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 100  // 100m
    if !isUpdating {
        manager.startUpdatingLocation()
        isUpdating = true
    }
}
```

#### メリット

- 自宅 70m 圏外を出た瞬間に `didUpdateLocations` が発火 → 即時に `.atHome → .away` 遷移 → 通常精度に復帰
- 家の中で動かない場合、`distanceFilter=100m` のため CLLocationManager が配信しない → 実質バッテリー消費ゼロ
- 家の中で動く場合（家事 / 室内移動）、100m 移動するまで配信されない → ほぼゼロ
- 設計がシンプル（SLC を呼ばないため経路が一本化される）

#### デメリット

- 厳密には CLLocationManager が稼働しているため、GPS チップへの電力供給は続く（ただし `pausesLocationUpdatesAutomatically=true` が動的に判断する余地あり）
- バッテリー実測が必要（理論値ゼロでも、実機で 1 日放置の検証は推奨）

### 選択肢 B（不採用）: SLC + ジオフェンス併用

```swift
// SLC 開始 + 自宅 70m のジオフェンスを設定
manager.startMonitoringSignificantLocationChanges()
let region = CLCircularRegion(center: home, radius: 70, identifier: "home")
region.notifyOnExit = true
manager.startMonitoring(for: region)
```

#### メリット

- 自宅 70m 圏外に出た瞬間に `didExitRegion` デリゲートが発火 → 即時検出可能
- SLC + ジオフェンスの組み合わせで、ほぼ完全に「家を出た瞬間に通常 GPS 起動」できる

#### デメリット

- iOS のジオフェンス（Region Monitoring）は **デバイスあたり 20 個まで** という上限がある（個人利用版では 1 個で問題ないが、将来「会社」「実家」など複数登録を増やすと衝突する）
- `CLCircularRegion` は OS が要求精度を内部で丸めるため、70m のような小さい半径は **実際には 100m 以上に拡張される** ケースが多い（ユーザー意図と実挙動が乖離する）
- 実装複雑度が高い（SLC / ジオフェンス / 通常 GPS の 3 経路の協調制御）
- テストが書きにくい（ジオフェンスのモック化が SLC より難しい）

### 選択肢 C（不採用）: 自宅判定半径を 500m 以上に強制

- jun さんの「自宅判定半径 70m」設定そのものを禁止し、強制的に 500m 以上にする

#### メリット

- SLC のみのまま実装変更不要

#### デメリット

- 自宅判定が 500m に広がる → マンション / 集合住宅で隣のビル / 駐車場まで「自宅扱い」になり、ピン落ちなどが起きる
- そもそもユーザー設定の自由度を制約する設計は許容しがたい

### 採用判断: 選択肢 A

「SLC 空白ウィンドウ」の根本解消 + 設計シンプル + テスト容易性 + jun さん承認済 のため A を採用。

---

## SLC は何のために残すべきか

SLC は「**タスクキル後の OS 起床トリガー**」としてのみ価値が高い:

- アプリがタスクキルされた状態で 500m 以上移動すると、OS が `UIBackgroundModes: location` を持つアプリを **メモリに復元して `didUpdateLocations` を呼ぶ**
- これが S6-006 / S6-015 で活用している経路

つまり SLC は:

| 用途 | 採用判断 |
|------|---------|
| 自宅滞在中の省電力経路 | **❌ NG**（S6-017 で発覚した空白ウィンドウのため） |
| タスクキル後の OS 起床 | **✅ OK**（500m 移動という配信距離は「すでに自宅から離れた」状態なので問題にならない） |

S6-017 で SLC を完全廃止するか、起床用に最小限残すかは dev-2 の実装判断に委ねるが、以下の方針を推奨:

### 推奨方針

- `startSignificantChangesIfHome` から SLC 開始呼び出しを **完全削除**（選択肢 A）
- 一方、`startUpdatingLocation` を最初に呼ぶタイミング（アプリ起動時 / `RecordingToggleButton` 開始時）で、**併用として `startMonitoringSignificantLocationChanges` を 1 回だけ呼ぶ**
  - これにより通常 GPS と SLC が並走し、`UIBackgroundModes: location` での継続実行が失敗した場合でも SLC で起床できる保険になる
  - ただし「通常 GPS が継続実行で生きている」状態では SLC からの起床は不要 → 二重起床になっても重複処理は冪等にする必要あり（`startTrackingFromSLC` の既存実装は冪等）

最終判断は dev-2 のコード PR で確定する。

---

## バッテリー消費の理論値見積もり

### atHome 中（家の中で動かない）

| 修正前（S3-006） | 修正後（S6-017） |
|-----------------|-----------------|
| SLC のみ（CLLocationManager 待機） | 通常 GPS 稼働（`kCLLocationAccuracyHundredMeters` + `distanceFilter=100m`） |
| 限りなくゼロ | **`distanceFilter=100m` で配信抑止 → 実質ゼロ**（理論上は GPS チップへの待機電力のみ） |

### atHome 中（家の中で家事 / 室内移動）

| 修正前 | 修正後 |
|-------|--------|
| 限りなくゼロ | **100m 移動するまで配信なし → 実質ゼロ** |

### atHome → away 遷移直後

| 修正前 | 修正後 |
|-------|--------|
| 500m〜1km まで待機（その間消費ほぼゼロだが、**ユーザー目的のログも欠落**） | **即時に通常精度復帰 → 通常 GPS と同等の消費** |

### .away 中

| 修正前 | 修正後 |
|-------|--------|
| `BatteryAdaptiveLocationPolicy`（S6-005）が動的精度切替 | **無変更**（S6-005 が継続稼働） |

---

## 実機検証のチェックリスト（S6-008 観点に追加）

S6-017 完了後、jun さん側で以下を確認:

- [ ] 自宅 → 徒歩 300m のショッピングモールに歩く → 移動経路が記録される（自宅 70m 外に出た直後から）
- [ ] 自宅 → 車で出発 → 出発直後の数百メートルから経路が記録される（500m 後のジャンプではなく連続的）
- [ ] 自宅滞在 1 日（外出なし）でバッテリー消費が S3-006 時代と同程度（実測 5% / 24h 以内が許容範囲の目安、計測条件は dev-2 / po-sm で合意）
- [ ] 自宅 → 外出 → 帰宅 → 自宅 70m 圏内に入った時点で精度が低下し、記録が止まる（既存 `.atHome` 自動停止挙動の維持）

---

## Sprint 7 以降の参考資料

新規 `@Model` クラスを追加するときの SwiftData 落とし穴メモ（`.scrum/notes/ios26-swiftdata.md`）と同様、**新規に省電力経路を設計するときは本ノートを参照すること**。

特に以下の罠を覚えておく:

1. **SLC は 500m〜1km 配信距離制約** → 自宅判定半径や、近距離のジオフェンスと組み合わせると空白ウィンドウが発生
2. **シミュレータでは SLC の配信距離制約は再現されにくい** → 実機検証必須
3. **ユニットテストは `CLLocationManager` をプロトコル抽象化したモックで書く**（S3-006 の `LocationProviderProtocol` 経路）が、配信距離の挙動はモックでは検証不能 → モックは API 呼び出し有無のみ確認
4. **「通常 GPS を完全停止 + SLC のみ」は設計アンチパターン**。やるなら「通常 GPS は低精度 + 大 distanceFilter で維持 + SLC は保険として並走」

---

## 関連ノート

- [`ios26-api-changes.md`](./ios26-api-changes.md) — iOS 26 API 変更点
- [`slc-wake-tracking-resume.md`](./slc-wake-tracking-resume.md) — SLC 起床経路で記録を確実に再開するための設計メモ（S6-015）
- [`swiftui-ondisappear-pitfall.md`](./swiftui-ondisappear-pitfall.md) — SwiftUI `.onDisappear` の落とし穴（S6-016）
- [`swiftui-state-init-pitfall.md`](./swiftui-state-init-pitfall.md) — SwiftUI `@State` init アンチパターン（S6-014）

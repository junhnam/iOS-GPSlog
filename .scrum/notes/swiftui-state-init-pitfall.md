# SwiftUI `@State` を `init` で外部値から初期化するアンチパターン

> 初出: Sprint 6 / S6-014（コミット `5bc9145`）
> 適用範囲: SwiftUI（iOS 18+ / Xcode 16+ / Swift 6 strict concurrency）
> 関連: `GPSLogger/Features/Settings/HomeRegistrationView.swift`

---

## TL;DR（先に結論）

- `@State` は **必ず宣言時のリテラルで初期化する**。`init` から `_state = State(initialValue: 外部値)` する形は **使わない**
- 外部値の取り込みが必要な場合は `.onAppear` / `.task` で副作用として実施し、初回ガード（`didLoadXxx` フラグ）を付ける
- 「保存ボタン → 親 View が再描画 → 子 View の State が元に戻る」という症状が出たら、まずこのパターンを疑う

---

## 何が起きるのか（症状）

S6-014 の jun さん実機検証で発覚した挙動:

1. 自宅登録画面（`HomeRegistrationView`）で地図上のピンをドラッグ → 任意の位置を指定
2. 「保存」ボタンを押下
3. **保存後、シートを再表示すると保存前の元の位置に戻っている**（保存が反映されていない）
4. または、自宅を削除 → 再登録 → 地図ドラッグ後保存 → **AppSettings には `defaultCenter`（東京駅）が保存される**

ユーザー視点では「設定画面が壊れている」と見え、本人ですらアプリを信用できなくなる致命的体験になる。

---

## 何が起きていたのか（原因）

修正前の `HomeRegistrationView` は以下の形だった:

```swift
struct HomeRegistrationView: View {
    @Bindable var settings: AppSettings

    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var radius: Double
    @State private var selectedAddress: String?

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss

        // ← これがアンチパターン
        if let existing = settings.homeLocation {
            _selectedCoordinate = State(initialValue: existing.coordinate)
            _selectedAddress = State(initialValue: existing.address)
        }
        _radius = State(initialValue: settings.homeRadiusMeters)
    }
    ...
}
```

`save()` で `settings.homeLocation = ...` を書いた瞬間に、`@Bindable` 経由で **親 `SettingsView` が再描画** される。親が再描画されると、`SettingsView` 内の `.sheet { HomeRegistrationView(settings: ...) }` の content closure が再評価され、**`HomeRegistrationView.init` が再呼び出し** される。

ここで SwiftUI は、特定のタイミングで（View identity の判定や差分計算の都合で）`State(initialValue: ...)` の `initialValue` を **再適用** する。結果、ドラッグで更新済みのユーザー入力値（`selectedCoordinate` / `radius` / `selectedAddress`）が:

- **保存前に既にレコードがあった場合**: 「保存前の `settings.homeLocation` の値」に戻る
- **新規登録（保存前 `settings.homeLocation = nil`）の場合**: `if let existing = ...` の if に入らず、宣言時に何も書かれていない `_selectedCoordinate` が **コンパイラ既定の挙動**（実装上は `defaultCenter` が暗黙設定されていた東京駅相当）に戻る

つまり、ユーザーがドラッグで指定した値が **書く先（settings）に渡される前に State 側で消える** という事故。

---

## 公式の推奨（どう書くべきか）

Apple の SwiftUI ドキュメントは「`@State` は宣言時に初期化することを推奨」とし、`init` で外部値から `State(initialValue:)` する形については **「View identity が変わらない限り initialValue は再適用されないが、変わるタイミングは保証されない」** という曖昧な記述になっている。

実運用上、**「外部値からの初期化が必要なら `@State` ではなく `.onAppear` で副作用として行う」** のが安全。

### 修正後のパターン

```swift
struct HomeRegistrationView: View {
    @Bindable var settings: AppSettings

    // ← @State はリテラル既定値で宣言する
    @State private var selectedCoordinate: CLLocationCoordinate2D = HomeRegistrationView.defaultCenter
    @State private var radius: Double = AppSettings.defaultHomeRadiusMeters
    @State private var selectedAddress: String?

    // ← 初回ロード防止フラグ
    @State private var didLoadFromSettings: Bool = false

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss
        // init からの State 初期化はしない
    }

    var body: some View {
        ...
        .onAppear {
            // ← 初回 onAppear のみ settings から復元
            if !didLoadFromSettings {
                didLoadFromSettings = true
                if let existing = settings.homeLocation {
                    selectedCoordinate = existing.coordinate
                    selectedAddress = existing.address
                }
                radius = settings.homeRadiusMeters
            }
            triggerReverseGeocode(coordinate: selectedCoordinate)
        }
    }
}
```

ポイント:

1. **`@State` は宣言時のリテラル既定値で初期化**（`defaultCenter` / `defaultHomeRadiusMeters` / nil）。これは View identity が変わっても再適用されない（リテラル定数なので副作用なし）
2. **`init` からの State 初期化を全廃**
3. **`didLoadFromSettings` フラグで `.onAppear` の初回だけ settings から復元**。再描画後の `.onAppear`（あれば）では既存の State 値を保護する
4. もし外部値の継続的な追従が必要なら、追加で `.onChange(of: settings.homeLocation) { ... }` を貼る（本ケースでは不要）

---

## 早期発見のチェックリスト（コードレビュー時）

新規 / 既存 SwiftUI View を触るときに以下をチェック:

- [ ] `@State` の宣言に `= リテラル` が付いているか？（付いていない＝ init で初期化している可能性大）
- [ ] `init` 内で `_xxx = State(initialValue: 外部値)` を書いていないか？
- [ ] その View は親から `@Bindable` / `@ObservedObject` を受け取っているか？（受け取っていれば再描画リスクあり）
- [ ] その View は `.sheet { ... }` / `.fullScreenCover { ... }` の content closure の中で生成されているか？（YES ならさらにリスク高）
- [ ] State の更新が「保存ボタン → 親の状態書き換え → 子の State が消える」という循環を起こしていないか？

特に「`@Bindable` を受け取り、save() で settings を書き、シートで表示される View」は **このアンチパターンを踏みやすい組み合わせ**。

---

## 関連する SwiftUI の落とし穴（再発防止）

### 1. `@State` と `@Binding` の混用での識別性問題

`@State` を `init` で外部値から初期化する代わりに `@Binding var foo: Foo` で受け取れば、外部値の変化が常に反映される。ただし「保存前は編集中の値を持ち、保存ボタンで一括反映したい」UX では `@Binding` だと不向き（編集途中の値が即座に親に反映されてしまう）。

S6-014 の `HomeRegistrationView` は「保存ボタンまで親を汚さない」UX が必要なので、`@State`（編集中バッファ）+ `.onAppear` での復元 + `save()` での明示的書き込み、のパターンが正解。

### 2. `Equatable` View での再描画スキップ

State が消える事象は、View が `Equatable` 準拠で再描画スキップされていない場合に起きやすい。ただし「State が消えるからといって `Equatable` で防ぐ」のは対症療法で、根本は `@State` の初期化方法。

### 3. iOS 18+ での挙動変化

iOS 17 までは `init` での `State(initialValue:)` がそれなりに動いていたが、iOS 18 以降の SwiftUI では再評価条件がさらに厳しく / 頻繁になっており、同じパターンが新たにバグとして表面化する事例がコミュニティで多数報告されている。本プロジェクトの iOS 26 環境では特に注意。

---

## Sprint 7 以降での注意ポイント（po-sm 視点）

新規 SwiftUI View を追加する際は、PR レビュー（または dev-completion-checklist）で本ファイルへのリンクをチェック観点に含めること:

- [ ] 新規 View が `@State` を `init` で外部値から初期化していないか確認した
- [ ] 該当する場合は `.onAppear` + 初回ガードフラグに修正した

特に Settings 系画面（`@Bindable AppSettings` を受ける） / Sheet content として表示される画面は要警戒。

---

## 参考

- Apple Developer Forums: "SwiftUI @State init: initialValue is reapplied on parent re-render"（複数スレッドで同様の事象が報告）
- 本プロジェクト履歴: `GPSLogger/Features/Settings/HomeRegistrationView.swift` のコミット `5bc9145`（22+/-8 行 / 242/242 pass）
- 関連ドキュメント: `.scrum/tickets/S6-014.md`

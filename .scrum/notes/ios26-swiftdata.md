# iOS 26 SwiftData / Swift 6 落とし穴メモ

最終更新: 2026-05-06（Sprint 3 プランニング時点）
背景: Sprint 2 で 3 件のバグ（S2-101 / S2-102 / S2-103）を踏んだ反省を、Sprint 3 以降の新規 SwiftData モデル追加時に再発させないため、ナレッジを集約する。本ノートは Sprint 3 の S3-009 で作成された。

---

## 1. `@Relationship` 配列プロパティへの `= []` 既定値必須

### 症状

iOS 26 + Swift 6 環境で `@Model` クラスの `@Relationship` 配列プロパティに既定値を付けないと、初期化時に precondition でクラッシュする。Sprint 2 では S2-001 完了直後の S2-002 統合段階で初めて顕在化（コミット 35eb5f3 で修正）。

### NG（Sprint 2 序盤の記述）

```swift
@Model
final class TripRecord {
    @Attribute(.unique) var date: Date
    @Relationship(deleteRule: .cascade) var routePoints: [RoutePoint]
    @Relationship(deleteRule: .cascade) var pins: [PinRecord]

    init(date: Date, routePoints: [RoutePoint], pins: [PinRecord]) {
        self.date = date
        self.routePoints = routePoints  // ここで precondition クラッシュ
        self.pins = pins
    }
}
```

### OK（Sprint 2 修正後・現状）

```swift
@Model
final class TripRecord {
    @Attribute(.unique) var date: Date
    @Relationship(deleteRule: .cascade) var routePoints: [RoutePoint] = []
    @Relationship(deleteRule: .cascade) var pins: [PinRecord] = []

    init(date: Date) {
        self.date = date
        // routePoints / pins は default 値で初期化済み。後から append する
    }
}
```

### 教訓

- `@Relationship` 配列は **プロパティ宣言時に必ず `= []` を付ける**
- init 内での代入は避ける（後から `routePoints.append(...)` で追加する）
- 関連: コミット `35eb5f3 fix: SwiftData @Relationship 配列に default 値を設定しクラッシュ回避`

---

## 2. テストの `ModelContainer` 強参照保持パターン

### 症状

`ModelContainer` をローカル変数や `_` で受けるとテスト実行のタイミングによって SIGTRAP が発生する。粒度では再現しないが Test Suite 全体実行で出る/出ないが分かれた。Sprint 2 では S2-103 として把握、コミット f85478a で集約。

### NG

```swift
final class TripRepositoryTests: XCTestCase {
    func testTodayTrip() throws {
        let (repo, _) = makeInMemoryRepository()  // _ で container を捨てる
        // テスト中に container が解放されて SIGTRAP
    }
}
```

### OK（Sprint 2 修正後・現状）

```swift
final class LocationServiceTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    override func setUp() {
        super.setUp()
        retainedContainers.removeAll()
    }

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    func testPersistRoutePoint() throws {
        let (repo, container) = makeInMemoryRepository()
        retainedContainers.append(container)  // 寿命を保証
        // テスト本体
    }
}
```

### 教訓

- テストでは `ModelContainer` を `XCTestCase` のプロパティ（配列）で強参照して寿命を保証する
- setUp / tearDown でクリアし、テスト間の汚染を防ぐ
- 関連: コミット `f85478a fix: LocationServiceTests で ModelContainer を強参照保持しクラッシュ回避`

---

## 3. `#Predicate` を避けてメモリフィルタを採用した経緯

### 背景

`TripRepository.trip(on:)` は当初 `#Predicate { $0.date == targetDate }` で実装する想定だったが、Sprint 2 段階では以下の理由でメモリフィルタを採用（コミット be6aeec）。

- iOS 26 / SwiftData 初期で `#Predicate` の Date 比較に予期しない挙動があった（ローカル時間 vs UTC、startOfDay の比較ずれ）
- レコード件数が数十〜数百を想定しており、全件 fetch + メモリフィルタで性能上の問題なし
- メモリフィルタなら Swift コード上で `Calendar.current.startOfDay(for:)` を明示的に揃えやすい

### 現状の実装イメージ

```swift
@MainActor
final class TripRepository {
    private let context: ModelContext

    func trip(on date: Date) -> TripRecord? {
        let descriptor = FetchDescriptor<TripRecord>()
        let all = (try? context.fetch(descriptor)) ?? []
        let target = Calendar.current.startOfDay(for: date)
        return all.first { Calendar.current.startOfDay(for: $0.date) == target }
    }
}
```

### 将来の見直しタイミング

- Sprint 5 で履歴の全期間表示・日付フィルタを実装する際、レコードが増えてからは `#Predicate` への移行を再検討する
- Sprint 2 review.md の申し送り #1 として記録済

---

## 4. Swift 6 strict concurrency の徹底パターン

Sprint 1 で確立し Sprint 2 でも維持しているパターン:

- SwiftData / Repository クラスは `@MainActor` 統一
- `CLLocationManagerDelegate` は `nonisolated` で実装し、コールバック内で `Task { @MainActor in ... }` を使って戻る
- `final actor` よりも `final class @MainActor + nonisolated for delegate` を優先（既存資産との接続が容易）

例:

```swift
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            await handleLocations(locations)
        }
    }
}
```

---

## 5. 新規 SwiftData モデル追加時のチェックリスト（Sprint 3 以降向け）

新しい `@Model` クラスを追加する場合は以下を必ず確認:

- [ ] `@Relationship` 配列プロパティは `= []` 既定値を付ける
- [ ] テストの `ModelContainer` を `retainedContainers` 配列で強参照保持する
- [ ] `@MainActor` または `nonisolated` の方針を明示する
- [ ] `Calendar.current.startOfDay(for:)` などの日時境界処理は Swift コード側で揃える
- [ ] `#Predicate` を使う前にメモリフィルタで動くか比較する
- [ ] 新規プロパティは Optional にして既存 DB との互換を保つ（Sprint 3 の PinRecord.placeName など）

---

## 関連ドキュメント

- `.scrum/sprint-2/review.md` Sprint 2 で発生したバグの詳細
- `.scrum/sprint-2/retro.md` Try セクションに本ノート作成が記載
- `CLAUDE.md` 「注意事項」セクションから本ノートにリンク予定（S3-009 の受け入れ条件）

---

## 改訂履歴

| 日付 | 内容 |
|---|---|
| 2026-05-06 | 初版（Sprint 3 S3-009 で作成） |

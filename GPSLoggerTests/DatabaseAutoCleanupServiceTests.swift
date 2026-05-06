import XCTest
import SwiftData
@testable import GPSLogger

/// DatabaseAutoCleanupService のユニットテスト（S6-004）。
///
/// 容量計測クロージャを Spy に差し替えることで、
/// FileManager / 実ストレージに依存せずに容量閾値ロジックを検証する。
///
/// SwiftData 落とし穴メモ（ios26-swiftdata.md）に従い:
///   - ModelContainer は retainedContainers で強参照保持する
///   - #Predicate を使わずメモリフィルタで全件取得
@MainActor
final class DatabaseAutoCleanupServiceTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run { retainedContainers.removeAll() }
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// テスト用インメモリ ModelContext を生成する。
    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return container.mainContext
    }

    /// テスト用 AppSettings を生成する（独立した UserDefaults スイート）。
    private func makeSettings(
        enabled: Bool = true,
        thresholdGB: Double = 1.0
    ) -> AppSettings {
        let suiteName = "gpslogger.tests.dbcleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.dbAutoCleanupEnabled = enabled
        settings.dbAutoCleanupThresholdGB = thresholdGB
        return settings
    }

    /// 指定した日付オフセット（秒）で TripRecord を 1 件インサートして返す。
    private func insertTrip(
        context: ModelContext,
        daysAgo: Int
    ) throws -> TripRecord {
        let date = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(-daysAgo) * 86_400))
        let trip = TripRecord(date: date, startedAt: date)
        context.insert(trip)
        try context.save()
        return trip
    }

    /// 指定したサイズ（バイト）を返す Spy クロージャを作る。
    private func spyBytes(_ bytes: Int64) -> () -> Int64 {
        return { bytes }
    }

    // MARK: - Tests

    /// しきい値未満の容量では削除されないことを検証する。
    func test_cleanup_underThreshold_doesNothing_S6_004() throws {
        let context = try makeContext()
        let settings = makeSettings(enabled: true, thresholdGB: 1.0)

        // 3 件レコードを投入
        _ = try insertTrip(context: context, daysAgo: 3)
        _ = try insertTrip(context: context, daysAgo: 2)
        _ = try insertTrip(context: context, daysAgo: 1)

        // しきい値 1.0 GB に対して 0.5 GB（未満）を返す Spy
        let halfGB: Int64 = Int64(0.5 * 1_073_741_824)
        let sut = DatabaseAutoCleanupService(
            appSettings: settings,
            modelContext: context,
            measureDBBytes: spyBytes(halfGB)
        )

        try sut.cleanup()

        let descriptor = FetchDescriptor<TripRecord>()
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 3,
            "しきい値未満では TripRecord が削除されない（S6-004）")
    }

    /// しきい値超過時に古い日付から削除されることを検証する。
    func test_cleanup_overThreshold_deletesOldestFirst_S6_004() throws {
        let context = try makeContext()
        let settings = makeSettings(enabled: true, thresholdGB: 1.0)

        // 3 件レコードを投入（3 日前、2 日前、1 日前）
        let oldest = try insertTrip(context: context, daysAgo: 3)
        let middle = try insertTrip(context: context, daysAgo: 2)
        let newest = try insertTrip(context: context, daysAgo: 1)

        // 1 回目の計測は 1.5 GB（超過）、2 回目以降は 0.5 GB（しきい値以下）
        // → 1 件削除して収まる想定
        var callCount = 0
        let thresholdBytes: Int64 = Int64(1.0 * 1_073_741_824)
        let overThreshold: Int64 = Int64(1.5 * 1_073_741_824)
        let underThreshold: Int64 = Int64(0.5 * 1_073_741_824)
        let spyMeasure: () -> Int64 = {
            callCount += 1
            return callCount == 1 ? overThreshold : underThreshold
        }

        let sut = DatabaseAutoCleanupService(
            appSettings: settings,
            modelContext: context,
            measureDBBytes: spyMeasure
        )

        try sut.cleanup()

        let descriptor = FetchDescriptor<TripRecord>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 2,
            "しきい値超過で 1 件削除される（S6-004）")
        XCTAssertFalse(remaining.contains(where: { $0.date == oldest.date }),
            "最も古い TripRecord が削除されている（S6-004）")
        XCTAssertTrue(remaining.contains(where: { $0.date == middle.date }),
            "2 番目に古い TripRecord は残る（S6-004）")
        XCTAssertTrue(remaining.contains(where: { $0.date == newest.date }),
            "最新の TripRecord は残る（S6-004）")
        _ = thresholdBytes
    }

    /// Toggle OFF のとき cleanup() が no-op であることを検証する。
    func test_cleanup_toggleOff_isNoOp_S6_004() throws {
        let context = try makeContext()
        // Toggle OFF（enabled: false）
        let settings = makeSettings(enabled: false, thresholdGB: 1.0)

        // 2 件レコードを投入
        _ = try insertTrip(context: context, daysAgo: 2)
        _ = try insertTrip(context: context, daysAgo: 1)

        // 計測が呼ばれたかを追跡する Spy（Toggle OFF なら呼ばれないはず）
        var measureCalled = false
        let overThreshold: Int64 = Int64(2.0 * 1_073_741_824)
        let spyMeasure: () -> Int64 = {
            measureCalled = true
            return overThreshold
        }

        let sut = DatabaseAutoCleanupService(
            appSettings: settings,
            modelContext: context,
            measureDBBytes: spyMeasure
        )

        try sut.cleanup()

        let descriptor = FetchDescriptor<TripRecord>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 2,
            "Toggle OFF では TripRecord が削除されない（S6-004）")
        XCTAssertFalse(measureCalled,
            "Toggle OFF では容量計測クロージャが呼ばれない（S6-004）")
    }

    /// DB が空のとき cleanup() が no-op であることを検証する。
    func test_cleanup_emptyDatabase_isNoOp_S6_004() throws {
        let context = try makeContext()
        let settings = makeSettings(enabled: true, thresholdGB: 1.0)

        // レコードなし
        let overThreshold: Int64 = Int64(2.0 * 1_073_741_824)
        let sut = DatabaseAutoCleanupService(
            appSettings: settings,
            modelContext: context,
            measureDBBytes: spyBytes(overThreshold)
        )

        // 空 DB で呼び出しても例外が起きないこと
        XCTAssertNoThrow(try sut.cleanup(),
            "DB 空でも cleanup() が例外を throw しない（S6-004）")

        let descriptor = FetchDescriptor<TripRecord>()
        let remaining = try context.fetch(descriptor)
        XCTAssertEqual(remaining.count, 0,
            "DB 空では何も変化しない（S6-004）")
    }

    /// しきい値超過で複数件が削除されることを検証する（追加ケース）。
    func test_cleanup_overThreshold_deletesMultipleRecordsUntilUnderThreshold_S6_004() throws {
        let context = try makeContext()
        let settings = makeSettings(enabled: true, thresholdGB: 1.0)

        // 5 件レコードを投入
        for i in (1...5).reversed() {
            _ = try insertTrip(context: context, daysAgo: i)
        }

        // 最初の 3 回の計測は超過、4 回目は未満 → 3 件削除される想定
        var callCount = 0
        let overThreshold: Int64 = Int64(2.0 * 1_073_741_824)
        let underThreshold: Int64 = Int64(0.3 * 1_073_741_824)
        let spyMeasure: () -> Int64 = {
            callCount += 1
            return callCount <= 3 ? overThreshold : underThreshold
        }

        let sut = DatabaseAutoCleanupService(
            appSettings: settings,
            modelContext: context,
            measureDBBytes: spyMeasure
        )

        try sut.cleanup()

        let descriptor = FetchDescriptor<TripRecord>()
        let remaining = try context.fetch(descriptor)

        XCTAssertEqual(remaining.count, 2,
            "しきい値超過が続く間は複数件を古い順に削除し続ける（S6-004）")
    }
}

import XCTest
import SwiftData
import CoreLocation
@testable import GPSLogger

/// TripRepository のユニットテスト（S2-003）。
/// インメモリ ModelContainer をテストごとに作り直し、
/// 取得 / 作成 / 追加 / 累積距離更新の各経路を独立に検証する。
@MainActor
final class TripRepositoryTests: XCTestCase {

    /// テストごとに作るインメモリ ModelContainer。
    /// **ModelContainer 自体を強参照で保持しないと、内部の ModelContext が
    /// 操作中に解放されてクラッシュするため、必ずプロパティで保持する。**
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: TripRepository!

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        repo = TripRepository(modelContext: context)
    }

    override func tearDown() async throws {
        repo = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - todayTrip

    func test_todayTrip_creatingIfMissingTrue_createsRecordOnFirstCall() throws {
        // setUp で初期化済みの repo / context を利用

        let trip = try repo.todayTrip(creatingIfMissing: true)
        XCTAssertNotNil(trip)
        XCTAssertEqual(trip?.totalDistanceMeters, 0)

        let stored = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(stored.count, 1)
    }

    func test_todayTrip_calledTwice_returnsSameRecord_noDuplicate() throws {
        // setUp で初期化済みの repo / context を利用

        let first = try repo.todayTrip(creatingIfMissing: true)
        let second = try repo.todayTrip(creatingIfMissing: true)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.date, second?.date)

        let stored = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(stored.count, 1, "Same-day trips should not duplicate")
    }

    func test_todayTrip_creatingIfMissingFalse_returnsNilWhenAbsent() throws {
        // setUp で初期化済みの repo を利用
        let trip = try repo.todayTrip(creatingIfMissing: false)
        XCTAssertNil(trip)
    }

    // MARK: - trip(on:)

    func test_trip_on_specificDate_returnsExistingRecord() throws {
        // setUp で初期化済みの repo を利用
        _ = try repo.todayTrip(creatingIfMissing: true)

        let today = Date()
        let found = try repo.trip(on: today)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.date, Calendar.current.startOfDay(for: today))
    }

    // MARK: - appendRoutePoint

    func test_appendRoutePoint_addsToTripCollection() throws {
        // setUp で初期化済みの repo を利用
        let trip = try XCTUnwrap(try repo.todayTrip(creatingIfMissing: true))
        XCTAssertEqual(trip.routePoints.count, 0)

        let p1 = CLLocation(latitude: 35.681236, longitude: 139.767125)
        let p2 = CLLocation(latitude: 35.690921, longitude: 139.700258)

        try repo.appendRoutePoint(p1, to: trip)
        try repo.appendRoutePoint(p2, to: trip)

        XCTAssertEqual(trip.routePoints.count, 2)
    }

    // MARK: - appendPin

    func test_appendPin_addsToTripCollection() throws {
        // setUp で初期化済みの repo を利用
        let trip = try XCTUnwrap(try repo.todayTrip(creatingIfMissing: true))

        let pin = PinRecord(latitude: 35.6,
                            longitude: 139.7,
                            stayedFrom: Date(),
                            stayedDurationSeconds: 720)
        try repo.appendPin(pin, to: trip)

        XCTAssertEqual(trip.pins.count, 1)
        XCTAssertEqual(trip.pins.first?.stayedDurationSeconds, 720)
    }

    // MARK: - updateEnd

    func test_updateEnd_setsEndedAt() throws {
        // setUp で初期化済みの repo を利用
        let trip = try XCTUnwrap(try repo.todayTrip(creatingIfMissing: true))

        let now = Date()
        try repo.updateEnd(of: trip, at: now)

        XCTAssertEqual(trip.endedAt, now)
    }

    // MARK: - updateTotalDistance

    func test_updateTotalDistance_accumulates() throws {
        // setUp で初期化済みの repo を利用
        let trip = try XCTUnwrap(try repo.todayTrip(creatingIfMissing: true))

        try repo.updateTotalDistance(of: trip, addingMeters: 100)
        try repo.updateTotalDistance(of: trip, addingMeters: 200)

        XCTAssertEqual(trip.totalDistanceMeters, 300, accuracy: 0.001)
        // km 換算プロパティの確認も兼ねる
        XCTAssertEqual(trip.totalDistanceKm, 0.30, accuracy: 0.001)
    }

    // MARK: - recentTrips

    func test_recentTrips_returnsDescendingOrder() throws {
        // setUp で初期化済みの repo / context を利用

        // 3 日分のレコードを過去日付で投入
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 0...2 {
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let t = TripRecord(date: d, startedAt: d)
            context.insert(t)
        }
        try context.save()

        let recent = try repo.recentTrips(limit: 10)
        XCTAssertEqual(recent.count, 3)
        // 降順: index 0 が最新
        XCTAssertEqual(recent[0].date, today)
    }

    // MARK: - deleteTrip (S6-003)

    /// 指定日付の TripRecord 1 件を削除し、関連する RoutePoint / PinRecord が
    /// カスケード削除されることを検証する（S6-003）。
    func test_deleteTrip_singleDate_removesRecordAndCascade_S6_003() throws {
        // 2 日分のレコードを投入し、1 件だけ削除して残り 1 件であることを確認する。
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let tripToday = TripRecord(date: today, startedAt: today)
        let tripYesterday = TripRecord(date: yesterday, startedAt: yesterday)
        context.insert(tripToday)
        context.insert(tripYesterday)
        try context.save()

        // RoutePoint と PinRecord を yesterday の TripRecord に紐付ける
        let point = RoutePoint(latitude: 35.681236, longitude: 139.767125,
                               timestamp: yesterday, trip: tripYesterday)
        let pin = PinRecord(latitude: 35.681236, longitude: 139.767125,
                            stayedFrom: yesterday, stayedDurationSeconds: 720)
        context.insert(point)
        try repo.appendPin(pin, to: tripYesterday)
        try context.save()

        // 削除前: RoutePoint / PinRecord が存在する
        let pointsBefore = try context.fetch(FetchDescriptor<RoutePoint>())
        let pinsBefore = try context.fetch(FetchDescriptor<PinRecord>())
        XCTAssertFalse(pointsBefore.isEmpty, "削除前は RoutePoint が存在する")
        XCTAssertFalse(pinsBefore.isEmpty, "削除前は PinRecord が存在する")

        // yesterday を削除
        try repo.deleteTrip(on: yesterday)

        // TripRecord が 1 件（today のみ）になっている
        let remaining = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(remaining.count, 1, "yesterday の TripRecord が削除されている")
        XCTAssertEqual(remaining.first?.date, today, "today の TripRecord は残っている")

        // cascade 削除により RoutePoint / PinRecord も消えている
        let pointsAfter = try context.fetch(FetchDescriptor<RoutePoint>())
        let pinsAfter = try context.fetch(FetchDescriptor<PinRecord>())
        XCTAssertTrue(pointsAfter.isEmpty, "cascade で RoutePoint が削除されている（S6-003）")
        XCTAssertTrue(pinsAfter.isEmpty, "cascade で PinRecord が削除されている（S6-003）")
    }

    /// 全 TripRecord を削除した後、DB が空になることを検証する（S6-003）。
    func test_deleteAllTrips_removesAllRecords_S6_003() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 3 日分のレコードを投入
        for offset in 0...2 {
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let t = TripRecord(date: d, startedAt: d)
            context.insert(t)
        }
        try context.save()

        // 削除前の件数確認
        let beforeCount = try context.fetchCount(FetchDescriptor<TripRecord>())
        XCTAssertEqual(beforeCount, 3, "削除前は 3 件ある")

        // 全削除
        try repo.deleteAllTrips()

        // 全件なくなっている
        let afterCount = try context.fetchCount(FetchDescriptor<TripRecord>())
        XCTAssertEqual(afterCount, 0, "全削除後は 0 件（S6-003）")
    }

    /// 存在しない日付を削除しても no-op になることを検証する（S6-003）。
    func test_deleteTrip_nonexistentDate_isNoOp_S6_003() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 1 件だけ投入
        let t = TripRecord(date: today, startedAt: today)
        context.insert(t)
        try context.save()

        // 存在しない日付（明日）を削除 → エラーが飛ばず no-op
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        XCTAssertNoThrow(try repo.deleteTrip(on: tomorrow),
                         "存在しない日付の削除は no-op でエラーが飛ばない（S6-003）")

        // 既存レコードは消えていない
        let remaining = try context.fetch(FetchDescriptor<TripRecord>())
        XCTAssertEqual(remaining.count, 1, "today のレコードは影響を受けていない（S6-003）")
    }

    /// availableDates が DB に存在する全日付を昇順で返すことを検証する（S6-003）。
    func test_availableDates_returnsAllDates_S6_003() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 5 日分をランダム順で投入
        let offsets = [0, -4, -2, -1, -3]
        var inserted: [Date] = []
        for offset in offsets {
            let d = cal.date(byAdding: .day, value: offset, to: today)!
            let t = TripRecord(date: d, startedAt: d)
            context.insert(t)
            inserted.append(d)
        }
        try context.save()

        let result = try repo.availableDates()

        // 件数が一致している
        XCTAssertEqual(result.count, 5, "availableDates は全件返す（S6-003）")

        // 昇順になっている
        let sortedExpected = inserted.sorted(by: <)
        XCTAssertEqual(result, sortedExpected,
                       "availableDates は昇順で返す（S6-003）")
    }
}

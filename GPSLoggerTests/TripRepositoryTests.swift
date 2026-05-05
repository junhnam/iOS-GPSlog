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

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        repo = TripRepository(modelContext: context)
    }

    override func tearDownWithError() throws {
        repo = nil
        context = nil
        container = nil
        try super.tearDownWithError()
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
}

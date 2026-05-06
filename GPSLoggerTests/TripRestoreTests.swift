import XCTest
import SwiftData
import CoreLocation
@testable import GPSLogger

/// S2-007 のユニットテスト: アプリ起動時の最新 TripRecord 復元。
///
/// 受け入れ条件「事前にリポジトリに TripRecord（RoutePoint x 5, PinRecord x 1,
/// totalDistanceMeters = 1234）を投入し、`restoreTodayTrip()` 後に
/// `route.count == 5`、`pins.count == 1`、`totalDistanceKm == 1.23` を満たす」を検証する。
@MainActor
final class TripRestoreTests: XCTestCase {

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

    func test_restoreTodayTrip_appliesRoutePinsAndDistance() throws {
        // 事前データ投入: 当日の TripRecord に RoutePoint x 5, PinRecord x 1, 距離 1234m
        let trip = try repo.todayTrip()
        // 距離を加算（1234m）
        try repo.updateTotalDistance(of: trip, addingMeters: 1234)
        // 経路点 5 個（時系列を明示的にずらす）
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<5 {
            let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.6 + Double(i) * 0.001,
                                                                    longitude: 139.7),
                                 altitude: 0,
                                 horizontalAccuracy: 5,
                                 verticalAccuracy: 5,
                                 timestamp: base.addingTimeInterval(Double(i) * 60))
            try repo.appendRoutePoint(loc, to: trip)
        }
        // 滞留ピン 1 個（10 分滞留）
        let pin = PinRecord(latitude: 35.65,
                            longitude: 139.7,
                            stayedFrom: base.addingTimeInterval(180),
                            stayedDurationSeconds: 600)
        try repo.appendPin(pin, to: trip)

        // 復元実行
        let viewModel = MapViewModel(repository: repo)
        XCTAssertFalse(viewModel.didRestore)
        viewModel.restoreTodayTrip()

        // 結果検証
        XCTAssertTrue(viewModel.didRestore)
        XCTAssertEqual(viewModel.route.count, 5)
        XCTAssertEqual(viewModel.pins.count, 1)
        XCTAssertEqual(viewModel.totalDistanceKm, 1.23, accuracy: 0.001)

        // 経路は時系列順
        let firstLat = try XCTUnwrap(viewModel.route.first?.latitude)
        let lastLat = try XCTUnwrap(viewModel.route.last?.latitude)
        XCTAssertEqual(firstLat, 35.6, accuracy: 0.0001)
        XCTAssertEqual(lastLat, 35.604, accuracy: 0.0001)

        // ピンの表示文字列は「滞留 約 10 分」
        XCTAssertEqual(viewModel.pins.first?.stayedMinutesText, "滞留 約10分")
    }

    func test_restoreTodayTrip_doesNothing_whenNoTodayRecord() throws {
        let viewModel = MapViewModel(repository: repo)
        viewModel.restoreTodayTrip()

        XCTAssertTrue(viewModel.didRestore)
        XCTAssertTrue(viewModel.route.isEmpty)
        XCTAssertTrue(viewModel.pins.isEmpty)
        XCTAssertEqual(viewModel.totalDistanceKm, 0)
    }

    func test_restoreTodayTrip_isIdempotent_secondCallNoOp() throws {
        // 初回呼び出しでは何もない状態 → didRestore = true
        let viewModel = MapViewModel(repository: repo)
        viewModel.restoreTodayTrip()
        XCTAssertTrue(viewModel.didRestore)
        XCTAssertTrue(viewModel.route.isEmpty)

        // 2 回目以降の onAppear で重ね呼び出しされても、副作用が起きない（早期 return）。
        // 1 回目の後にデータを追加し、もう一度 restore を呼んでも反映されないことを確認。
        let trip = try repo.todayTrip()
        let loc = CLLocation(latitude: 35.6, longitude: 139.7)
        try repo.appendRoutePoint(loc, to: trip)

        viewModel.restoreTodayTrip()
        // 2 回目の呼び出しは早期 return する仕様（onAppear の重複防止）。
        XCTAssertTrue(viewModel.route.isEmpty)
    }
}

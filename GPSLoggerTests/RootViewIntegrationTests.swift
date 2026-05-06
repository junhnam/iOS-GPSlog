import XCTest
import SwiftUI
import CoreLocation
import SwiftData
@testable import GPSLogger

/// QA-S3-001 の回帰防止テスト。
///
/// Sprint 3 の QA で「MapView 内で LocationService を生成すると AppSettings /
/// placeProvider が DI されず、自宅判定 / SLC / MKLocalSearch が本番経路で無効化される」
/// 統合バグが見つかった。修正として RootView 側で LocationService を生成し、
/// AppSettings と同じインスタンスを LocationService に DI している。
///
/// 本テストでは LocationService の生成口（RootView の init 相当）が
/// 「AppSettings を伴った構築」で機能するかをユニットテスト相当で再現する。
@MainActor
final class RootViewIntegrationTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run { retainedContainers.removeAll() }
        try await super.tearDown()
    }

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    /// RootView 相当の構築（AppSettings + LocationService の同居）で
    /// 自宅判定が有効化されることを検証する。
    func test_locationService_constructedWithAppSettings_enablesHomeDetection() throws {
        let repo = try makeInMemoryRepository()

        // RootView.init() と同じ生成順序を再現
        let suiteName = "gpslogger.tests.rootview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        settings.homeLocation = HomeLocation(latitude: 35.681236,
                                             longitude: 139.767125,
                                             address: "Home")
        settings.homeRadiusMeters = 100

        let sut = LocationService(repository: repo,
                                  placeProvider: nil,
                                  appSettings: settings)

        // 自宅座標を流す → atHome 状態になる
        let homeLoc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.681236,
                                                                   longitude: 139.767125),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                 timestamp: Date())
        sut._ingestForTesting([homeLoc])

        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome,
                       "RootView 経路で AppSettings を DI した LocationService は自宅判定が動く")
        XCTAssertEqual(sut.atHomeSkipCount, 1,
                       "atHome 状態で RoutePoint がスキップされている")

        // 自宅外座標を流す → away に遷移して RoutePoint 永続化が再開する
        let awayLoc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 35.700000,
                                                                   longitude: 139.767125),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                 timestamp: Date().addingTimeInterval(60))
        sut._ingestForTesting([awayLoc])

        XCTAssertEqual(sut._lastHomeStateForTesting, .away)

        let trip = try repo.todayTrip(creatingIfMissing: false)
        let unwrapped = try XCTUnwrap(trip)
        XCTAssertEqual(unwrapped.routePoints.count, 1,
                       "away 遷移後の点が永続化されている（自宅滞在中の点はスキップ）")
    }
}

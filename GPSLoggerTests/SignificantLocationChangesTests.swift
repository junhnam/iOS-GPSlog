import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S3-006 受け入れ条件:
///   (a) 自宅滞在開始で SLC 起動
///   (b) 自宅退出で通常 GPS 復帰
///   (c) 高速移動で desiredAccuracy 上昇（Best）
///   (d) 停止で desiredAccuracy 低下（HundredMeters）
///   + 自宅未登録時は SLC が無効
@MainActor
final class SignificantLocationChangesTests: XCTestCase {

    private var retainedContainers: [ModelContainer] = []

    override func tearDown() async throws {
        await MainActor.run {
            retainedContainers.removeAll()
        }
        try await super.tearDown()
    }

    private func makeInMemoryRepository() throws -> TripRepository {
        let container = try PersistenceController.makeInMemoryContainer()
        retainedContainers.append(container)
        return TripRepository(modelContext: container.mainContext)
    }

    private func makeIsolatedSettings() -> AppSettings {
        let suiteName = "gpslogger.tests.slc.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppSettings(defaults: defaults)
    }

    private func location(lat: Double, lon: Double, at offset: TimeInterval, base: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                   timestamp: base.addingTimeInterval(offset))
    }

    // MARK: - (a) 自宅滞在開始で SLC 起動 + 通常 GPS 停止

    func test_atHomeTransition_startsSLCAndStopsRegularUpdates() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 100

        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()
        XCTAssertTrue(mock.didStartUpdating)

        // 自宅外 -> 自宅内に遷移
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 0, base: base)]) // away
        XCTAssertEqual(sut._lastHomeStateForTesting, .away)
        XCTAssertFalse(sut.isMonitoringSignificantChanges)

        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 5, base: base)]) // home
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)
        XCTAssertTrue(sut.isMonitoringSignificantChanges)
        XCTAssertTrue(mock.didStartSLC)
        XCTAssertTrue(mock.didStopUpdating)
    }

    // MARK: - (b) 自宅退出で SLC 停止 + 通常 GPS 再開

    func test_awayTransition_stopsSLCAndResumesRegularUpdates() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 100

        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 自宅滞在 → SLC オン
        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 0, base: base)])
        XCTAssertTrue(sut.isMonitoringSignificantChanges)

        // 退出 → SLC オフ + 通常 GPS 再開
        mock.didStartUpdating = false // クリアして「再開」を測れるようにする
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 10, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .away)
        XCTAssertFalse(sut.isMonitoringSignificantChanges)
        XCTAssertTrue(mock.didStopSLC)
        XCTAssertTrue(mock.didStartUpdating)
    }

    // MARK: - (c) 高速移動で Best

    func test_fastMotion_increasesAccuracyToBest() throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // まず HundredMeters に倒すため停止状態を作る
        // 20 秒ほぼ同じ点 → HundredMeters
        for i in 0...4 {
            sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: TimeInterval(i * 5), base: base)])
        }
        XCTAssertEqual(sut.dynamicAccuracy, .hundredMeters)

        // 直後に 5 秒以内で 50m（緯度 0.0005 度 ≒ 約 55m）動く
        sut._ingestForTesting([location(lat: 35.681736, lon: 139.767125, at: 22, base: base)])
        XCTAssertEqual(sut.dynamicAccuracy, .best)
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyBest)
    }

    // MARK: - (d) 停止で HundredMeters

    func test_stalledMotion_decreasesAccuracyToHundredMeters() throws {
        let repo = try makeInMemoryRepository()
        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 20 秒以上、ほぼ同じ点を継続 → HundredMeters
        for i in 0...4 {
            sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: TimeInterval(i * 5), base: base)])
        }
        XCTAssertEqual(sut.dynamicAccuracy, .hundredMeters)
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyHundredMeters)
    }

    // MARK: - 自宅未登録時は SLC 無効

    func test_noHomeRegistered_doesNotEnableSLC() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings() // 自宅未登録
        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)

        sut.startSignificantChangesIfHome()
        XCTAssertFalse(sut.isMonitoringSignificantChanges)
        XCTAssertFalse(mock.didStartSLC)
    }
}

// MARK: - Mock provider

/// LocationProviderProtocol のモック。
/// SLC オン/オフ・desiredAccuracy 変更をフラグで観測できる。
/// `LocationProviderProtocol` は `CLLocationManager` （非 main isolated）に合わせて
/// nonisolated 要件で宣言されているため、本モックも nonisolated で実装する。
/// テストはすべて `@MainActor` だが、モック自体は同一スレッドでしかアクセスされず
/// データ競合は発生しないので `@unchecked Sendable` で扱う。
final class MockLocationProvider: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest {
        didSet { lastDesiredAccuracy = desiredAccuracy }
    }
    var distanceFilter: CLLocationDistance = 10
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    var lastDesiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest

    var didStartUpdating: Bool = false
    var didStopUpdating: Bool = false
    var didStartSLC: Bool = false
    var didStopSLC: Bool = false

    func requestWhenInUseAuthorization() {}
    func requestAlwaysAuthorization() {}
    func startUpdatingLocation() { didStartUpdating = true }
    func stopUpdatingLocation() { didStopUpdating = true }
    func startMonitoringSignificantLocationChanges() { didStartSLC = true }
    func stopMonitoringSignificantLocationChanges() { didStopSLC = true }
}

import XCTest
import CoreLocation
import SwiftData
@testable import GPSLogger

/// S3-006 / S6-017 受け入れ条件:
///   (a) 自宅滞在開始で低精度通常 GPS モードに移行（S6-017 修正: SLC ではなく通常 GPS 維持）
///   (b) 自宅退出で通常精度（Best）に復元
///   (c) 高速移動で desiredAccuracy 上昇（Best）
///   (d) 停止で desiredAccuracy 低下（HundredMeters）
///   + 自宅未登録時は SLC が無効（通常 GPS モードへの切替も行わない）
///
/// ### S6-017 仕様変更の背景
/// 旧実装: 自宅滞在時に通常 GPS を停止して SLC に切り替えていた。
///   → Apple の SLC は「500m〜1km 動かないと配信されない」ため、自宅 70m を出ても
///     500m 動くまで位置情報が来ず atHome のまま記録されないバグが発生。
/// 新実装: 通常 GPS を維持したまま低精度（100m）・大 distanceFilter（100m）に切り替える。
///   → 70m〜100m 外に出た瞬間に didUpdateLocations が発火 → away 判定 → 精度復元。
///
/// ### 影響した既存テスト（S6-017 で書き換え）
///   - test_atHomeTransition_startsSLCAndStopsRegularUpdates
///     旧: SLC 開始 + 通常 GPS 停止を検証 → 新: 低精度通常 GPS 維持を検証
///   - test_awayTransition_stopsSLCAndResumesRegularUpdates
///     旧: SLC 停止 + 通常 GPS 再開を検証 → 新: 精度復元（Best / kCLDistanceFilterNone）を検証
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

    // MARK: - (a) 自宅滞在開始で低精度通常 GPS モードに移行（S6-017）
    //
    // 旧テスト名: test_atHomeTransition_startsSLCAndStopsRegularUpdates
    // 変更理由 (S6-017): SLC を廃止し、低精度通常 GPS モードに移行する仕様変更のため。
    //   旧実装: startMonitoringSignificantLocationChanges() 呼び出し + stopUpdatingLocation() を期待
    //   新実装: isUpdating=true を維持 / desiredAccuracy=100m / distanceFilter=100m / SLC 呼び出しなし

    func test_atHomeTransition_setsLowAccuracyGPS_andKeepsUpdating_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 100
        settings.wasTracking = true

        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()
        XCTAssertTrue(mock.didStartUpdating, "前提: 通常 GPS が開始されている")

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 自宅外 -> 自宅内に遷移
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 0, base: base)]) // away
        XCTAssertEqual(sut._lastHomeStateForTesting, .away)
        XCTAssertFalse(sut.isMonitoringSignificantChanges, "away 中は SLC 非活性")

        // リセットして atHome 遷移時の変化のみを観測
        mock.didStopUpdating = false
        mock.didStartSLC = false

        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 5, base: base)]) // home
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)

        // S6-017: 低精度通常 GPS モードに移行（SLC は使わない）
        XCTAssertTrue(sut.isUpdating,
            "S6-017: 自宅滞在中も isUpdating=true を維持する（通常 GPS を停止しない）")
        XCTAssertFalse(mock.didStopUpdating,
            "S6-017: stopUpdatingLocation() は呼ばれない（通常 GPS 停止しない）")
        XCTAssertFalse(mock.didStartSLC,
            "S6-017: SLC は使わない（startMonitoringSignificantLocationChanges() を呼ばない）")
        XCTAssertFalse(sut.isMonitoringSignificantChanges,
            "S6-017: isMonitoringSignificantChanges=false のまま")
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyHundredMeters,
            "S6-017: 自宅滞在中は desiredAccuracy=HundredMeters（省電力）")
        XCTAssertEqual(mock.lastDistanceFilter, 100,
            "S6-017: 自宅滞在中は distanceFilter=100m（省電力）")
    }

    // MARK: - (b) 自宅退出で通常精度に復元（S6-017）
    //
    // 旧テスト名: test_awayTransition_stopsSLCAndResumesRegularUpdates
    // 変更理由 (S6-017): away 遷移時に SLC を停止するのではなく、精度を Best に復元する仕様変更のため。
    //   旧実装: stopMonitoringSignificantLocationChanges() + didStartUpdating=true を期待
    //   新実装: desiredAccuracy=Best / distanceFilter=kCLDistanceFilterNone に戻る
    //           isUpdating=true は atHome 中も維持されているため「再開」ではなく「精度復元」

    func test_awayTransition_restoresNormalAccuracy_S6017() throws {
        let repo = try makeInMemoryRepository()
        let settings = makeIsolatedSettings()
        settings.homeLocation = HomeLocation(latitude: 35.681236, longitude: 139.767125, address: "Home")
        settings.homeRadiusMeters = 100
        settings.wasTracking = true

        let mock = MockLocationProvider()
        let sut = LocationService(manager: mock, repository: repo, appSettings: settings)
        sut.startUpdatingLocation()

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // 自宅外 → 自宅内（低精度 GPS モードへ）
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 0, base: base)])
        sut._ingestForTesting([location(lat: 35.681236, lon: 139.767125, at: 5, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .atHome)
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyHundredMeters,
            "前提: 自宅滞在中は低精度モード")

        // 自宅内 → 自宅外（精度復元）
        mock.didStartUpdating = false // クリアして「再開」を測れるようにする
        sut._ingestForTesting([location(lat: 35.700000, lon: 139.767125, at: 10, base: base)])
        XCTAssertEqual(sut._lastHomeStateForTesting, .away)

        // S6-017: away に出たら精度を通常に復元する
        XCTAssertFalse(sut.isMonitoringSignificantChanges,
            "S6-017: SLC は使わないので isMonitoringSignificantChanges=false のまま")
        XCTAssertEqual(mock.lastDesiredAccuracy, kCLLocationAccuracyBest,
            "S6-017: away 遷移時に desiredAccuracy=Best に復元する")
        XCTAssertEqual(mock.lastDistanceFilter, kCLDistanceFilterNone,
            "S6-017: away 遷移時に distanceFilter=kCLDistanceFilterNone（デフォルト）に戻す")
        XCTAssertTrue(sut.isUpdating,
            "S6-017: away 遷移後も isUpdating=true（atHome 中も維持していたため）")
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

    // MARK: - 自宅未登録時は SLC も低精度 GPS モードも無効

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
/// SLC オン/オフ・desiredAccuracy / distanceFilter 変更をフラグで観測できる。
/// `LocationProviderProtocol` は `CLLocationManager` （非 main isolated）に合わせて
/// nonisolated 要件で宣言されているため、本モックも nonisolated で実装する。
/// テストはすべて `@MainActor` だが、モック自体は同一スレッドでしかアクセスされず
/// データ競合は発生しないので `@unchecked Sendable` で扱う。
final class MockLocationProvider: NSObject, LocationProviderProtocol, @unchecked Sendable {
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest {
        didSet { lastDesiredAccuracy = desiredAccuracy }
    }
    var distanceFilter: CLLocationDistance = 10 {
        didSet { lastDistanceFilter = distanceFilter }
    }
    var activityType: CLActivityType = .other
    var pausesLocationUpdatesAutomatically: Bool = true
    var allowsBackgroundLocationUpdates: Bool = true
    var showsBackgroundLocationIndicator: Bool = true
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var delegate: CLLocationManagerDelegate?

    var lastDesiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var lastDistanceFilter: CLLocationDistance = 10

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
